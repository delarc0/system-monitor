"""macOS menu bar (NSStatusItem) — shows color-coded CPU % and opens dropdown panel."""

from AppKit import (
    NSStatusBar,
    NSMenu,
    NSMenuItem,
    NSVariableStatusItemLength,
    NSAttributedString,
    NSColor,
    NSFont,
    NSForegroundColorAttributeName,
    NSFontAttributeName,
    NSImage,
)
from Foundation import NSObject, NSDictionary, NSTimer

from panel import Panel


class _MenuTarget(NSObject):
    """Receives NSMenuItem actions."""

    def menuAction_(self, sender):
        tag = sender.tag()
        cb = _callbacks.get(tag)
        if cb:
            try:
                cb()
            except Exception:
                pass


_callbacks = {}
_TAG_DETAILS = 2
_TAG_QUIT = 1


class Tray:
    def __init__(self, monitor, config):
        self._monitor = monitor
        self._config = config
        self._status_item = None
        self._target = None
        self._panel = None
        self._timer = None
        self._latest_snapshot = None

    def setup(self):
        sb = NSStatusBar.systemStatusBar()
        self._status_item = sb.statusItemWithLength_(NSVariableStatusItemLength)

        btn = self._status_item.button()
        if btn:
            btn.setTitle_("  \u2014  ")

        self._target = _MenuTarget.alloc().init()

        # Build menu
        menu = NSMenu.alloc().init()
        menu.setAutoenablesItems_(False)

        # "Show Details" opens the panel
        _callbacks[_TAG_DETAILS] = self._toggle_panel
        item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Show Details", "menuAction:", "d"
        )
        item.setTarget_(self._target)
        item.setTag_(_TAG_DETAILS)
        menu.addItem_(item)

        menu.addItem_(NSMenuItem.separatorItem())

        # Quit
        _callbacks[_TAG_QUIT] = self._quit
        quit_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Quit System Monitor", "menuAction:", "q"
        )
        quit_item.setTarget_(self._target)
        quit_item.setTag_(_TAG_QUIT)
        menu.addItem_(quit_item)

        self._status_item.setMenu_(menu)

        # Panel
        self._panel = Panel(self._status_item)

        # Register for monitor updates
        self._monitor.on_update(self._on_snapshot)

        # Timer to update menu bar text on the main thread
        self._timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            1.0, self._target, "refreshMenuBar:", None, True
        )

        # Bind the timer selector
        tray_ref = self

        def refresh_menu_bar_(self_obj, timer):
            tray_ref._update_menu_bar_text()

        _MenuTarget.refreshMenuBar_ = refresh_menu_bar_

    def _on_snapshot(self, snapshot):
        """Called from monitor thread — store for main thread timer to pick up."""
        self._latest_snapshot = snapshot

    def _update_menu_bar_text(self):
        """Update menu bar with current CPU %. Runs on main thread via NSTimer."""
        snap = self._latest_snapshot
        if not snap:
            return

        cpu_pct = snap.get("cpu", {}).get("overall", 0)
        text = f" {cpu_pct:3.0f}% "

        # Color based on load
        if cpu_pct < 50:
            color = NSColor.systemGreenColor()
        elif cpu_pct < 80:
            color = NSColor.systemOrangeColor()
        else:
            color = NSColor.systemRedColor()

        font = NSFont.monospacedDigitSystemFontOfSize_weight_(11.0, 0.0)

        attrs = NSDictionary.dictionaryWithObjects_forKeys_(
            [color, font],
            [NSForegroundColorAttributeName, NSFontAttributeName],
        )
        attr_str = NSAttributedString.alloc().initWithString_attributes_(text, attrs)

        btn = self._status_item.button()
        if btn:
            btn.setAttributedTitle_(attr_str)

        # Live-update the panel if it's open
        if self._panel and self._panel.is_visible():
            self._panel.update(snap)

    def _toggle_panel(self):
        if self._panel.is_visible():
            self._panel.hide()
        else:
            self._panel.show(self._latest_snapshot)

    def _quit(self):
        self._monitor.stop()
        from PyObjCTools import AppHelper
        AppHelper.stopEventLoop()
