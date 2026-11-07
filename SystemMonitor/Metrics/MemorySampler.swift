import Darwin
import Foundation

struct MemorySampler {
    /// Activity Monitor's "Memory Used": app memory + wired + compressed. App memory
    /// is anonymous pages minus purgeable; "active" would count file cache the system
    /// can drop at any moment, which read 8 points high on a 64 GB Mac.
    static func usedPages(internal anonymous: UInt64, purgeable: UInt64, wired: UInt64, compressed: UInt64) -> UInt64 {
        (anonymous > purgeable ? anonymous - purgeable : 0) + wired + compressed
    }

    func sample() -> MemorySample {
        let total = Sysctl.uint64("hw.memsize") ?? 0
        // host_page_size, not the vm_kernel_page_size global: Swift 6 rejects mutable C globals.
        var kernelPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &kernelPageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { typed in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, typed, &count)
            }
        }

        var used: UInt64 = 0
        if result == KERN_SUCCESS {
            used = Self.usedPages(
                internal: UInt64(stats.internal_page_count),
                purgeable: UInt64(stats.purgeable_count),
                wired: UInt64(stats.wire_count),
                compressed: UInt64(stats.compressor_page_count)
            ) * UInt64(kernelPageSize)
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0

        return MemorySample(
            totalGB: Double(total) / 1_073_741_824,
            usedGB: Double(used) / 1_073_741_824,
            percent: total > 0 ? Double(used) / Double(total) * 100 : 0,
            swapUsedGB: Double(swapUsed) / 1_073_741_824,
            pressure: MemoryPressure(level: Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1)
        )
    }
}
