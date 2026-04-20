import Foundation
import SwiftUI
import ServiceManagement

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case cpu = "cpu"
    case cpuMem = "cpu+mem"
    case cpuGpu = "cpu+gpu"
    case all = "all"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .cpuMem: return "CPU + Memory"
        case .cpuGpu: return "CPU + GPU"
        case .all: return "CPU + Memory + GPU"
        }
    }
}

enum UpdateInterval: Int, CaseIterable, Identifiable {
    case fast = 1
    case normal = 2
    case slow = 5

    var id: Int { rawValue }
    var title: String { "\(rawValue) second\(rawValue == 1 ? "" : "s")" }
}

/// Central preferences backed by UserDefaults via @AppStorage.
/// Single source of truth — inject into views or read directly.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @AppStorage("menuBarDisplay") var menuBarDisplayRaw: String = MenuBarDisplay.cpuMem.rawValue
    @AppStorage("updateInterval") var updateInterval: Int = UpdateInterval.normal.rawValue

    var menuBarDisplay: MenuBarDisplay {
        get { MenuBarDisplay(rawValue: menuBarDisplayRaw) ?? .cpuMem }
        set { menuBarDisplayRaw = newValue.rawValue }
    }

    /// Launch at Login — reflects SMAppService state.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                objectWillChange.send()
            } catch {
                NSLog("SMAppService toggle failed: \(error)")
            }
        }
    }
}
