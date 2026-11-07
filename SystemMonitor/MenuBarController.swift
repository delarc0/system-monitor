import AppKit
import Combine
import SwiftUI

/// Manages the menu bar NSStatusItem and its dropdown NSPopover.
/// SwiftUI's `MenuBarExtra` flattens per-segment colors when hosted in an
/// NSStatusItem button, so we drive the button title imperatively with
/// `NSAttributedString` + `NSColor`, same pattern as Bark-mac.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let prefs = AppPreferences.shared
    private let metrics = MetricsService.shared
    private var cancellables = Set<AnyCancellable>()

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

        // Created here, not on first use: nothing else would start its background checks.
        _ = UpdaterController.shared

        metrics.start()

        metrics.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLabel() }
            .store(in: &cancellables)

        prefs.$menuBarDisplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLabel() }
            .store(in: &cancellables)

        updateLabel()
    }

    #if DEBUG
    /// Opens the panel without a click, so a build can be screenshotted.
    func debugShowPanel() {
        guard !popover.isShown else { return }
        // Transient closes the moment anything else takes focus, which left nothing to draw.
        popover.behavior = .applicationDefined
        // On the popover, not NSApp: it takes its appearance from the status button.
        if ProcessInfo.processInfo.environment["SYSMON_LIGHT"] != nil {
            popover.appearance = NSAppearance(named: .aqua)
        }
        togglePopover()

        // `screencapture` needs Screen Recording, which an agent's shell may not have.
        // This draws the real views with live data, in-process.
        guard let path = ProcessInfo.processInfo.environment["SYSMON_PANEL_PNG"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            write(popover.contentViewController?.view, to: path)
            write(statusItem.button, to: path.replacingOccurrences(of: ".png", with: "-menubar.png"))
        }
    }

    private func write(_ view: NSView?, to path: String) {
        guard let view, let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: image)
        try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
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
        // re-evaluates the whole panel on every tick for a view nobody is looking at.
        popover.contentViewController = NSHostingController(
            rootView: PanelView()
                .environmentObject(metrics)
                .environmentObject(prefs)
        )

        metrics.setPanelVisible(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// `.transient` popovers close on their own, so this is the only reliable place to
    /// stop the process sampler. Reopening during the close animation must not lose
    /// the new panel, hence the guard.
    func popoverDidClose(_ notification: Notification) {
        guard !popover.isShown else { return }
        metrics.setPanelVisible(false)
        popover.contentViewController = nil
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let attr = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        guard let snap = metrics.snapshot else {
            attr.append(NSAttributedString(
                string: "…",
                attributes: [.font: font, .foregroundColor: NSColor.labelColor]
            ))
            button.attributedTitle = attr
            return
        }

        let labelAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        func append(_ label: String, _ value: Double, _ color: NSColor) {
            if attr.length > 0 {
                attr.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            }
            attr.append(NSAttributedString(string: label + " ", attributes: labelAttributes))
            attr.append(NSAttributedString(
                string: String(format: "%.0f%%", value),
                attributes: [.font: font, .foregroundColor: color]
            ))
        }

        // The number carries the colour. Memory is coloured by the kernel's pressure
        // state, not its percentage: a Mac near 90% used is usually fine.
        // First and in every display mode: it's the reading the bar exists for.
        if let claude = metrics.claude {
            // Dimmed once the reads are failing, so an old number can't pass as current.
            let isStale = Date().timeIntervalSince(claude.readAt) >= 3600
            append("Claude", claude.percent, isStale ? .tertiaryLabelColor : loadNSColor(claude.percent))
        } else if ClaudeSampler.binaryPath != nil {
            attr.append(NSAttributedString(string: "Claude --", attributes: labelAttributes))
        }
        append("CPU", snap.cpu.overall, loadNSColor(snap.cpu.overall))
        if prefs.menuBarDisplay == .cpuGpu || prefs.menuBarDisplay == .all, let gpu = snap.gpu.utilization {
            append("GPU", gpu, loadNSColor(gpu))
        }
        if prefs.menuBarDisplay == .cpuMem || prefs.menuBarDisplay == .all {
            append("MEM", snap.memory.percent, loadNSColor(snap.memory.pressure.load))
        }
        // The one warning: nothing else in the menu bar would ever show the disk.
        if snap.disk.isLow {
            append("Disk", snap.disk.percent, .systemRed)
        }

        button.attributedTitle = attr

        // Also the accessibility description, and the only place the disk shows when healthy.
        let description = tooltip(for: snap)
        button.toolTip = description
        button.setAccessibilityLabel(description)
    }

    private func tooltip(for snap: Snapshot) -> String {
        var parts = [String(format: "CPU %.0f%%", snap.cpu.overall)]
        if let claude = metrics.claude {
            parts.insert(String(format: "Claude %.0f%%", claude.percent) + (claude.resets.map { ", resets \($0)" } ?? ""), at: 0)
        }
        if let gpu = snap.gpu.utilization { parts.append(String(format: "GPU %.0f%%", gpu)) }
        parts.append(String(format: "Memory %.0f%%", snap.memory.percent))
        parts.append(String(format: "Disk %.0f%%", snap.disk.percent))
        return parts.joined(separator: " · ")
    }
}
