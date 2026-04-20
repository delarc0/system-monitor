import Foundation

struct CPUSample: Sendable, Equatable {
    var overall: Double           // 0..100
    var perCore: [Double]
    var pCores: [Double]
    var eCores: [Double]
    var pCount: Int
    var eCount: Int
}

struct MemorySample: Sendable, Equatable {
    var totalGB: Double
    var usedGB: Double
    var availableGB: Double
    var percent: Double            // 0..100
    var swapTotalGB: Double
    var swapUsedGB: Double
    var swapPercent: Double
}

struct GPUSample: Sendable, Equatable {
    var utilization: Double?       // 0..100, nil if unavailable
}

struct NetworkSample: Sendable, Equatable {
    var downloadBps: Double
    var uploadBps: Double
    var downloadHistory: [Double]
    var uploadHistory: [Double]
    var downloadString: String
    var uploadString: String
}

struct ProcessEntry: Sendable, Identifiable, Equatable {
    let id: String
    var name: String
    var value: Double              // cpu% for topCPU, GB for topMemory
}

struct Snapshot: Sendable, Equatable {
    var cpu: CPUSample
    var memory: MemorySample
    var gpu: GPUSample
    var network: NetworkSample
    var topCPU: [ProcessEntry]
    var topMemory: [ProcessEntry]
}
