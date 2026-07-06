import Darwin
import Foundation

struct PowerSample: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let status: Int
    let pvWatts: Double
    let acWatts: Double
    let pv1Watts: Double
    let pv1Volts: Double
    let pv1Amps: Double
    let pv2Watts: Double
    let pv2Volts: Double
    let pv2Amps: Double
    let todayKWh: Double
    let totalKWh: Double
    let gridVolts: Double
    let gridHz: Double
    let inverterTempC: Double
    let boostTempC: Double
}

struct GrowattModbusClient: Sendable {
    let host: String
    let port: Int
    let unit: UInt8
    let timeoutSeconds: Double
    let blockDelaySeconds: Double

    init(
        host: String,
        port: Int = 502,
        unit: UInt8 = 1,
        timeoutSeconds: Double = 4.0,
        blockDelaySeconds: Double = 1.0
    ) {
        self.host = host
        self.port = port
        self.unit = unit
        self.timeoutSeconds = timeoutSeconds
        self.blockDelaySeconds = blockDelaySeconds
    }

    func readSnapshot() throws -> PowerSample {
        var registers: [Int: UInt16] = [:]

        // Growatt Modbus protocol v1.24, Input Reg first group.
        // Keep reads small because ShineWiFi-X can time out on large ranges.
        for block in [(0, 11), (35, 7), (53, 4), (91, 13)] {
            let values = try readInputRegisters(start: block.0, count: block.1)
            for (offset, value) in values.enumerated() {
                registers[block.0 + offset] = value
            }
            Thread.sleep(forTimeInterval: blockDelaySeconds)
        }

        func reg(_ index: Int) -> Double {
            Double(registers[index] ?? 0)
        }

        func u32(_ highRegister: Int) -> Double {
            let high = UInt32(registers[highRegister] ?? 0)
            let low = UInt32(registers[highRegister + 1] ?? 0)
            return Double((high << 16) + low)
        }

        let ac = u32(35) / 10
        let acPhase = u32(40) / 10

        return PowerSample(
            timestamp: Date(),
            status: Int(registers[0] ?? 0),
            pvWatts: u32(1) / 10,
            acWatts: ac == 0 ? acPhase : ac,
            pv1Watts: u32(5) / 10,
            pv1Volts: reg(3) / 10,
            pv1Amps: reg(4) / 10,
            pv2Watts: u32(9) / 10,
            pv2Volts: reg(7) / 10,
            pv2Amps: reg(8) / 10,
            todayKWh: u32(53) / 10,
            totalKWh: u32(55) / 10,
            gridVolts: reg(38) / 10,
            gridHz: reg(37) / 100,
            inverterTempC: reg(93) / 10,
            boostTempC: reg(95) / 10
        )
    }

    private func readInputRegisters(start: Int, count: Int) throws -> [UInt16] {
        try readRegisters(function: 4, start: start, count: count)
    }

    private func readRegisters(function: UInt8, start: Int, count: Int) throws -> [UInt16] {
        let transactionID = UInt16.random(in: 1...UInt16.max)

        var request = Data()
        request.appendUInt16BE(transactionID)
        request.appendUInt16BE(0)
        request.appendUInt16BE(6)
        request.append(unit)
        request.append(function)
        request.appendUInt16BE(UInt16(start))
        request.appendUInt16BE(UInt16(count))

        let socketFD = try openSocket()
        defer {
            close(socketFD)
        }

        try sendAll(request, socketFD: socketFD)

        let header = try recvExact(7, socketFD: socketFD)
        let responseTransactionID = header.uint16BE(at: 0)
        let protocolID = header.uint16BE(at: 2)
        let length = Int(header.uint16BE(at: 4))
        let responseUnit = header[6]

        guard responseTransactionID == transactionID else {
            throw ModbusError.unexpectedResponse("wrong transaction id")
        }
        guard protocolID == 0 else {
            throw ModbusError.unexpectedResponse("protocol id \(protocolID)")
        }
        guard responseUnit == unit else {
            throw ModbusError.unexpectedResponse("unit \(responseUnit)")
        }

        let body = try recvExact(length - 1, socketFD: socketFD)
        guard let responseFunction = body.first else {
            throw ModbusError.connectionClosed
        }
        if responseFunction & 0x80 != 0 {
            let code = body.count > 1 ? body[1] : 0
            throw ModbusError.exception(code)
        }
        guard responseFunction == function else {
            throw ModbusError.unexpectedResponse("function \(responseFunction)")
        }

        let byteCount = Int(body[1])
        let data = body.dropFirst(2).prefix(byteCount)
        guard data.count % 2 == 0 else {
            throw ModbusError.unexpectedResponse("odd byte count")
        }

        var values: [UInt16] = []
        values.reserveCapacity(data.count / 2)
        let bytes = Array(data)
        for index in stride(from: 0, to: bytes.count, by: 2) {
            values.append((UInt16(bytes[index]) << 8) + UInt16(bytes[index + 1]))
        }
        return values
    }

    private func openSocket() throws -> Int32 {
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0 else {
            throw ModbusError.socket(String(cString: strerror(errno)))
        }

        var timeout = timeval(
            tv_sec: Int(timeoutSeconds),
            tv_usec: Int32((timeoutSeconds - floor(timeoutSeconds)) * 1_000_000)
        )
        setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian

        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            close(socketFD)
            throw ModbusError.invalidHost(host)
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard result == 0 else {
            let message = String(cString: strerror(errno))
            close(socketFD)
            throw ModbusError.socket(message)
        }

        return socketFD
    }

    private func sendAll(_ data: Data, socketFD: Int32) throws {
        var sent = 0
        let bytes = Array(data)
        while sent < bytes.count {
            let result = bytes.withUnsafeBytes { pointer in
                Darwin.send(
                    socketFD,
                    pointer.baseAddress!.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
            }
            guard result > 0 else {
                throw ModbusError.socket(String(cString: strerror(errno)))
            }
            sent += result
        }
    }

    private func recvExact(_ count: Int, socketFD: Int32) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)

        while data.count < count {
            var buffer = [UInt8](repeating: 0, count: count - data.count)
            let received = Darwin.recv(socketFD, &buffer, buffer.count, 0)
            if received == 0 {
                throw ModbusError.connectionClosed
            }
            guard received > 0 else {
                throw ModbusError.socket(String(cString: strerror(errno)))
            }
            data.append(contentsOf: buffer.prefix(received))
        }

        return data
    }
}

enum ModbusError: Error, LocalizedError {
    case invalidHost(String)
    case socket(String)
    case connectionClosed
    case exception(UInt8)
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            "Invalid host: \(host)"
        case .socket(let message):
            message
        case .connectionClosed:
            "Connection closed before response"
        case .exception(let code):
            "Modbus exception \(code)"
        case .unexpectedResponse(let message):
            "Unexpected response: \(message)"
        }
    }
}

private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) {
            append(contentsOf: $0)
        }
    }

    func uint16BE(at index: Int) -> UInt16 {
        (UInt16(self[index]) << 8) + UInt16(self[index + 1])
    }
}
