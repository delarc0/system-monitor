"""Dropdown panel — clean dark panel, 4 stats + network graph + processes."""

from AppKit import (
    NSWindowStyleMaskBorderless,
    NSWindowStyleMaskNonactivatingPanel,
    NSBackingStoreBuffered,
    NSView,
    NSColor,
    NSFont,
    NSBezierPath,
    NSMakeRect,
    NSScreen,
    NSForegroundColorAttributeName,
    NSFontAttributeName,
    NSPanel,
)
from Foundation import (
    NSMakeRect,
    NSAttributedString,
    NSDictionary,
    NSPoint,
)
import objc

PANEL_WIDTH = 280
PAD = 16
CORNER_RADIUS = 10
BAR_HEIGHT = 5
BAR_RADIUS = 2.5
GRAPH_HEIGHT = 50

FONT_LG = 13
FONT_MD = 11
FONT_SM = 10
FONT_XS = 9
ROW = 18
GAP = 16

# Colors
COL_BG = None
COL_WHITE = None
COL_DIM = None
COL_TRACK = None
COL_SEP = None
COL_DL = None
COL_UL = None
COL_DL_FILL = None
COL_UL_FILL = None


def initColors():
    global COL_BG, COL_WHITE, COL_DIM, COL_TRACK, COL_SEP
    global COL_DL, COL_UL, COL_DL_FILL, COL_UL_FILL
    if COL_BG is not None:
        return
    COL_BG = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.10, 0.10, 0.12, 0.96)
    COL_WHITE = NSColor.whiteColor()
    COL_DIM = NSColor.colorWithCalibratedWhite_alpha_(0.50, 1.0)
    COL_TRACK = NSColor.colorWithCalibratedWhite_alpha_(0.22, 1.0)
    COL_SEP = NSColor.colorWithCalibratedWhite_alpha_(0.18, 1.0)
    COL_DL = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.35, 0.78, 1.0, 1.0)
    COL_UL = NSColor.colorWithCalibratedRed_green_blue_alpha_(1.0, 0.55, 0.35, 1.0)
    COL_DL_FILL = NSColor.colorWithCalibratedRed_green_blue_alpha_(0.35, 0.78, 1.0, 0.15)
    COL_UL_FILL = NSColor.colorWithCalibratedRed_green_blue_alpha_(1.0, 0.55, 0.35, 0.10)


def barColor(pct):
    if pct < 50:
        return NSColor.systemGreenColor()
    elif pct < 80:
        return NSColor.systemOrangeColor()
    else:
        return NSColor.systemRedColor()


# ── Drawing functions ──

def drawText(text, x, y, size, color, bold=False):
    font = (NSFont.systemFontOfSize_weight_(size, 0.6) if bold
            else NSFont.systemFontOfSize_(size))
    attrs = NSDictionary.dictionaryWithObjects_forKeys_(
        [font, color], [NSFontAttributeName, NSForegroundColorAttributeName])
    NSAttributedString.alloc().initWithString_attributes_(
        text, attrs).drawAtPoint_(NSPoint(x, y))
    return y + ROW


def drawTextRight(text, y, w, size, color, bold=False):
    font = (NSFont.monospacedDigitSystemFontOfSize_weight_(size, 0.6) if bold
            else NSFont.monospacedDigitSystemFontOfSize_weight_(size, 0.0))
    attrs = NSDictionary.dictionaryWithObjects_forKeys_(
        [font, color], [NSFontAttributeName, NSForegroundColorAttributeName])
    s = NSAttributedString.alloc().initWithString_attributes_(text, attrs)
    s.drawAtPoint_(NSPoint(PAD + w - s.size().width, y))


def drawStatRow(label, pct, y, w):
    """Draw: Label  [====    ]  XX%  — all on one line."""
    label_w = 56
    pct_w = 38
    bar_x = PAD + label_w
    bar_w = w - label_w - pct_w - 4

    drawText(label, PAD, y, FONT_MD, COL_WHITE, bold=True)

    # Bar
    t = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
        NSMakeRect(bar_x, y + 6, bar_w, BAR_HEIGHT), BAR_RADIUS, BAR_RADIUS)
    COL_TRACK.set()
    t.fill()
    fw = bar_w * (pct / 100.0)
    if fw > 0:
        f = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            NSMakeRect(bar_x, y + 6, max(fw, BAR_RADIUS * 2), BAR_HEIGHT),
            BAR_RADIUS, BAR_RADIUS)
        barColor(pct).set()
        f.fill()

    drawTextRight(f"{pct:.0f}%", y, w, FONT_MD, COL_WHITE, bold=True)
    return y + ROW


def drawStatRowVal(label, value, y, w):
    """Draw: Label                Value"""
    drawText(label, PAD, y, FONT_MD, COL_WHITE, bold=True)
    drawTextRight(value, y, w, FONT_MD, COL_DIM)
    return y + ROW


def drawSep(y, w):
    path = NSBezierPath.bezierPath()
    path.moveToPoint_(NSPoint(PAD, y))
    path.lineToPoint_(NSPoint(PAD + w, y))
    COL_SEP.set()
    path.setLineWidth_(0.5)
    path.stroke()
    return y


def drawGraph(dl_hist, ul_hist, dl_str, ul_str, y, w):
    """Draw a network throughput graph with filled areas."""
    graph_x = PAD
    graph_w = w
    graph_y = y
    graph_h = GRAPH_HEIGHT

    # Find max for scaling
    all_vals = dl_hist + ul_hist
    peak = max(all_vals) if all_vals else 1
    if peak < 1024:
        peak = 1024  # minimum 1 KB/s scale

    n = len(dl_hist)
    if n < 2:
        return y + graph_h

    step = graph_w / (n - 1)

    # Draw download area + line (blue)
    drawFilledLine(dl_hist, graph_x, graph_y, graph_w, graph_h, step, peak, n,
                   COL_DL, COL_DL_FILL)

    # Draw upload area + line (orange)
    drawFilledLine(ul_hist, graph_x, graph_y, graph_w, graph_h, step, peak, n,
                   COL_UL, COL_UL_FILL)

    # Bottom axis line
    axis = NSBezierPath.bezierPath()
    axis.moveToPoint_(NSPoint(graph_x, graph_y + graph_h))
    axis.lineToPoint_(NSPoint(graph_x + graph_w, graph_y + graph_h))
    COL_SEP.set()
    axis.setLineWidth_(0.5)
    axis.stroke()

    # Legend below graph
    ly = graph_y + graph_h + 6
    drawText(f"\u2193 {dl_str}", PAD, ly, FONT_SM, COL_DL)
    drawTextRight(f"\u2191 {ul_str}", ly, w, FONT_SM, COL_UL)

    return ly + ROW


def drawFilledLine(hist, gx, gy, gw, gh, step, peak, n, lineColor, fillColor):
    """Draw a filled area chart line for a history list."""
    # Build points
    points = []
    for i, val in enumerate(hist):
        px = gx + i * step
        ratio = min(val / peak, 1.0) if peak > 0 else 0
        py = gy + gh - (ratio * (gh - 2))  # 2px top margin
        points.append((px, py))

    if not points:
        return

    # Filled area
    fill = NSBezierPath.bezierPath()
    fill.moveToPoint_(NSPoint(points[0][0], gy + gh))
    for px, py in points:
        fill.lineToPoint_(NSPoint(px, py))
    fill.lineToPoint_(NSPoint(points[-1][0], gy + gh))
    fill.closePath()
    fillColor.set()
    fill.fill()

    # Line on top
    line = NSBezierPath.bezierPath()
    line.moveToPoint_(NSPoint(points[0][0], points[0][1]))
    for px, py in points[1:]:
        line.lineToPoint_(NSPoint(px, py))
    lineColor.set()
    line.setLineWidth_(1.5)
    line.stroke()


def drawProcRow(name, pct, y, w):
    drawText(name, PAD, y, FONT_SM, COL_WHITE)
    drawTextRight(f"{pct:.1f}%", y, w, FONT_SM, COL_DIM)
    return y + ROW


# ── View ──

class PanelView(NSView):

    def initWithFrame_(self, frame):
        self = objc.super(PanelView, self).initWithFrame_(frame)
        if self is None:
            return None
        self.snap = None
        initColors()
        return self

    def setSnap_(self, s):
        self.snap = s
        self.setNeedsDisplay_(True)

    def isFlipped(self):
        return True

    def drawRect_(self, rect):
        bg = NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            self.bounds(), CORNER_RADIUS, CORNER_RADIUS)
        COL_BG.set()
        bg.fill()

        if not self.snap:
            drawText("Loading\u2026", PAD, PAD, FONT_MD, COL_DIM)
            return

        s = self.snap
        w = PANEL_WIDTH - 2 * PAD
        y = PAD

        # ── 4 Main Stats ──
        cpu_pct = s.get("cpu", {}).get("overall", 0)
        y = drawStatRow("CPU", cpu_pct, y, w)

        gpu = s.get("gpu", {})
        gv = gpu.get("utilization")
        if gv is not None:
            y = drawStatRow("GPU", gv, y, w)
        else:
            y = drawStatRowVal("GPU", "N/A", y, w)

        mem = s.get("memory", {})
        mp = mem.get("percent", 0)
        y = drawStatRow("Memory", mp, y, w)
        # Memory detail line
        detail = f"{mem.get('used_gb', 0)} / {mem.get('total_gb', 0)} GB"
        if mem.get("swap_used_gb", 0) > 0.1:
            detail += f"  \u00b7  Swap {mem.get('swap_used_gb', 0):.1f} GB"
        y = drawText(detail, PAD + 56, y - 4, FONT_XS, COL_DIM)
        y += 2

        y = drawSep(y, w)
        y += GAP

        # ── Network Graph ──
        net = s.get("network", {})
        y = drawText("Network", PAD, y, FONT_MD, COL_WHITE, bold=True)
        y += 4
        dl_hist = net.get("download_history", [0] * 30)
        ul_hist = net.get("upload_history", [0] * 30)
        y = drawGraph(
            dl_hist, ul_hist,
            net.get("download_str", "0 B/s"),
            net.get("upload_str", "0 B/s"),
            y, w
        )

        y += GAP
        y = drawSep(y, w)
        y += GAP

        # ── Processes ──
        procs = s.get("processes", [])
        if procs:
            y = drawText("Processes", PAD, y, FONT_MD, COL_WHITE, bold=True)
            y += 2
            for name, pct in procs:
                dn = name[:24] + "\u2026" if len(name) > 24 else name
                y = drawProcRow(dn, pct, y, w)
        # Extra bottom padding is handled by panel height


# ── Panel Window ──

# Calculate panel height to fit everything with room to spare
# 4 stats (~72) + sep + network header + graph + legend (~100) + sep + processes header + 5 rows (~108) + padding
PANEL_HEIGHT = 400


class Panel:

    def __init__(self, status_item):
        self._si = status_item
        self._win = None
        self._view = None
        self._build()

    def _build(self):
        f = NSMakeRect(0, 0, PANEL_WIDTH, PANEL_HEIGHT)
        self._win = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            f, NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel,
            NSBackingStoreBuffered, False)
        self._win.setLevel_(3)
        self._win.setOpaque_(False)
        self._win.setBackgroundColor_(NSColor.clearColor())
        self._win.setHasShadow_(True)
        self._view = PanelView.alloc().initWithFrame_(f)
        self._win.setContentView_(self._view)

    def show(self, snapshot=None):
        btn = self._si.button()
        if btn and btn.window():
            r = btn.window().convertRectToScreen_(btn.frame())
            px = r.origin.x + r.size.width / 2 - PANEL_WIDTH / 2
            py = r.origin.y - self._win.frame().size.height - 6
            sc = NSScreen.mainScreen()
            if sc:
                sf = sc.visibleFrame()
                px = max(px, sf.origin.x + 8)
                px = min(px, sf.origin.x + sf.size.width - PANEL_WIDTH - 8)
            self._win.setFrameOrigin_(NSPoint(px, py))
        if snapshot:
            self._view.setSnap_(snapshot)
        self._win.makeKeyAndOrderFront_(None)

    def hide(self):
        self._win.orderOut_(None)

    def is_visible(self):
        return self._win.isVisible()

    def update(self, snapshot):
        self._view.setSnap_(snapshot)
