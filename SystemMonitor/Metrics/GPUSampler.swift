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

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // M-series chips report via PerformanceStatistics.
            if let perf = dict["PerformanceStatistics"] as? [String: Any],
               let util = perf["Device Utilization %"] as? Int {
                return GPUSample(utilization: Double(util))
            }
            // Older / alternate keys.
            if let util = dict["gpu-core-utilization-%"] as? Int {
                return GPUSample(utilization: Double(util))
            }
            if let util = dict["gpu-utilization-%"] as? Int {
                return GPUSample(utilization: Double(util))
            }
        }

        return GPUSample(utilization: nil)
    }
}
