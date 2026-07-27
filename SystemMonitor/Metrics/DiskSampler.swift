import Foundation
import IOKit

/// Disk sampler: capacity from the filesystem, throughput from IOKit's
/// per-driver byte counters.
///
/// Capacity uses `volumeAvailableCapacityForImportantUsage`, which is what
/// Finder and Storage Settings report; plain `volumeAvailableCapacity` ignores
/// purgeable space and reads several hundred GB lower than the number the user
/// sees everywhere else.
final class DiskSampler {
    private let maxGapSeconds: TimeInterval = 15

    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0
    private var previousTime: Date?

    func sample() -> DiskSample {
        let capacity = readCapacity()
        guard let (read, write) = readCounters() else {
            return makeSample(capacity: capacity, read: 0, write: 0)
        }
        let now = Date()

        defer {
            previousRead = read
            previousWrite = write
            previousTime = now
        }

        guard let prev = previousTime else {
            return makeSample(capacity: capacity, read: 0, write: 0)
        }
        let dt = now.timeIntervalSince(prev)
        guard dt > 0, dt <= maxGapSeconds else {
            return makeSample(capacity: capacity, read: 0, write: 0)
        }

        // Drives can be attached and detached mid-run, which drops their
        // counters out of the sum. Clamp instead of underflowing.
        let deltaRead = read > previousRead ? read - previousRead : 0
        let deltaWrite = write > previousWrite ? write - previousWrite : 0

        return makeSample(
            capacity: capacity,
            read: Double(deltaRead) / dt,
            write: Double(deltaWrite) / dt
        )
    }

    private func makeSample(capacity: (total: Double, free: Double), read: Double, write: Double) -> DiskSample {
        let used = max(0, capacity.total - capacity.free)
        return DiskSample(
            totalGB: capacity.total,
            usedGB: used,
            freeGB: capacity.free,
            percent: capacity.total > 0 ? used / capacity.total * 100 : 0,
            readBps: read,
            writeBps: write,
            readString: NetworkSampler.format(read),
            writeString: NetworkSampler.format(write)
        )
    }

    private func readCapacity() -> (total: Double, free: Double) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else {
            return (0, 0)
        }
        let gb = 1_073_741_824.0
        let total = Double(values.volumeTotalCapacity ?? 0) / gb
        let free = Double(values.volumeAvailableCapacityForImportantUsage ?? 0) / gb
        return (total, free)
    }

    /// Summed across every block storage driver, so an external or second
    /// internal drive counts too.
    private func readCounters() -> (UInt64, UInt64)? {
        guard let match = IOServiceMatching("IOBlockStorageDriver") else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else {
                continue
            }

            if let bytes = stats["Bytes (Read)"] as? Int64, bytes > 0 { read &+= UInt64(bytes) }
            if let bytes = stats["Bytes (Write)"] as? Int64, bytes > 0 { write &+= UInt64(bytes) }
        }

        return (read, write)
    }
}
