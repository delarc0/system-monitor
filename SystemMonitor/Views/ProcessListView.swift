import SwiftUI
import AppKit

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
                    Button {
                        ProcessActions.openActivityMonitor()
                    } label: {
                        row(for: entry)
                    }
                    .buttonStyle(RowButtonStyle())
                    .contextMenu {
                        Button("Open Activity Monitor") {
                            ProcessActions.openActivityMonitor()
                        }
                        if let bundlePath = entry.bundlePath {
                            Button("Reveal in Finder") {
                                ProcessActions.reveal(bundlePath)
                            }
                        }
                    }
                }
            }
        }
    }

    private func row(for entry: ProcessEntry) -> some View {
        HStack(spacing: 10) {
            icon(for: entry)
                .frame(width: 16, height: 16)

            Text(entry.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            // A merged row hides how many processes it represents; say so.
            if entry.instances > 1 {
                Text("×\(entry.instances)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(formatted(entry.value, tab: tab))
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .help(tooltip(for: entry))
    }

    @ViewBuilder
    private func icon(for entry: ProcessEntry) -> some View {
        if let bundlePath = entry.bundlePath {
            Image(nsImage: AppIconCache.icon(for: bundlePath))
                .resizable()
                .interpolation(.high)
        } else {
            // Not an app bundle: a daemon or a command-line binary.
            Image(systemName: "gearshape")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tooltip(for entry: ProcessEntry) -> String {
        let path = entry.instances > 1
            ? "\(entry.instances) processes · \(entry.executablePath)"
            : entry.executablePath
        return path + "\nClick to open Activity Monitor"
    }

    private func formatted(_ value: Double, tab: Tab) -> String {
        switch tab {
        case .cpu: return String(format: "%.1f%%", value)
        case .memory: return String(format: "%.2f GB", value)
        }
    }
}

/// A borderless row that highlights on hover, so it reads as clickable without
/// putting a button chrome on every line.
private struct RowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(hovering ? 0.07 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onHover { hovering = $0 }
    }
}

enum ProcessActions {
    /// Activity Monitor can't be told to select a specific process from the
    /// outside, so this opens it and leaves the user one step away.
    @MainActor
    static func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @MainActor
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

/// `NSWorkspace.icon(forFile:)` hits the filesystem, and these rows redraw on
/// every tick, so resolved icons are kept for the life of the process.
@MainActor
private enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundlePath: String) -> NSImage {
        if let hit = cache[bundlePath] { return hit }
        let image = NSWorkspace.shared.icon(forFile: bundlePath)
        if cache.count >= 128 { cache.removeAll() }
        cache[bundlePath] = image
        return image
    }
}
