import Foundation

struct CPUSample {
    var overall: Double            // 0..100
    var thermal: ProcessInfo.ThermalState
}

/// The kernel's own verdict on memory, which is what actually predicts trouble:
/// a Mac is routinely near 90% used with nothing wrong.
enum MemoryPressure {
    case normal, warning, critical

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    init(level: Int) {
        switch level {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    /// Where this state sits on the 0..100 load colour scale.
    var load: Double {
        switch self {
        case .normal: return 0
        case .warning: return 60
        case .critical: return 100
        }
    }
}

struct MemorySample {
    var totalGB: Double
    var usedGB: Double
    var percent: Double            // 0..100
    var swapUsedGB: Double
    var pressure: MemoryPressure
}

struct GPUSample {
    var utilization: Double?       // 0..100, nil if unavailable
}

struct NetworkSample {
    var downloadBps: Double
    var uploadBps: Double
    var downloadHistory: [Double]
    var uploadHistory: [Double]
}

struct DiskSample {
    var totalGB: Double
    var freeGB: Double
    var percent: Double            // capacity used, 0..100
    var readBps: Double
    var writeBps: Double

    /// Under 10% free is when a Mac starts to struggle and renders start to fail.
    var isLow: Bool { totalGB > 0 && percent >= 90 }
}

struct ClaudeUsage: Sendable {
    var percent: Double            // weekly allowance used, 0..100
    var resets: String?            // as Claude Code words it, no year or zone
    var weekElapsed: Double?       // 0..1, nil if the reset text can't be read
    var readAt: Date
}

struct ProcessEntry: Sendable, Identifiable {
    let id: String
    var name: String               // resolved app name, not the executable
    var value: Double              // cpu% for the CPU list, GB for the memory list
    var bundlePath: String?        // .app bundle, when the row is a real app
    var executablePath: String     // for the tooltip: what actually ran
    var instances: Int             // processes merged into this row
}

struct TopProcesses: Sendable {
    var cpu: [ProcessEntry] = []
    var memory: [ProcessEntry] = []
}

/// Rolling history behind the sparklines.
///
/// The series start empty and grow to `capacity` rather than being pre-filled
/// with zeros: a zero is a real reading, and padding with them drew a fake flat
/// line across the graph for the first minutes after launch. Views scale x
/// against `capacity` and right-anchor, so a partial series fills in from the
/// right the way every other system graph does.
struct MetricHistory {
    static let capacity = 60

    var cpu: [Double] = []
    var gpu: [Double] = []
    var memory: [Double] = []
}

extension Array where Element == Double {
    mutating func pushToHistory(_ value: Double) {
        append(value)
        if count > MetricHistory.capacity { removeFirst(count - MetricHistory.capacity) }
    }
}

struct Snapshot {
    var cpu: CPUSample
    var memory: MemorySample
    var gpu: GPUSample
    var disk: DiskSample
    var network: NetworkSample
    var history: MetricHistory
}
