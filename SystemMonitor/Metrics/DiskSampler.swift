import Foundation
import IOKit

/// Disk sampler: capacity from the filesystem, throughput from IOKit's per-driver
/// byte counters.
///
/// Capacity uses `volumeAvailableCapacityForImportantUsage`, which is what Finder
/// and Storage Settings report; plain `volumeAvailableCapacity` ignores purgeable
/// space and reads several hundred GB lower than the number the user sees elsewhere.
final class DiskSampler {
    /// The important-usage lookup takes about 8 ms and up to 24 ms, against 0.1 ms for
    /// the other reads, and it runs on the main actor. Free space barely moves in a minute.
    private static let capacityMaxAge: TimeInterval = 60

    private var capacity: (total: Double, free: Double) = (0, 0)
    private var capacityReadAt: Date?
    private var readRate = RateCounter()
    private var writeRate = RateCounter()

    func sample() -> DiskSample {
        let now = Date()
        if capacityReadAt.map({ now.timeIntervalSince($0) >= Self.capacityMaxAge }) ?? true,
           let fresh = readCapacity() {
            capacity = fresh
            capacityReadAt = now
        }

        let counters = readCounters()
        let used = max(0, capacity.total - capacity.free)
        return DiskSample(
            totalGB: capacity.total,
            freeGB: capacity.free,
            percent: capacity.total > 0 ? used / capacity.total * 100 : 0,
            readBps: readRate.rate(counters.read, now: now) ?? 0,
            writeBps: writeRate.rate(counters.write, now: now) ?? 0
        )
    }

    private func readCapacity() -> (total: Double, free: Double)? {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]) else { return nil }
        let gb = 1_073_741_824.0
        return (
            Double(values.volumeTotalCapacity ?? 0) / gb,
            Double(values.volumeAvailableCapacityForImportantUsage ?? 0) / gb
        )
    }

    /// Every block storage driver, so an external or second internal drive counts too.
    private func readCounters() -> (read: [String: UInt64], write: [String: UInt64]) {
        var read: [String: UInt64] = [:]
        var write: [String: UInt64] = [:]
        guard let match = IOServiceMatching("IOBlockStorageDriver") else { return (read, write) }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            return (read, write)
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var entryID: UInt64 = 0
            // One key, not the whole property dictionary: this runs every tick.
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
                  let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] else { continue }

            let key = String(entryID)
            if let bytes = stats["Bytes (Read)"] as? Int64, bytes > 0 { read[key] = UInt64(bytes) }
            if let bytes = stats["Bytes (Write)"] as? Int64, bytes > 0 { write[key] = UInt64(bytes) }
        }
        return (read, write)
    }
}
