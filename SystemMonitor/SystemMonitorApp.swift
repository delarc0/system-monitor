import SwiftUI

@main
struct SystemMonitorApp: App {
    @StateObject private var metrics = MetricsService.shared
    @StateObject private var prefs = AppPreferences.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(metrics)
                .environmentObject(prefs)
                .onAppear {
                    metrics.updateInterval = TimeInterval(prefs.updateInterval)
                    metrics.start()
                }
        } label: {
            MenuBarLabel(snapshot: metrics.snapshot, display: prefs.menuBarDisplay)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
