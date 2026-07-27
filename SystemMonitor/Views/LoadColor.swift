import SwiftUI
import AppKit

/// Hue for a 0..100 load value: 120° (green) at idle, sliding to 0° (red) at
/// 85% and staying there. Returned in SwiftUI's 0..1 hue space.
private func loadHue(_ percent: Double) -> Double {
    let clamped = min(max(percent, 0), 100)
    return max(0, (85 - clamped) / 85) * (120.0 / 360.0)
}

private let loadSaturation = 0.78
private let loadBrightness = 0.92

/// Smooth green → orange → red color based on a 0..100 load value.
func loadColor(_ percent: Double) -> Color {
    Color(hue: loadHue(percent), saturation: loadSaturation, brightness: loadBrightness)
}

/// NSColor variant for use in `NSAttributedString`, because SwiftUI's `Color` gets
/// flattened to the menu bar's template tint when embedded in an NSStatusItem,
/// so the menu bar label uses this explicit NSColor to preserve hue.
func loadNSColor(_ percent: Double) -> NSColor {
    NSColor(hue: loadHue(percent), saturation: loadSaturation, brightness: loadBrightness, alpha: 1.0)
}
