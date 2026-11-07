import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var launchAtLogin = AppPreferences.shared.launchAtLogin

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Picker("Menu bar display", selection: $prefs.menuBarDisplay) {
                ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
            }

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    prefs.launchAtLogin = newValue
                    launchAtLogin = prefs.launchAtLogin
                }
            ))

            LabeledContent("Version", value: version)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
