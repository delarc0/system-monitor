import SwiftUI

struct ProcessListView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case cpu = "Top CPU"
        case memory = "Top Memory"
        var id: String { rawValue }
    }

    @Binding var tab: Tab
    let topCPU: [ProcessEntry]
    let topMemory: [ProcessEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            let items = tab == .cpu ? topCPU : topMemory
            if items.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(items) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 11))
                            .frame(width: 16)
                            .foregroundStyle(.tertiary)
                        Text(entry.name)
                            .font(.system(.caption, design: .default))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(formatted(entry.value, tab: tab))
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func formatted(_ value: Double, tab: Tab) -> String {
        switch tab {
        case .cpu: return String(format: "%.1f%%", value)
        case .memory: return String(format: "%.2f GB", value)
        }
    }
}
