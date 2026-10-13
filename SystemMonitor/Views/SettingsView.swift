import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AlertSettingsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 340)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
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

            // Writing the preference is enough; MenuBarController observes it.
            Picker("Update every:", selection: Binding(
                get: { UpdateInterval(rawValue: prefs.updateInterval) ?? .normal },
                set: { prefs.updateInterval = $0.rawValue }
            )) {
                ForEach(UpdateInterval.allCases) { i in
                    Text(i.title).tag(i)
                }
            }

            Picker("Network graph scale:", selection: Binding(
                get: { prefs.networkScale },
                set: { prefs.networkScale = $0 }
            )) {
                ForEach(NetworkScale.allCases) { s in
                    Text(s.title).tag(s)
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
        .formStyle(.grouped)
    }
}

struct AlertSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var notificationDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Alert on sustained load", isOn: binding(\.enabled))
            } footer: {
                Text("A metric has to stay over its threshold for the whole window before it alerts, so ordinary spikes stay quiet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Thresholds") {
                // LabeledContent keeps each toggle in the Form's label column,
                // so these rows line up with the pickers below them instead of
                // spanning the full width on their own.
                ForEach(MetricKind.allCases) { metric in
                    thresholdRow(for: metric)
                }

                Picker("Sustained for:", selection: binding(\.sustainedSeconds)) {
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                }
            }
            .disabled(!prefs.alerts.enabled)

            Section {
                Toggle("Also send a notification", isOn: Binding(
                    get: { prefs.alerts.notify },
                    set: { enable in
                        prefs.alerts.notify = enable
                        // Only ever ask for permission at the moment the user
                        // opts in, so the app's default stays zero-permission.
                        guard enable else { return }
                        Task {
                            let granted = await AlertNotifier.requestAuthorization()
                            notificationDenied = !granted
                            if !granted { prefs.alerts.notify = false }
                        }
                    }
                ))

                if notificationDenied {
                    Text("Notifications are turned off for System Monitor in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!prefs.alerts.enabled)
        }
        .formStyle(.grouped)
    }

    private func thresholdRow(for metric: MetricKind) -> some View {
        let watched = prefs.alerts.watched.contains(metric)

        return LabeledContent {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { prefs.alerts.threshold(for: metric) },
                        set: { prefs.alerts.setThreshold($0.rounded(), for: metric) }
                    ),
                    in: 50...99,
                    step: 1
                )
                .disabled(!watched)

                Text("\(Int(prefs.alerts.threshold(for: metric)))%")
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(watched ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            }
        } label: {
            Toggle(metric.title, isOn: Binding(
                get: { prefs.alerts.watched.contains(metric) },
                set: { on in
                    if on { prefs.alerts.watched.insert(metric) }
                    else { prefs.alerts.watched.remove(metric) }
                }
            ))
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AlertSettings, T>) -> Binding<T> {
        Binding(
            get: { prefs.alerts[keyPath: keyPath] },
            set: { prefs.alerts[keyPath: keyPath] = $0 }
        )
    }
}

struct AboutView: View {
    @ObservedObject private var updater = UpdaterController.shared

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// `applicationIconImage` is `null_resettable`, so it arrives in Swift as an
    /// implicitly unwrapped optional and a nil would trap rather than render.
    private var appIcon: NSImage {
        NSApp.applicationIconImage
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSImage(size: NSSize(width: 72, height: 72))
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 72, height: 72)
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
