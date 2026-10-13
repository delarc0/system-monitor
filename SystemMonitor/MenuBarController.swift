import AppKit
import Combine
import SwiftUI

/// Manages the menu bar NSStatusItem and its dropdown NSPopover.
/// SwiftUI's `MenuBarExtra` flattens per-segment colors when hosted in an
/// NSStatusItem button, so we drive the button title imperatively with
/// `NSAttributedString` + `NSColor`, same pattern as Bark-mac.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let prefs = AppPreferences.shared
    private let metrics = MetricsService.shared
    private var cancellables = Set<AnyCancellable>()
    private var island: NotchController?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        super.init()

        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        // The stored interval has to be applied before the loop starts, or a
        // saved 1 s / 5 s preference silently reverts to the 2 s default on
        // every launch while Settings still shows the saved value.
        metrics.updateInterval = TimeInterval(prefs.updateInterval)
        metrics.alertSettings = prefs.alerts
        metrics.start()
        island = NotchController { [weak self] in self?.togglePopover() }

        prefs.$alerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in self?.metrics.alertSettings = settings }
            .store(in: &cancellables)

        metrics.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLabel() }
            .store(in: &cancellables)

        prefs.$menuBarDisplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLabel() }
            .store(in: &cancellables)

        // Owning this here keeps Settings a pure preferences editor instead of
        // reaching into the sampling loop. The loop reads the interval at every
        // sleep, so no restart: restarting took a second sample milliseconds
        // after the last and pushed a fake 0% into every graph.
        prefs.$updateInterval
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in self?.metrics.updateInterval = TimeInterval(seconds) }
            .store(in: &cancellables)

        updateLabel()
    }

    #if DEBUG
    /// Opens the panel without a click, so a build can be screenshotted.
    func debugShowPanel() {
        guard !popover.isShown else { return }
        togglePopover()
    }
    #endif

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        guard !popover.isShown else {
            popover.performClose(nil)
            return
        }

        // Built on open and torn down on close. Kept alive across the app's
        // lifetime, the hosting controller stays subscribed to `metrics` and
        // re-evaluates the whole panel (Charts, animations and all) on every
        // tick for a view nobody is looking at.
        popover.contentViewController = NSHostingController(
            rootView: PanelView()
                .environmentObject(metrics)
                .environmentObject(prefs)
        )

        metrics.samplesProcesses = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Don't make the panel wait a full tick for its process rows.
        Task { await self.metrics.refreshProcesses() }
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let attr = NSMutableAttributedString()
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        guard let snap = metrics.snapshot else {
            attr.append(NSAttributedString(
                string: "…",
                attributes: [.font: numberFont, .foregroundColor: NSColor.labelColor]
            ))
            button.attributedTitle = attr
            return
        }

        appendSegment(to: attr, value: snap.cpu.overall, alerting: snap.alert(for: .cpu) != nil)

        if (prefs.menuBarDisplay == .cpuGpu || prefs.menuBarDisplay == .all),
           let gpu = snap.gpu.utilization {
            appendGap(to: attr, numberFont: numberFont)
            appendSegment(to: attr, value: gpu, alerting: snap.alert(for: .gpu) != nil)
        }

        if prefs.menuBarDisplay == .cpuMem || prefs.menuBarDisplay == .all {
            appendGap(to: attr, numberFont: numberFont)
            appendSegment(to: attr, value: snap.memory.percent, alerting: snap.alert(for: .memory) != nil)
        }

        button.attributedTitle = attr

        // The title is bare colour-coded numbers, so on its own it reads as
        // "5% 60%" with no indication of which is which, and the alert state is
        // carried only by colour. Both need saying out loud.
        let description = tooltip(for: snap)
        button.toolTip = description
        let alerting = snap.alerts.map { "\($0.metric.title) alert" }
        button.setAccessibilityLabel(
            ([description] + alerting).joined(separator: " · ")
        )
    }

    /// The number itself carries the load colour. The old layout prefixed each
    /// reading with a coloured ●, which cost roughly a character of menu bar
    /// width per metric to say what the number could say on its own.
    private func appendSegment(to attr: NSMutableAttributedString, value: Double, alerting: Bool) {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: 12,
            weight: alerting ? .bold : .medium
        )
        attr.append(NSAttributedString(
            string: String(format: "%.0f%%", value),
            attributes: [
                .foregroundColor: alerting ? NSColor.systemRed : loadNSColor(value),
                .font: font
            ]
        ))
    }

    private func appendGap(to attr: NSMutableAttributedString, numberFont: NSFont) {
        attr.append(NSAttributedString(
            string: "  ",
            attributes: [.font: numberFont]
        ))
    }

    /// Without the icons, hovering is the only way to learn which number is
    /// which, and it doubles as the accessibility description.
    private func tooltip(for snap: Snapshot) -> String {
        var parts = [String(format: "CPU %.0f%%", snap.cpu.overall)]
        if let gpu = snap.gpu.utilization { parts.append(String(format: "GPU %.0f%%", gpu)) }
        parts.append(String(format: "Memory %.0f%%", snap.memory.percent))
        parts.append(String(format: "Disk %.0f%%", snap.disk.percent))
        return parts.joined(separator: " · ")
    }
}

extension MenuBarController: NSPopoverDelegate {
    /// `.transient` popovers close on their own, so this is the only reliable
    /// place to stop the process sampler.
    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            self.metrics.samplesProcesses = false
            self.popover.contentViewController = nil
        }
    }
}
