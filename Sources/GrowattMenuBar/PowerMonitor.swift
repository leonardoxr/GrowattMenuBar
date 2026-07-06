import Foundation
import SwiftUI

@MainActor
final class PowerMonitor: ObservableObject {
    @AppStorage("growatt.host") var host: String = "192.168.31.5"
    @AppStorage("growatt.port") var port: Int = 502
    @AppStorage("growatt.unit") var unit: Int = 1
    @AppStorage("growatt.interval") var interval: Double = 10
    @AppStorage("growatt.capacityWatts") var capacityWatts: Double = 6000

    @Published private(set) var latest: PowerSample?
    @Published private(set) var history: [PowerSample] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastUpdated: Date?

    private var task: Task<Void, Never>?

    var menuSymbol: String {
        if lastError != nil {
            return "exclamationmark.triangle.fill"
        }
        return "sun.max.fill"
    }

    var menuTitle: String {
        if let latest {
            return "\(Self.wattsFormatter.string(from: NSNumber(value: latest.acWatts)) ?? "0")W"
        }
        if lastError != nil {
            return "Solar"
        }
        return "Solar"
    }

    func start() {
        guard task == nil else { return }
        isRunning = true
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.readOnce()
        }
    }

    func restart() {
        stop()
        start()
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await readOnce()
            let sleepSeconds = max(5, interval)
            try? await Task.sleep(for: .seconds(sleepSeconds))
        }
    }

    private func readOnce() async {
        let currentHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentPort = port
        let currentUnit = UInt8(clamping: unit)

        do {
            let sample = try await Task.detached(priority: .userInitiated) {
                let client = GrowattModbusClient(
                    host: currentHost,
                    port: currentPort,
                    unit: currentUnit,
                    timeoutSeconds: 5,
                    blockDelaySeconds: 1
                )
                return try client.readSnapshot()
            }.value

            latest = sample
            lastUpdated = sample.timestamp
            lastError = nil
            history.append(sample)
            if history.count > 180 {
                history.removeFirst(history.count - 180)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    static let wattsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

extension PowerSample {
    var statusText: String {
        switch status {
        case 0:
            return "Waiting"
        case 1:
            return "Normal"
        case 3:
            return "Fault"
        default:
            return "Status \(status)"
        }
    }
}
