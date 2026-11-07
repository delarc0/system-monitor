import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var metrics: MetricsService
    @Environment(\.openSettings) private var openSettings
    @State private var processTab: ProcessListView.Tab = .cpu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = metrics.snapshot {
                gauges(for: s)

                Divider()

                NetworkChartView(sample: s.network)

                Divider()

                ProcessListView(tab: $processTab, topCPU: metrics.processes.cpu, topMemory: metrics.processes.memory)
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

    @ViewBuilder
    private func gauges(for s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GaugeRow(icon: "cpu", label: "CPU", value: s.cpu.overall, history: s.history.cpu, subline: thermalSubline(s.cpu.thermal))

            if let gpu = s.gpu.utilization {
                GaugeRow(icon: "display", label: "GPU", value: gpu, history: s.history.gpu)
            }

            GaugeRow(
                icon: "memorychip",
                label: "Memory",
                value: s.memory.percent,
                history: s.history.memory,
                subline: memorySubline(s.memory),
                colorValue: s.memory.pressure.load
            )

            GaugeRow(icon: "internaldrive", label: "Disk", value: s.disk.percent, subline: diskSubline(s.disk), isAlerting: s.disk.isLow)

            if ClaudeSampler.binaryPath != nil {
                claudeRow
            }
        }
    }

    @ViewBuilder
    private var claudeRow: some View {
        if let claude = metrics.claude {
            GaugeRow(icon: "sparkles", label: "Claude", value: claude.percent, subline: claudeSubline(claude))
        } else {
            HStack(spacing: 10) {
                GaugeLabel(icon: "sparkles", label: "Claude")
                Spacer()
                Text("no data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            if UpdaterController.isConfigured {
                Button("Check for Updates…") { UpdaterController.shared.checkForUpdates() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    /// Nominal is the norm; only spend words on it when the fans have a reason.
    private func thermalSubline(_ thermal: ProcessInfo.ThermalState) -> String? {
        switch thermal {
        case .fair: return "Thermal fair"
        case .serious: return "Thermal serious"
        case .critical: return "Thermal critical"
        default: return nil
        }
    }

    private func claudeSubline(_ claude: ClaudeUsage) -> String {
        var parts = ["This week"]
        if let elapsed = claude.weekElapsed {
            parts[0] = String(format: "%.0f%% of week gone", elapsed * 100)
        }
        if let resets = claude.resets {
            parts.append("resets \(resets)")
        }
        // Normal cadence is 30 minutes, so anything older means the reads are failing.
        let hours = Int(Date().timeIntervalSince(claude.readAt) / 3600)
        if hours >= 1 { parts.append("\(hours) h old") }
        return parts.joined(separator: "  ·  ")
    }

    private func memorySubline(_ m: MemorySample) -> String {
        var parts = [String(format: "%.1f / %.0f GB", m.usedGB, m.totalGB)]
        if m.swapUsedGB > 0.1 { parts.append(String(format: "Swap %.1f GB", m.swapUsedGB)) }
        switch m.pressure {
        case .normal: break
        case .warning: parts.append("Pressure high")
        case .critical: parts.append("Pressure critical")
        }
        return parts.joined(separator: "  ·  ")
    }

    private func diskSubline(_ d: DiskSample) -> String {
        let base = String(format: "%.0f GB free of %.0f", d.freeGB, d.totalGB)
        // Idle disks are the norm; only spend the line on I/O when there is any.
        guard max(d.readBps, d.writeBps) > 512 * 1024 else { return base }
        return base + "  ·  R \(formatByteRate(d.readBps))  ·  W \(formatByteRate(d.writeBps))"
    }
}
