import Darwin
import Foundation

/// Network throughput sampler using `getifaddrs` → `if_data` byte counters.
/// Maintains a 30-slot rolling history for graphing.
final class NetworkSampler {
    private let historyLength = 30
    private var previousIn: UInt64 = 0
    private var previousOut: UInt64 = 0
    private var previousTime: Date?
    private var downloadHistory: [Double]
    private var uploadHistory: [Double]

    init() {
        downloadHistory = Array(repeating: 0, count: historyLength)
        uploadHistory = Array(repeating: 0, count: historyLength)
    }

    func sample() -> NetworkSample {
        let (bytesIn, bytesOut) = readCounters()
        let now = Date()

        defer {
            previousIn = bytesIn
            previousOut = bytesOut
            previousTime = now
        }

        guard let prev = previousTime else {
            return emptySample()
        }

        let dt = max(now.timeIntervalSince(prev), 0.001)
        let downBps = Double(bytesIn &- previousIn) / dt
        let upBps = Double(bytesOut &- previousOut) / dt

        downloadHistory.removeFirst()
        downloadHistory.append(downBps)
        uploadHistory.removeFirst()
        uploadHistory.append(upBps)

        return NetworkSample(
            downloadBps: downBps,
            uploadBps: upBps,
            downloadHistory: downloadHistory,
            uploadHistory: uploadHistory,
            downloadString: Self.format(downBps),
            uploadString: Self.format(upBps)
        )
    }

    private func emptySample() -> NetworkSample {
        NetworkSample(
            downloadBps: 0,
            uploadBps: 0,
            downloadHistory: downloadHistory,
            uploadHistory: uploadHistory,
            downloadString: "0 B/s",
            uploadString: "0 B/s"
        )
    }

    private func readCounters() -> (UInt64, UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }

            let name = String(cString: cur.pointee.ifa_name)
            let flags = cur.pointee.ifa_flags
            guard (flags & UInt32(IFF_UP)) != 0,
                  (flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }

            // Skip virtual / pseudo-interfaces.
            if name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("llw") ||
               name.hasPrefix("gif") || name.hasPrefix("stf") || name.hasPrefix("bridge") {
                continue
            }

            // Only AF_LINK entries carry populated if_data.
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else {
                continue
            }

            bytesIn &+= UInt64(data.pointee.ifi_ibytes)
            bytesOut &+= UInt64(data.pointee.ifi_obytes)
        }
        return (bytesIn, bytesOut)
    }

    static func format(_ bps: Double) -> String {
        let gb = 1 << 30
        let mb = 1 << 20
        let kb = 1 << 10
        if bps >= Double(gb) { return String(format: "%.1f GB/s", bps / Double(gb)) }
        if bps >= Double(mb) { return String(format: "%.1f MB/s", bps / Double(mb)) }
        if bps >= Double(kb) { return String(format: "%.1f KB/s", bps / Double(kb)) }
        return String(format: "%.0f B/s", bps)
    }
}
