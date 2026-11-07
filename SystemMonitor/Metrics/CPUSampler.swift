import Darwin
import Foundation

/// Overall CPU load from the delta of Mach tick counters across two reads.
///
/// Overall only, on purpose. Core types differ per chip (the M5 Max has Super and
/// Performance cores and no efficiency cores), so a per-type split needs the real
/// core map, and an order-based guess shipped wrong labels.
final class CPUSampler {
    private var previous: host_cpu_load_info?

    /// Nil on the first read, which has no baseline, and on a failed read.
    func sample() -> CPUSample? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { typed in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, typed, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        defer { previous = info }
        guard let last = previous else { return nil }

        let user = Double(info.cpu_ticks.0 &- last.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- last.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- last.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- last.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }

        return CPUSample(
            overall: (user + system + nice) / total * 100,
            thermal: ProcessInfo.processInfo.thermalState
        )
    }
}
