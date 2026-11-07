import Foundation

/// Bytes per second from ever-growing counters, tracked per interface or drive.
///
/// Per key because a sum breaks when membership changes: an interface coming back
/// up with its old byte count would add its whole lifetime to the total and read
/// as one huge burst, pinning the chart scale. A new key only sets a baseline.
struct RateCounter {
    /// Longer than any tick, so a bigger gap means the Mac slept and the delta
    /// spans an unknown stretch of time.
    private static let maxGap: TimeInterval = 15

    private var previous: [String: UInt64] = [:]
    private var previousTime: Date?

    /// Nil when there is no usable baseline: first read, or after a long gap.
    mutating func rate(_ counters: [String: UInt64], now: Date = Date()) -> Double? {
        defer {
            previous = counters
            previousTime = now
        }
        guard let last = previousTime else { return nil }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 0, elapsed <= Self.maxGap else { return nil }

        var bytes: UInt64 = 0
        for (key, value) in counters {
            // A counter that went backwards was restarted, so this tick says nothing.
            if let old = previous[key], value > old { bytes &+= value - old }
        }
        return Double(bytes) / elapsed
    }
}
