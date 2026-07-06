import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        VStack(spacing: 14) {
            HeaderView(monitor: monitor)

            if let latest = monitor.latest {
                GaugeRow(sample: latest, capacityWatts: monitor.capacityWatts)
                HistoryView(samples: monitor.history, capacityWatts: monitor.capacityWatts)
                DetailGrid(sample: latest)
            } else {
                EmptyStateView(error: monitor.lastError)
            }

            SettingsView(monitor: monitor)
            FooterView(monitor: monitor)
        }
        .foregroundStyle(.primary)
    }
}

private struct HeaderView: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Growatt")
                    .font(.system(size: 22, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            Spacer()

            if let latest = monitor.latest {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PowerFormatting.kilowatts(latest.acWatts, digits: 2))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(PowerFormatting.watts(latest.acWatts)) · AC output")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusText: String {
        if let error = monitor.lastError {
            return error
        }
        if let latest = monitor.latest {
            return "\(latest.statusText) · \(latest.timestamp.formatted(date: .omitted, time: .standard))"
        }
        return "Connecting"
    }

    private var statusColor: Color {
        if monitor.lastError != nil {
            return .orange
        }
        if monitor.latest?.status == 1 {
            return .green
        }
        return .secondary
    }
}

private struct GaugeRow: View {
    let sample: PowerSample
    let capacityWatts: Double

    var body: some View {
        HStack(spacing: 12) {
            MetricGauge(
                title: "PV",
                value: sample.pvWatts / 1000,
                unit: "kW",
                detail: PowerFormatting.watts(sample.pvWatts),
                fraction: sample.pvWatts / max(capacityWatts, 1),
                color: .yellow,
                digits: 2
            )
            MetricGauge(
                title: "AC",
                value: sample.acWatts / 1000,
                unit: "kW",
                detail: PowerFormatting.watts(sample.acWatts),
                fraction: sample.acWatts / max(capacityWatts, 1),
                color: .blue,
                digits: 2
            )
            MetricGauge(
                title: "Temp",
                value: sample.inverterTempC,
                unit: "C",
                detail: "Inverter",
                fraction: min(sample.inverterTempC / 80, 1),
                color: .orange,
                digits: 1
            )
        }
    }
}

private struct MetricGauge: View {
    let title: String
    let value: Double
    let unit: String
    let detail: String
    let fraction: Double
    let color: Color
    let digits: Int

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(.secondary.opacity(0.28), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(90))
                Circle()
                    .trim(from: 0.15, to: 0.15 + 0.7 * min(max(fraction, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(90))
                VStack(spacing: 0) {
                    Text(value, format: .number.precision(.fractionLength(digits)))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 94, height: 74)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryView: View {
    let samples: [PowerSample]
    let capacityWatts: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Power History")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(samples.count) samples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PowerHistoryCanvas(samples: samples, capacityWatts: capacityWatts)
                .frame(height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PowerHistoryCanvas: View {
    let samples: [PowerSample]
    let capacityWatts: Double

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(.black.opacity(0.08)))

            guard samples.count > 1 else { return }

            let maxPower = max(capacityWatts, samples.map(\.acWatts).max() ?? 1, 1)
            let points = samples.enumerated().map { index, sample in
                let x = size.width * CGFloat(index) / CGFloat(samples.count - 1)
                let y = size.height - (CGFloat(sample.acWatts / maxPower) * size.height)
                return CGPoint(x: x, y: max(0, min(size.height, y)))
            }

            var area = Path()
            area.move(to: CGPoint(x: points[0].x, y: size.height))
            for point in points {
                area.addLine(to: point)
            }
            area.addLine(to: CGPoint(x: points.last?.x ?? size.width, y: size.height))
            area.closeSubpath()

            let gradient = Gradient(colors: [.blue.opacity(0.72), .cyan.opacity(0.18)])
            context.fill(area, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() {
                line.addLine(to: point)
            }
            context.stroke(line, with: .color(.blue), lineWidth: 2)
        }
    }
}

private struct DetailGrid: View {
    let sample: PowerSample

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                DetailTile(title: "PV1", primary: power(sample.pv1Watts), secondary: "\(PowerFormatting.watts(sample.pv1Watts)) · \(one(sample.pv1Volts)) V · \(one(sample.pv1Amps)) A", color: .yellow)
                DetailTile(title: "PV2", primary: power(sample.pv2Watts), secondary: "\(PowerFormatting.watts(sample.pv2Watts)) · \(one(sample.pv2Volts)) V · \(one(sample.pv2Amps)) A", color: .orange)
            }

            HStack(spacing: 10) {
                DetailTile(title: "Today", primary: "\(one(sample.todayKWh)) kWh", secondary: "Generated", color: .green)
                DetailTile(title: "Total", primary: "\(one(sample.totalKWh)) kWh", secondary: "Lifetime", color: .teal)
            }

            HStack(spacing: 10) {
                DetailTile(title: "Grid", primary: "\(one(sample.gridVolts)) V", secondary: "\(two(sample.gridHz)) Hz", color: .blue)
                DetailTile(title: "Boost", primary: "\(one(sample.boostTempC)) C", secondary: "Temperature", color: .red)
            }
        }
    }

    private func power(_ value: Double) -> String {
        PowerFormatting.kilowatts(value, digits: 2)
    }

    private func one(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func two(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}

private struct DetailTile: View {
    let title: String
    let primary: String
    let secondary: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(primary)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text(secondary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SettingsView: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        DisclosureGroup {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    Text("Host")
                        .foregroundStyle(.secondary)
                    TextField("192.168.31.5", text: $monitor.host)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Port")
                        .foregroundStyle(.secondary)
                    TextField("502", value: $monitor.port, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Unit")
                        .foregroundStyle(.secondary)
                    Stepper(value: $monitor.unit, in: 1...247) {
                        Text("\(monitor.unit)")
                    }
                }
                GridRow {
                    Text("Poll")
                        .foregroundStyle(.secondary)
                    Stepper(value: $monitor.interval, in: 5...60, step: 5) {
                        Text("\(Int(monitor.interval)) seconds")
                    }
                }
                GridRow {
                    Text("Capacity")
                        .foregroundStyle(.secondary)
                    Stepper(value: $monitor.capacityWatts, in: 1000...30000, step: 500) {
                        Text(PowerFormatting.kilowatts(monitor.capacityWatts, digits: 1))
                    }
                }
            }
            .font(.system(size: 13))
            .padding(.top, 8)
        } label: {
            Label("Connection", systemImage: "network")
                .font(.system(size: 13, weight: .semibold))
        }
    }
}

private struct EmptyStateView: View {
    let error: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: error == nil ? "sun.max" : "exclamationmark.triangle")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(error == nil ? .yellow : .orange)
            Text(error ?? "Waiting for inverter data")
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(error == nil ? .secondary : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct FooterView: View {
    @ObservedObject var monitor: PowerMonitor

    var body: some View {
        HStack {
            Button {
                monitor.refreshNow()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
                monitor.restart()
            } label: {
                Label("Restart", systemImage: "play.circle")
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13, weight: .medium))
    }
}
