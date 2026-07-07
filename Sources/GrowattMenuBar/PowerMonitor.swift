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
    @Published private(set) var nightFallbackActive = false
    @Published private(set) var fallbackDetail = ""

    private var task: Task<Void, Never>?

    // Camaçari-friendly solar schedule: normal day, dusk fallback, quiet night, sparse wake checks.
    private let duskWatchStartHour = 16
    private let nightQuietStartHour = 18
    private let morningWakeStartHour = 3
    private let morningWakeEndHour = 6
    private let wakeProbeIntervalSeconds: Double = 300
    private let nightQuietIntervalSeconds: Double = 1_800

    var menuSymbol: String {
        if nightFallbackActive {
            return "moon.stars.fill"
        }
        if lastError != nil {
            return "exclamationmark.triangle.fill"
        }
        return "sun.max.fill"
    }

    var menuTitle: String {
        if nightFallbackActive {
            return "Sun down"
        }
        if let latest {
            return "AC \(PowerFormatting.kilowatts(latest.acWatts, digits: 2))"
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
            await self?.readOnce(phase: self?.pollPhase() ?? .normal)
        }
    }

    func restart() {
        stop()
        start()
    }

    private func runLoop() async {
        while !Task.isCancelled {
            let phase = pollPhase()
            if phase == .nightQuiet {
                enterFallback(for: phase)
            } else {
                await readOnce(phase: phase)
            }

            let sleepSeconds = nextSleepSeconds(for: pollPhase())
            try? await Task.sleep(for: .seconds(sleepSeconds))
        }
    }

    private func readOnce(phase: PollPhase) async {
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
            fallbackDetail = ""
            nightFallbackActive = false
            history.append(sample)
            if history.count > 180 {
                history.removeFirst(history.count - 180)
            }
        } catch {
            if phase.suppressesReadErrors {
                enterFallback(for: phase)
            } else {
                lastError = error.localizedDescription
                fallbackDetail = ""
                nightFallbackActive = false
            }
        }
    }

    var fallbackStatusText: String {
        fallbackDetail.isEmpty ? "Sun down" : "Sun down · \(fallbackDetail)"
    }

    var fallbackWindowText: String {
        "quiet \(formatHour(nightQuietStartHour))-\(formatHour(morningWakeStartHour)), wake checks \(formatHour(morningWakeStartHour))-\(formatHour(morningWakeEndHour))"
    }

    private func enterFallback(for phase: PollPhase) {
        latest = nil
        lastUpdated = Date()
        lastError = nil
        fallbackDetail = phase.fallbackDetail
        nightFallbackActive = true
    }

    private func nextSleepSeconds(for phase: PollPhase) -> Double {
        switch phase {
        case .normal:
            return normalPollIntervalSeconds
        case .duskWatch:
            return nightFallbackActive ? wakeProbeIntervalSeconds : normalPollIntervalSeconds
        case .nightQuiet:
            return nightQuietIntervalSeconds
        case .morningWake:
            return nightFallbackActive || latest == nil ? wakeProbeIntervalSeconds : normalPollIntervalSeconds
        }
    }

    private var normalPollIntervalSeconds: Double {
        max(5, interval)
    }

    private func pollPhase(date: Date = Date()) -> PollPhase {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= nightQuietStartHour || hour < morningWakeStartHour {
            return .nightQuiet
        }
        if hour < morningWakeEndHour {
            return .morningWake
        }
        if hour >= duskWatchStartHour {
            return .duskWatch
        }
        return .normal
    }

    private func formatHour(_ hour: Int) -> String {
        "\(String(format: "%02d", hour)):00"
    }
}

private enum PollPhase {
    case normal
    case duskWatch
    case nightQuiet
    case morningWake

    var suppressesReadErrors: Bool {
        switch self {
        case .normal:
            return false
        case .duskWatch, .nightQuiet, .morningWake:
            return true
        }
    }

    var fallbackDetail: String {
        switch self {
        case .normal:
            return ""
        case .duskWatch:
            return "dusk watch"
        case .nightQuiet:
            return "quiet"
        case .morningWake:
            return "wake check"
        }
    }
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
