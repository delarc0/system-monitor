import Foundation

/// Threshold rules, persisted as one JSON blob.
struct AlertSettings: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var watched: Set<MetricKind> = [.cpu, .memory, .disk]
    var sustainedSeconds: Int = 30
    var notify: Bool = false

    var cpu: Double = 90
    var gpu: Double = 90
    var memory: Double = 90
    var disk: Double = 90
    var claude: Double = 90

    init() {}

    /// Field by field with defaults, so a settings blob saved by an older
    /// build still decodes after a new field is added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        watched = try c.decodeIfPresent(Set<MetricKind>.self, forKey: .watched) ?? watched
        sustainedSeconds = try c.decodeIfPresent(Int.self, forKey: .sustainedSeconds) ?? sustainedSeconds
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? notify
        cpu = try c.decodeIfPresent(Double.self, forKey: .cpu) ?? cpu
        gpu = try c.decodeIfPresent(Double.self, forKey: .gpu) ?? gpu
        memory = try c.decodeIfPresent(Double.self, forKey: .memory) ?? memory
        disk = try c.decodeIfPresent(Double.self, forKey: .disk) ?? disk
        claude = try c.decodeIfPresent(Double.self, forKey: .claude) ?? claude
    }

    func threshold(for metric: MetricKind) -> Double {
        switch metric {
        case .cpu: return cpu
        case .gpu: return gpu
        case .memory: return memory
        case .disk: return disk
        case .claude: return claude
        }
    }

    mutating func setThreshold(_ value: Double, for metric: MetricKind) {
        switch metric {
        case .cpu: cpu = value
        case .gpu: gpu = value
        case .memory: memory = value
        case .disk: disk = value
        case .claude: claude = value
        }
    }
}

/// Turns raw readings into sustained-breach alerts.
///
/// A momentary spike to 100% is normal on any machine: a compile, a wake, a
/// render. Only a metric that *stays* over its threshold is worth surfacing, so
/// a breach has to persist for `sustainedSeconds` before it becomes an alert.
/// Clearing uses a lower bar than arming so a value hovering on the line
/// doesn't flap the UI on and off every tick.
@MainActor
final class AlertMonitor {
    private static let clearMargin: Double = 5

    /// Longest plausible gap between two ticks at the slowest update interval.
    /// A larger one means the app was suspended (the machine slept), and that wall-clock time must not be counted
    /// as sustained load, or a Mac that sleeps while busy alerts the instant it
    /// wakes for a breach that was never continuously observed.
    private static let maxGapSeconds: TimeInterval = 15

    private var breachStarted: [MetricKind: Date] = [:]
    private var active: Set<MetricKind> = []
    private var lastEvaluated: Date?

    /// Metrics that just became alerting on this tick: the edge worth
    /// notifying on, as opposed to the level that keeps the UI red.
    private(set) var newlyTriggered: [MetricAlert] = []

    func evaluate(
        values: [MetricKind: Double],
        settings: AlertSettings,
        now: Date = Date()
    ) -> [MetricAlert] {
        newlyTriggered = []

        let gap = lastEvaluated.map { now.timeIntervalSince($0) }
        lastEvaluated = now

        guard settings.enabled else {
            breachStarted.removeAll()
            active.removeAll()
            return []
        }

        // Start every breach clock over after a suspension.
        if let gap, gap > Self.maxGapSeconds || gap < 0 {
            breachStarted.removeAll()
            active.removeAll()
        }

        var alerts: [MetricAlert] = []

        for metric in MetricKind.allCases {
            guard settings.watched.contains(metric), let value = values[metric] else {
                breachStarted[metric] = nil
                active.remove(metric)
                continue
            }

            let threshold = settings.threshold(for: metric)
            let clearAt = threshold - Self.clearMargin
            let isOver = active.contains(metric) ? value >= clearAt : value >= threshold

            guard isOver else {
                breachStarted[metric] = nil
                active.remove(metric)
                continue
            }

            let start = breachStarted[metric] ?? now
            breachStarted[metric] = start

            let sustained = now.timeIntervalSince(start)
            guard sustained >= Double(settings.sustainedSeconds) else { continue }

            let alert = MetricAlert(
                metric: metric,
                value: value,
                threshold: threshold,
                sustainedSeconds: Int(sustained)
            )
            alerts.append(alert)

            if active.insert(metric).inserted {
                newlyTriggered.append(alert)
            }
        }

        return alerts
    }
}
