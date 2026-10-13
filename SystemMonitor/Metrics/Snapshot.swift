import Foundation

struct CPUSample: Sendable, Equatable {
    var overall: Double           // 0..100
    var pCores: [Double]
    var eCores: [Double]
    var pCount: Int
    var eCount: Int
    var thermal: ProcessInfo.ThermalState
}

struct MemorySample: Sendable, Equatable {
    var totalGB: Double
    var usedGB: Double
    var percent: Double            // 0..100
    var swapUsedGB: Double
}

struct GPUSample: Sendable, Equatable {
    var utilization: Double?       // 0..100, nil if unavailable
}

struct NetworkSample: Sendable, Equatable {
    var downloadBps: Double
    var uploadBps: Double
    var downloadHistory: [Double]
    var uploadHistory: [Double]
    var windowSeconds: Int         // wall-clock span the history covers
    var capacity: Int              // slots the window holds once warmed up
}

struct DiskSample: Sendable, Equatable {
    var totalGB: Double
    var usedGB: Double
    var freeGB: Double
    var percent: Double            // capacity used, 0..100
    var readBps: Double
    var writeBps: Double
}

struct ClaudeSample: Sendable, Equatable {
    var fiveHourPercent: Double    // 0..100, plan rate limit window
    var sevenDayPercent: Double    // 0..100
    var fiveHourResetsAt: Date?
    var sevenDayResetsAt: Date?
    var sessionCostUSD: Double?    // the session that last wrote the file
    var updatedAt: Date            // only moves while a Claude Code session runs
}

struct BatterySample: Sendable, Equatable {
    var percent: Double            // 0..100
    var isCharging: Bool
    var externalPower: Bool
    var watts: Double              // signed: positive charges, negative drains
}

struct ProcessEntry: Sendable, Identifiable, Equatable {
    let id: String
    var name: String               // resolved app name, not the executable
    var value: Double              // cpu% for topCPU, GB for topMemory
    var bundlePath: String?        // .app bundle, when the row is a real app
    var executablePath: String     // for the tooltip: what actually ran
    var instances: Int             // processes merged into this row
}

/// The metrics a threshold can watch. Network and disk *throughput* are
/// deliberately absent: a burst of traffic isn't a problem, a sustained
/// saturated resource is. Claude is the 5-hour plan window.
enum MetricKind: String, Sendable, CaseIterable, Identifiable, Codable {
    case cpu, gpu, memory, disk, claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .claude: return "Claude"
        }
    }

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .claude: return "sparkles"
        }
    }
}

struct MetricAlert: Sendable, Equatable, Identifiable {
    let metric: MetricKind
    var value: Double
    var threshold: Double
    var sustainedSeconds: Int

    var id: String { metric.rawValue }
}

/// Rolling per-metric history, so the gauges can show where a value has been
/// rather than only where it is.
///
/// The series start empty and grow to `capacity` rather than being pre-filled
/// with zeros: a zero is a real reading, and padding with them drew a fake flat
/// line across the graph for the first minutes after launch. Views scale x
/// against `capacity` and right-anchor, so a partial series fills in from the
/// right the way every other system graph does.
struct MetricHistory: Sendable, Equatable {
    var capacity: Int = 60
    var cpu: [Double] = []
    var gpu: [Double] = []
    var memory: [Double] = []
    var disk: [Double] = []
}

struct Snapshot: Sendable, Equatable {
    var cpu: CPUSample
    var memory: MemorySample
    var gpu: GPUSample
    var disk: DiskSample
    var network: NetworkSample
    var claude: ClaudeSample?      // nil until the statusline has written once
    var battery: BatterySample?    // nil on a desktop
    var topCPU: [ProcessEntry]
    var topMemory: [ProcessEntry]
    var history: MetricHistory
    var alerts: [MetricAlert]

    func alert(for metric: MetricKind) -> MetricAlert? {
        alerts.first { $0.metric == metric }
    }
}
