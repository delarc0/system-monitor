import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var metrics: MetricsService
    @Environment(\.openSettings) private var openSettings
    @State private var processTab: ProcessListView.Tab = .cpu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let s = metrics.snapshot {
                gauges(for: s)

                Divider()

                NetworkChartView(sample: s.network)

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
        .frame(width: 340)
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
                icon: "cpu",
                label: "CPU",
                value: s.cpu.overall,
                valueText: String(format: "%.0f%%", s.cpu.overall),
                subline: coreSubline(for: s.cpu)
            )

            if let gpu = s.gpu.utilization {
                GaugeRow(
                    icon: "display",
                    label: "GPU",
                    value: gpu,
                    valueText: String(format: "%.0f%%", gpu)
                )
            }

            GaugeRow(
                icon: "memorychip",
                label: "Memory",
                value: s.memory.percent,
                valueText: String(format: "%.0f%%", s.memory.percent),
                subline: memorySubline(for: s.memory)
            )
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
        guard cpu.eCount > 0 else { return nil }
        let pAvg = cpu.pCores.isEmpty ? 0 : cpu.pCores.reduce(0, +) / Double(cpu.pCores.count)
        let eAvg = cpu.eCores.isEmpty ? 0 : cpu.eCores.reduce(0, +) / Double(cpu.eCores.count)
        return String(format: "P %.0f%%  ·  E %.0f%%", pAvg, eAvg)
    }

    private func memorySubline(for m: MemorySample) -> String {
        let base = String(format: "%.1f / %.0f GB", m.usedGB, m.totalGB)
        if m.swapUsedGB > 0.1 {
            return base + String(format: "  ·  Swap %.1f GB", m.swapUsedGB)
        }
        return base
    }
}

#Preview {
    PanelView()
        .environmentObject(MetricsService.shared)
}
