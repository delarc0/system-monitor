import SwiftUI

@main
struct SystemMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            menuBar = MenuBarController()

            #if DEBUG
            // A menu bar popover can't be opened from a script, which makes the
            // panel impossible to screenshot for review. `SYSMON_OPEN_PANEL`
            // opens it on launch; its value is a delay in seconds, so the graphs
            // can be given time to fill before the shot:
            //   open -n --env SYSMON_OPEN_PANEL=120 "…/System Monitor.app"
            // Debug-only, so it can't exist in a shipped build.
            if let raw = ProcessInfo.processInfo.environment["SYSMON_OPEN_PANEL"] {
                let delay = max(Double(raw) ?? 2.0, 2.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NSApp.activate(ignoringOtherApps: true)
                    self.menuBar?.debugShowPanel()
                }
            }
            #endif
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
