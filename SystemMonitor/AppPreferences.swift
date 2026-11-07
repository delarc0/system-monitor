import Foundation
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
        case .all: return "CPU + GPU + Memory"
        }
    }
}

/// @Published + didSet so changes reliably fire objectWillChange; @AppStorage inside
/// an ObservableObject doesn't.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private static let displayKey = "menuBarDisplay"

    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: Self.displayKey) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.displayKey) ?? ""
        menuBarDisplay = MenuBarDisplay(rawValue: stored) ?? .cpuMem
    }

    /// Launch at Login, reflecting SMAppService state.
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
