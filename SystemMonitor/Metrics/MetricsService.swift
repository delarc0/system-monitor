import Foundation
import SwiftUI

/// Orchestrates sampling and publishes the results on the main actor.
///
/// Three independent loops, so the slow ones can never hold up the numbers in the
/// menu bar: the main tick is microsecond reads only, `ps` runs only while the panel
/// is open, and `claude` runs only when its saved reading has gone stale.
@MainActor
final class MetricsService: ObservableObject {
    static let shared = MetricsService()
    static let interval: TimeInterval = 2

    private static let claudeSavedCheckEvery: TimeInterval = 30
    /// A running session rewrites the saved reading about every 5 minutes and sometimes
    /// skips one, which must not set off a heavy run.
    private static let claudeStaleAfter: TimeInterval = 15 * 60
    private static let claudeRetryEvery: TimeInterval = 30 * 60
    private static let claudeRetryEveryOnOpen: TimeInterval = 5 * 60

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var processes = TopProcesses()
    @Published private(set) var claude: ClaudeUsage?

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let gpu = GPUSampler()
    private let disk = DiskSampler()
    private let network = NetworkSampler()
    private let process = ProcessSampler()

    private var history = MetricHistory()
    private var loop: Task<Void, Never>?
    private var processLoop: Task<Void, Never>?
    private var claudeFetch: Task<Void, Never>?
    // First fetch 30 s after launch: login is already the busiest moment of the day.
    private var claudeAttemptedAt = Date(timeIntervalSinceNow: 30 - claudeRetryEvery)
    private var claudeSavedCheckedAt = Date.distantPast
    private var activity: NSObjectProtocol?

    func start() {
        guard loop == nil else { return }
        // An agent with no visible window is App Nap's first target. A napped timer can
        // overrun RateCounter's gap guard, and then every rate reads as a sleep.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Live system readings in the menu bar"
        )
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let snapshot = self.buildSnapshot() { self.snapshot = snapshot }
                self.readSavedClaude()
                self.refreshClaude(retryEvery: Self.claudeRetryEvery)
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    /// The process list is only ever read by the panel, so `ps` runs only while it is
    /// open. The last rows stay, so reopening isn't blank.
    func setPanelVisible(_ visible: Bool) {
        processLoop?.cancel()
        processLoop = nil
        guard visible else { return }

        refreshClaude(retryEvery: Self.claudeRetryEveryOnOpen)
        processLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let tops = await self.process.sampleTops()
                // A `ps` that finished after the panel closed has nobody to report to.
                guard !Task.isCancelled else { return }
                if let tops { self.processes = tops }
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    private func readSavedClaude() {
        guard Date().timeIntervalSince(claudeSavedCheckedAt) >= Self.claudeSavedCheckEvery else { return }
        claudeSavedCheckedAt = Date()
        Task { [weak self] in
            let saved = await Task.detached(priority: .utility) { ClaudeSampler.readSaved() }.value
            guard let self, let saved, saved.readAt > (self.claude?.readAt ?? .distantPast) else { return }
            self.claude = saved
        }
    }

    private func refreshClaude(retryEvery: TimeInterval) {
        guard ClaudeSampler.binaryPath != nil,
              claudeFetch == nil,
              Date().timeIntervalSince(claude?.readAt ?? .distantPast) >= Self.claudeStaleAfter,
              Date().timeIntervalSince(claudeAttemptedAt) >= retryEvery else { return }
        claudeAttemptedAt = Date()
        claudeFetch = Task { [weak self] in
            // A failed run keeps the last reading, which the panel marks with its age.
            if let usage = await ClaudeSampler.fetch() { self?.claude = usage }
            self?.claudeFetch = nil
        }
    }

    /// Nil on the first tick: CPU is a delta and has no baseline yet, and a
    /// fake 0% would land in the history as if it were a real reading.
    private func buildSnapshot() -> Snapshot? {
        guard let c = cpu.sample() else { return nil }
        let m = memory.sample()
        let g = gpu.sample()

        history.cpu.pushToHistory(c.overall)
        history.memory.pushToHistory(m.percent)
        if let utilization = g.utilization { history.gpu.pushToHistory(utilization) }

        return Snapshot(
            cpu: c,
            memory: m,
            gpu: g,
            disk: disk.sample(),
            network: network.sample(),
            history: history
        )
    }
}
