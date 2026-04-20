import SwiftUI

/// Menu-bar status item content. Renders segments per the current display preference
/// with per-segment color-coded percentages.
struct MenuBarLabel: View {
    let snapshot: Snapshot?
    let display: MenuBarDisplay

    var body: some View {
        if let snap = snapshot {
            HStack(spacing: 4) {
                segment(snap.cpu.overall)
                if showsMemory {
                    separator
                    segment(snap.memory.percent)
                }
                if showsGPU, let gpu = snap.gpu.utilization {
                    separator
                    segment(gpu)
                }
            }
            .monospacedDigit()
            .font(.system(size: 12, weight: .medium, design: .rounded))
        } else {
            Text("—%")
        }
    }

    private var showsMemory: Bool { display == .cpuMem || display == .all }
    private var showsGPU: Bool { display == .cpuGpu || display == .all }

    @ViewBuilder
    private func segment(_ pct: Double) -> some View {
        Text(String(format: "%.0f%%", pct))
            .foregroundStyle(loadColor(pct))
    }

    private var separator: some View {
        Text("·").foregroundStyle(.secondary)
    }
}
