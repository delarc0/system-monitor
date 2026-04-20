import Darwin
import Foundation

struct MemorySampler {
    func sample() -> MemorySample {
        let total = Sysctl.uint64("hw.memsize") ?? 0
        let pageSize = UInt64(vm_kernel_page_size)

        var vmInfo = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &vmInfo) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { typed in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, typed, &count)
            }
        }

        var used: UInt64 = 0
        var available: UInt64 = 0
        if kr == KERN_SUCCESS {
            let active = UInt64(vmInfo.active_count) * pageSize
            let wired = UInt64(vmInfo.wire_count) * pageSize
            let compressed = UInt64(vmInfo.compressor_page_count) * pageSize
            let inactive = UInt64(vmInfo.inactive_count) * pageSize
            let free = UInt64(vmInfo.free_count) * pageSize
            // Matches Activity Monitor's "Memory Used": app + wired + compressed.
            used = active + wired + compressed
            available = free + inactive
        }
        let percent = total > 0 ? Double(used) / Double(total) * 100.0 : 0

        // Swap
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsed = swap.xsu_used
            swapTotal = swap.xsu_total
        }
        let swapPct = swapTotal > 0 ? Double(swapUsed) / Double(swapTotal) * 100.0 : 0

        return MemorySample(
            totalGB: Double(total) / 1_073_741_824,
            usedGB: Double(used) / 1_073_741_824,
            availableGB: Double(available) / 1_073_741_824,
            percent: percent,
            swapTotalGB: Double(swapTotal) / 1_073_741_824,
            swapUsedGB: Double(swapUsed) / 1_073_741_824,
            swapPercent: swapPct
        )
    }
}
