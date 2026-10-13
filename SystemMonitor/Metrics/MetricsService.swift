import Foundation
import SwiftUI

/// Orchestrates sampling and publishes the latest `Snapshot` on the main actor.
@MainActor
final class MetricsService: ObservableObject {
    static let shared = MetricsService()

    @Published private(set) var snapshot: Snapshot?

    var updateInterval: TimeInterval = 2.0

    /// The process list is only ever read by the panel. Sampling it while the
    /// popover is closed spawns a `ps` every tick for output nobody sees, so
    /// the panel switches it on while it's visible.
    var samplesProcesses = false

    /// Threshold rules, pushed in by whoever owns preferences.
    var alertSettings = AlertSettings()

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let gpu = GPUSampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()
    private let process = ProcessSampler()
    private let alerts = AlertMonitor()
    private let notifier = AlertNotifier()
    private var loop: Task<Void, Never>?

    /// Sparkline depth, matched to the network graph so both cover the same
    /// stretch of time at a given update interval.
    private let historyLength = 60
    private lazy var history = MetricHistory(capacity: historyLength)

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let snapshot = await self.buildSnapshot() { self.snapshot = snapshot }
                try? await Task.sleep(for: .seconds(self.updateInterval))
            }
        }
    }

    /// Fill in the process rows immediately when the panel opens, instead of
    /// making it wait out a tick.
    ///
    /// Deliberately *not* a full snapshot rebuild: that would take a second
    /// network reading milliseconds after the loop's, and `NetworkSampler`
    /// turns each call into one history slot, so opening the panel would push
    /// a meaningless near-zero rate into the graph and shift the window.
    func refreshProcesses() async {
        guard samplesProcesses else { return }
        let tops = await process.sampleTops()
        // Re-read: the loop may have published a new snapshot across the await.
        guard var current = snapshot else { return }
        current.topCPU = tops.topCPU
        current.topMemory = tops.topMemory
        snapshot = current
    }

    /// Nil on the first tick: CPU is a delta and has no baseline yet, and a
    /// fake 0% would land in the history as if it were a real reading.
    private func buildSnapshot() async -> Snapshot? {
        // Mach/sysctl reads are microseconds; the `ps` shell-out is not, so it
        // lives on the ProcessSampler actor rather than the main actor.
        guard let c = cpu.sample() else { return nil }
        let m = memory.sample()
        let g = gpu.sample()
        let d = disk.sample()
        let n = network.sample(interval: updateInterval)

        append(c.overall, to: \.cpu)
        append(g.utilization ?? 0, to: \.gpu)
        append(m.percent, to: \.memory)
        append(d.percent, to: \.disk)

        let raised = alerts.evaluate(
            values: [.cpu: c.overall, .gpu: g.utilization ?? 0, .memory: m.percent, .disk: d.percent],
            settings: alertSettings
        )
        if alertSettings.notify {
            for alert in alerts.newlyTriggered {
                notifier.post(alert)
            }
        }

        let tops: (topCPU: [ProcessEntry], topMemory: [ProcessEntry])
        if samplesProcesses {
            tops = await process.sampleTops()
        } else {
            // Keep the last known rows so reopening the panel isn't blank.
            tops = (snapshot?.topCPU ?? [], snapshot?.topMemory ?? [])
        }

        return Snapshot(
            cpu: c,
            memory: m,
            gpu: g,
            disk: d,
            network: n,
            topCPU: tops.topCPU,
            topMemory: tops.topMemory,
            history: history,
            alerts: raised
        )
    }

    /// Grows to `historyLength` then slides. No zero padding; see `MetricHistory`.
    private func append(_ value: Double, to keyPath: WritableKeyPath<MetricHistory, [Double]>) {
        var series = history[keyPath: keyPath]
        series.append(value)
        if series.count > historyLength {
            series.removeFirst(series.count - historyLength)
        }
        history[keyPath: keyPath] = series
    }
}
