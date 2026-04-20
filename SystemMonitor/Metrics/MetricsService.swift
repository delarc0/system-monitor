import Foundation
import SwiftUI

/// Orchestrates sampling and publishes the latest `Snapshot` on the main actor.
@MainActor
final class MetricsService: ObservableObject {
    static let shared = MetricsService()

    @Published private(set) var snapshot: Snapshot?

    var updateInterval: TimeInterval = 2.0

    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let gpu = GPUSampler()
    private let network = NetworkSampler()
    private let process = ProcessSampler()
    private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let snap = await self.buildSnapshot()
                self.snapshot = snap
                try? await Task.sleep(for: .seconds(self.updateInterval))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func restart() {
        stop()
        start()
    }

    private func buildSnapshot() async -> Snapshot {
        // Fast Mach/sysctl calls stay on main; ps shell-out is offloaded.
        let c = cpu.sample()
        let m = memory.sample()
        let g = gpu.sample()
        let n = network.sample()
        let sampler = process
        let tops = await Task.detached(priority: .utility) {
            sampler.sampleTops()
        }.value
        return Snapshot(cpu: c, memory: m, gpu: g, network: n, topCPU: tops.topCPU, topMemory: tops.topMemory)
    }
}
