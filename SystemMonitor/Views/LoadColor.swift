import SwiftUI

/// Smooth green → orange → red color based on a 0..100 load value.
/// Hue transitions from 120° (green) at 0% to 0° (red) at ~85%+.
func loadColor(_ percent: Double) -> Color {
    let clamped = max(0, min(percent, 100))
    // Map 0..85 → hue 120..0 (green→red). Above 85% stays saturated red.
    let hue = max(0, (85 - clamped) / 85) * (120.0 / 360.0)
    return Color(hue: hue, saturation: 0.78, brightness: 0.92)
}
