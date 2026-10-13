import Foundation
import IOKit

/// GPU utilization via IOKit AGXAccelerator registry.
struct GPUSampler {
    func sample() -> GPUSample {
        guard let match = IOServiceMatching("AGXAccelerator") else {
            return GPUSample(utilization: nil)
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            return GPUSample(utilization: nil)
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            // One key, not the whole property dictionary: this runs every tick.
            // M-series chips report via PerformanceStatistics.
            if let perf = property(service, "PerformanceStatistics") as? [String: Any],
               let util = perf["Device Utilization %"] as? Int {
                return GPUSample(utilization: Double(util))
            }
            // Older / alternate keys.
            for key in ["gpu-core-utilization-%", "gpu-utilization-%"] {
                if let util = property(service, key) as? Int {
                    return GPUSample(utilization: Double(util))
                }
            }
        }

        return GPUSample(utilization: nil)
    }

    private func property(_ service: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
