import SwiftUI

/// The notch readout. Collapsed it is a clear hover target the size of the
/// notch; expanded it is a black tab hanging from the screen edge with the
/// readout below the notch. Only the expanded branch observes `metrics`, so a
/// collapsed island costs nothing per tick (same lesson as the popover).
struct IslandView: View {
    let notchSize: CGSize
    /// Returns the effective state: the controller refuses an exit while the
    /// pointer is still inside the panel, so the view follows its answer.
    let onHover: (Bool) -> Bool
    let onTap: () -> Void
    @State private var expanded = false

    var body: some View {
        ZStack(alignment: .top) {
            if expanded {
                IslandReadout()
                    .padding(.top, notchSize.height + 10)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            let effective = onHover(hovering)
            withAnimation(.easeOut(duration: 0.18)) { expanded = effective }
        }
        .onTapGesture(perform: onTap)
        .environment(\.colorScheme, .dark)
    }
}

private struct IslandReadout: View {
    @EnvironmentObject private var metrics: MetricsService

    var body: some View {
        if let s = metrics.snapshot {
            HStack(alignment: .center, spacing: 18) {
                trace("CPU", s.cpu.overall, s.history.cpu, s.history.capacity)
                trace("MEM", s.memory.percent, s.history.memory, s.history.capacity)

                VStack(alignment: .leading, spacing: 4) {
                    Label(formatByteRate(s.network.downloadBps), systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                    Label(formatByteRate(s.network.uploadBps), systemImage: "arrow.up")
                        .foregroundStyle(.orange)
                }
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
                .frame(width: 92, alignment: .leading)

                if let c = s.claude {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            bar("5h", c.fiveHourPercent)
                            bar("7d", c.sevenDayPercent)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
        } else {
            Text("Starting…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func trace(_ label: String, _ value: Double, _ history: [Double], _ capacity: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", value))
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
            }
            Sparkline(values: history, capacity: capacity, current: value, color: loadColor(value))
                .frame(height: 26)
        }
        .frame(width: 104)
    }

    private func bar(_ label: String, _ percent: Double) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(loadColor(percent))
                        .frame(width: max(4, geo.size.width * min(percent, 100) / 100))
                }
            }
            .frame(width: 84, height: 6)
            Text(String(format: "%.0f%%", percent))
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)
        }
    }
}
