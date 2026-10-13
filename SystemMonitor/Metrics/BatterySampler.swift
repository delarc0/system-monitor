import Foundation
import IOKit

/// Battery level and net power from the `AppleSmartBattery` registry entry.
/// Nil on a desktop. `Amperage` is signed by direction, so the wattage is too.
struct BatterySampler {
    func sample() -> BatterySample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              // Already a 0..100 percentage on Apple Silicon (MaxCapacity is 100).
              let percent = dict["CurrentCapacity"] as? Double,
              let milliamps = dict["Amperage"] as? Double,
              let millivolts = dict["Voltage"] as? Double else { return nil }

        return BatterySample(
            percent: percent,
            isCharging: dict["IsCharging"] as? Bool ?? false,
            externalPower: dict["ExternalConnected"] as? Bool ?? false,
            watts: milliamps * millivolts / 1_000_000
        )
    }
}
