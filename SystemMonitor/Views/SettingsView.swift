import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 260)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var metrics = MetricsService.shared
    @State private var launchAtLogin: Bool = AppPreferences.shared.launchAtLogin

    var body: some View {
        Form {
            Picker("Menu bar display:", selection: Binding(
                get: { prefs.menuBarDisplay },
                set: { prefs.menuBarDisplay = $0 }
            )) {
                ForEach(MenuBarDisplay.allCases) { m in
                    Text(m.title).tag(m)
                }
            }

            Picker("Update every:", selection: Binding(
                get: { UpdateInterval(rawValue: prefs.updateInterval) ?? .normal },
                set: { new in
                    prefs.updateInterval = new.rawValue
                    metrics.updateInterval = TimeInterval(new.rawValue)
                    metrics.restart()
                }
            )) {
                ForEach(UpdateInterval.allCases) { i in
                    Text(i.title).tag(i)
                }
            }

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    prefs.launchAtLogin = newValue
                    launchAtLogin = prefs.launchAtLogin
                }
            ))
        }
        .padding(24)
    }
}

struct AboutView: View {
    @ObservedObject private var updater = UpdaterController.shared

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("System Monitor")
                .font(.title2).bold()
            Text("Version \(versionString)")
                .foregroundStyle(.secondary)
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheck)
            Text("© LAB37")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
}
