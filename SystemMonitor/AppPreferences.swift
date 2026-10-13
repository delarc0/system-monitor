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
        case .all: return "CPU + GPU + Memory"
        }
    }
}

enum NetworkScale: String, CaseIterable, Identifiable {
    /// One symmetric scale for both directions. Honest about the ratio, but a
    /// typical 10:1 download:upload split renders upload as a sliver.
    case shared
    /// Each half scaled to its own peak, both labelled. Reads the shape of a
    /// small upload at the cost of the two halves not being comparable.
    case perDirection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shared: return "Shared (comparable)"
        case .perDirection: return "Per direction (detailed)"
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

/// Preferences persisted in UserDefaults. @Published + didSet so changes reliably
/// fire objectWillChange; @AppStorage inside an ObservableObject doesn't.
@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Key {
        static let menuBarDisplay = "menuBarDisplay"
        static let updateInterval = "updateInterval"
        static let networkScale = "networkScale"
        static let alertSettings = "alertSettings"
        static let showIsland = "showIsland"
    }

    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: Key.menuBarDisplay) }
    }

    @Published var updateInterval: Int {
        didSet { UserDefaults.standard.set(updateInterval, forKey: Key.updateInterval) }
    }

    @Published var networkScale: NetworkScale {
        didSet { UserDefaults.standard.set(networkScale.rawValue, forKey: Key.networkScale) }
    }

    @Published var showIsland: Bool {
        didSet { UserDefaults.standard.set(showIsland, forKey: Key.showIsland) }
    }

    @Published var alerts: AlertSettings {
        didSet {
            guard let data = try? JSONEncoder().encode(alerts) else { return }
            UserDefaults.standard.set(data, forKey: Key.alertSettings)
        }
    }

    private init() {
        let rawDisplay = UserDefaults.standard.string(forKey: Key.menuBarDisplay)
            ?? MenuBarDisplay.cpuMem.rawValue
        self.menuBarDisplay = MenuBarDisplay(rawValue: rawDisplay) ?? .cpuMem

        let storedInterval = UserDefaults.standard.integer(forKey: Key.updateInterval)
        self.updateInterval = storedInterval > 0 ? storedInterval : UpdateInterval.normal.rawValue

        let rawScale = UserDefaults.standard.string(forKey: Key.networkScale) ?? NetworkScale.shared.rawValue
        self.networkScale = NetworkScale(rawValue: rawScale) ?? .shared

        self.showIsland = UserDefaults.standard.object(forKey: Key.showIsland) as? Bool ?? true

        if let data = UserDefaults.standard.data(forKey: Key.alertSettings),
           let decoded = try? JSONDecoder().decode(AlertSettings.self, from: data) {
            self.alerts = decoded
        } else {
            self.alerts = AlertSettings()
        }
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
