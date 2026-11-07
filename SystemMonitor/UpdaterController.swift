import Foundation
import Sparkle

/// Wraps Sparkle's updater.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    /// False until the first real release sets the EdDSA key. Starting Sparkle with
    /// the placeholder is a configuration error it reports to the user on launch.
    static var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return !key.isEmpty && !key.hasPrefix("REPLACE_")
    }

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: Self.isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
