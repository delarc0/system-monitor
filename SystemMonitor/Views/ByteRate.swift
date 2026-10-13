import Foundation

/// Formats a bytes-per-second rate for display, picking the largest unit that
/// keeps the number readable.
///
/// Shared by the network graph and the disk row, so it lives here rather than on
/// either sampler. Samplers publish numbers; formatting is the view's job.
func formatByteRate(_ bytesPerSecond: Double) -> String {
    let gb = Double(1 << 30)
    let mb = Double(1 << 20)
    let kb = Double(1 << 10)
    if bytesPerSecond >= gb { return String(format: "%.1f GB/s", bytesPerSecond / gb) }
    if bytesPerSecond >= mb { return String(format: "%.1f MB/s", bytesPerSecond / mb) }
    if bytesPerSecond >= kb { return String(format: "%.0f KB/s", bytesPerSecond / kb) }
    return String(format: "%.0f B/s", bytesPerSecond)
}

/// Round a window's peak up to a 1/2/5 × 10ⁿ figure inside its B/KB/MB/GB
/// unit, so the labelled scale is a number worth reading, with a floor so
/// an idle link doesn't magnify its own noise into a mountain range.
///
/// Must never return less than `peak`, or the chart silently clips the very
/// spike it exists to show. Covered by `LogicTests`.
func niceByteCeiling(_ peak: Double) -> Double {
    let floorValue = 64.0 * 1024
    guard peak > floorValue else { return floorValue }

    // `unit` is the largest power of 1024 not exceeding peak, so `mantissa`
    // lands in [1, 1024) and needs its own decimal rounding on top.
    let unit = pow(1024, floor(log2(peak) / 10))
    let mantissa = peak / unit
    let magnitude = pow(10, floor(log10(mantissa)))
    let normalized = mantissa / magnitude
    let step: Double
    switch normalized {
    case ..<1: step = 1
    case ..<2: step = 2
    case ..<5: step = 5
    default: step = 10
    }
    return step * magnitude * unit
}
