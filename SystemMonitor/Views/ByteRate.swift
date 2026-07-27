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
