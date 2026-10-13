import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var metrics: MetricsService
    @EnvironmentObject private var prefs: AppPreferences
    @Environment(\.openSettings) private var openSettings
    @State private var processTab: ProcessListView.Tab = .cpu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let s = metrics.snapshot {
                if !s.alerts.isEmpty {
                    AlertBanner(alerts: s.alerts)
                }

                gauges(for: s)

                Divider()

                NetworkChartView(sample: s.network, scale: prefs.networkScale)

                Divider()

                ProcessListView(
                    tab: $processTab,
                    topCPU: s.topCPU,
                    topMemory: s.topMemory
                )
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Starting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tint)
            Text("System Monitor")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Spacer()
        }
    }

    @ViewBuilder
    private func gauges(for s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GaugeRow(
                icon: MetricKind.cpu.icon,
                label: MetricKind.cpu.title,
                value: s.cpu.overall,
                valueText: String(format: "%.0f%%", s.cpu.overall),
                history: s.history.cpu,
                historyCapacity: s.history.capacity,
                subline: coreSubline(for: s.cpu),
                isAlerting: s.alert(for: .cpu) != nil
            )

            if let gpu = s.gpu.utilization {
                GaugeRow(
                    icon: MetricKind.gpu.icon,
                    label: MetricKind.gpu.title,
                    value: gpu,
                    valueText: String(format: "%.0f%%", gpu),
                    history: s.history.gpu,
                    historyCapacity: s.history.capacity,
                    isAlerting: s.alert(for: .gpu) != nil
                )
            }

            GaugeRow(
                icon: MetricKind.memory.icon,
                label: MetricKind.memory.title,
                value: s.memory.percent,
                valueText: String(format: "%.0f%%", s.memory.percent),
                history: s.history.memory,
                historyCapacity: s.history.capacity,
                subline: memorySubline(for: s.memory),
                isAlerting: s.alert(for: .memory) != nil
            )

            GaugeRow(
                icon: MetricKind.disk.icon,
                label: MetricKind.disk.title,
                value: s.disk.percent,
                valueText: String(format: "%.0f%%", s.disk.percent),
                history: s.history.disk,
                historyCapacity: s.history.capacity,
                subline: diskSubline(for: s.disk),
                isAlerting: s.alert(for: .disk) != nil
            )

            if let c = s.claude {
                GaugeRow(
                    icon: MetricKind.claude.icon,
                    label: MetricKind.claude.title,
                    value: c.fiveHourPercent,
                    valueText: String(format: "%.0f%%", c.fiveHourPercent),
                    subline: claudeSubline(for: c),
                    isAlerting: s.alert(for: .claude) != nil
                )
            }

            if let b = s.battery {
                GaugeRow(
                    icon: b.externalPower ? "battery.100percent.bolt" : "battery.75percent",
                    label: "Battery",
                    value: b.percent,
                    valueText: String(format: "%.0f%%", b.percent),
                    subline: batterySubline(for: b),
                    colorValue: 100 - b.percent
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private func coreSubline(for cpu: CPUSample) -> String? {
        var parts: [String] = []
        if cpu.eCount > 0 {
            let pAvg = cpu.pCores.isEmpty ? 0 : cpu.pCores.reduce(0, +) / Double(cpu.pCores.count)
            let eAvg = cpu.eCores.isEmpty ? 0 : cpu.eCores.reduce(0, +) / Double(cpu.eCores.count)
            parts.append(String(format: "P %.0f%%  ·  E %.0f%%", pAvg, eAvg))
        }
        // Nominal is the norm; only spend words on it when the fans have a reason.
        switch cpu.thermal {
        case .fair: parts.append("Thermal fair")
        case .serious: parts.append("Thermal serious")
        case .critical: parts.append("Thermal critical")
        default: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private func claudeSubline(for c: ClaudeSample) -> String {
        var parts = [String(format: "7d %.0f%%", c.sevenDayPercent)]
        if let reset = c.fiveHourResetsAt, reset > Date() {
            parts.append("5h resets " + reset.formatted(date: .omitted, time: .shortened))
        }
        if let cost = c.sessionCostUSD {
            parts.append(String(format: "$%.2f session", cost))
        }
        // The file only moves while a Claude Code session runs; say so when it hasn't.
        let age = Date().timeIntervalSince(c.updatedAt)
        if age > 600 { parts.append("updated \(Int(age / 60)) min ago") }
        return parts.joined(separator: "  ·  ")
    }

    private func batterySubline(for b: BatterySample) -> String {
        let state = b.isCharging ? "Charging" : b.externalPower ? "On power" : "On battery"
        return state + String(format: "  ·  %.1f W %@", abs(b.watts), b.watts >= 0 ? "in" : "draw")
    }

    private func memorySubline(for m: MemorySample) -> String {
        let base = String(format: "%.1f / %.0f GB", m.usedGB, m.totalGB)
        if m.swapUsedGB > 0.1 {
            return base + String(format: "  ·  Swap %.1f GB", m.swapUsedGB)
        }
        return base
    }

    private func diskSubline(for d: DiskSample) -> String {
        let base = String(format: "%.0f GB free of %.0f", d.freeGB, d.totalGB)
        // Idle disks are the norm; only spend the line on I/O when there is any.
        let busy = max(d.readBps, d.writeBps) > 512 * 1024
        guard busy else { return base }
        return base + "  ·  R \(formatByteRate(d.readBps))  ·  W \(formatByteRate(d.writeBps))"
    }
}

/// Sustained breaches, called out above the gauges. The gauge rows also turn
/// red, but a metric that's been pinned for half a minute deserves a sentence
/// rather than only a colour.
struct AlertBanner: View {
    let alerts: [MetricAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(alerts) { alert in
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text("\(alert.metric.title) over \(Int(alert.threshold))% for \(durationText(alert.sustainedSeconds))")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }

    private func durationText(_ seconds: Int) -> String {
        seconds >= 120 ? "\(seconds / 60) min" : "\(seconds)s"
    }
}

#Preview {
    PanelView()
        .environmentObject(MetricsService.shared)
        .environmentObject(AppPreferences.shared)
}
