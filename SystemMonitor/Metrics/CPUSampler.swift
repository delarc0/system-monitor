import Darwin
import Foundation

/// CPU utilization sampler based on Mach host statistics.
/// Computes overall % from delta of CPU ticks across two samples.
final class CPUSampler {
    let pCount: Int
    let eCount: Int

    private var previousTotal: host_cpu_load_info?
    private var previousPerCore: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []

    init() {
        let p = Sysctl.int("hw.perflevel0.logicalcpu") ?? 0
        let e = Sysctl.int("hw.perflevel1.logicalcpu") ?? 0
        if p == 0 && e == 0 {
            // Non-Apple-Silicon: treat all as P-cores
            self.pCount = Int(ProcessInfo.processInfo.activeProcessorCount)
            self.eCount = 0
        } else {
            self.pCount = p
            self.eCount = e
        }
    }

    func sample() -> CPUSample {
        let overall = sampleOverall()
        let perCore = samplePerCore()
        let pSlice = Array(perCore.prefix(pCount))
        let eSlice = Array(perCore.dropFirst(pCount).prefix(eCount))
        return CPUSample(
            overall: overall,
            perCore: perCore,
            pCores: pSlice,
            eCores: eSlice,
            pCount: pCount,
            eCount: eCount
        )
    }

    private func sampleOverall() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { typed in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, typed, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }

        defer { previousTotal = info }
        guard let prev = previousTotal else { return 0 }

        let user = Double(info.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return (user + system + nice) / total * 100.0
    }

    private func samplePerCore() -> [Double] {
        var cpuCount = natural_t(0)
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount = mach_msg_type_number_t(0)

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return [] }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var results: [Double] = []
        var newPrev: [(UInt32, UInt32, UInt32, UInt32)] = []
        results.reserveCapacity(Int(cpuCount))
        newPrev.reserveCapacity(Int(cpuCount))

        for i in 0..<Int(cpuCount) {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            newPrev.append((user, system, idle, nice))

            if i < previousPerCore.count {
                let prev = previousPerCore[i]
                let du = Double(user &- prev.user)
                let ds = Double(system &- prev.system)
                let di = Double(idle &- prev.idle)
                let dn = Double(nice &- prev.nice)
                let total = du + ds + di + dn
                results.append(total > 0 ? (du + ds + dn) / total * 100.0 : 0)
            } else {
                results.append(0)
            }
        }

        previousPerCore = newPrev
        return results
    }
}
