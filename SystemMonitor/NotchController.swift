import AppKit
import Combine
import SwiftUI

/// A borderless panel over the MacBook notch: invisible at rest, a readout on
/// hover. macOS has no Dynamic Island API (ActivityKit is iOS-only), so this is
/// what every notch app does: a status-level window placed from
/// `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
@MainActor
final class NotchController: NSObject {
    private static let expandedSize = NSSize(width: 600, height: 112)

    private let panel: NSPanel
    private let prefs = AppPreferences.shared
    private var expanded = false
    private var cancellable: AnyCancellable?

    init(onTap: @escaping @MainActor () -> Void) {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // The notch is a property of this machine's built-in display, so its
        // size is read once; `layout` only decides whether it is on screen.
        let notch = Self.notchRect()?.size ?? CGSize(width: 220, height: 38)
        panel.contentView = NSHostingView(rootView: IslandView(
            notchSize: notch,
            onHover: { [weak self] in self?.setExpanded($0) ?? false },
            onTap: onTap
        ).environmentObject(MetricsService.shared))

        cancellable = prefs.$showIsland
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.layout() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        layout()
    }

    @objc private func screensChanged() { layout() }

    /// The gap between the two auxiliary areas, in global screen coordinates.
    /// Nil without a notched display, which includes a closed lid.
    private static func notchRect() -> NSRect? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        return NSRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: screen.safeAreaInsets.top)
    }

    private func layout() {
        guard prefs.showIsland, let notch = Self.notchRect() else {
            panel.orderOut(nil)
            return
        }
        let size = expanded ? Self.expandedSize : notch.size
        let frame = NSRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height, width: size.width, height: size.height)
        // animator(), not setFrame(animate:): that one blocks in a nested
        // event loop, SwiftUI then sees a hover exit mid-resize, and the second
        // call collides with the first and leaves the frame stuck part way.
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    @discardableResult
    private func setExpanded(_ value: Bool) -> Bool {
        guard expanded != value else { return expanded }
        // A resize under the cursor can report an exit while the pointer never
        // left; the frame, not the tracking area, decides.
        if !value, panel.frame.contains(NSEvent.mouseLocation) { return expanded }
        expanded = value
        layout()
        return expanded
    }
}
