import Foundation
import UserNotifications

/// Optional macOS notifications for sustained threshold breaches.
///
/// Off by default and authorization is only ever requested when the user turns
/// it on in Settings, so the app keeps its "asks for nothing" default. Every
/// call is best-effort: an unsigned build, a denied prompt or a missing
/// notification centre must never take the sampling loop down with it.
@MainActor
final class AlertNotifier {
    /// Called from Settings when the toggle flips on.
    static func requestAuthorization() async -> Bool {
        guard let center = AlertNotifier().center else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            NSLog("Notification authorization failed: \(error)")
            return false
        }
    }

    func post(_ alert: MetricAlert) {
        guard let center = center else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(alert.metric.title) at \(Int(alert.value))%"
        content.body = "Above \(Int(alert.threshold))% for \(alert.sustainedSeconds) seconds."

        let request = UNNotificationRequest(
            identifier: "alert-\(alert.metric.rawValue)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error { NSLog("Notification post failed: \(error)") }
        }
    }

    /// `UNUserNotificationCenter.current()` traps rather than returning nil when
    /// the process isn't a properly bundled, signed app, which is exactly the
    /// case for some local builds.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }
}
