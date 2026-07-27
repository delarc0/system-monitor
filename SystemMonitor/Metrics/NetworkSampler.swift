import Darwin
import Foundation

/// Network throughput sampler.
///
/// Counters come from `sysctl(NET_RT_IFLIST2)` → `if_data64`. The obvious
/// `getifaddrs` route exposes `if_data`, whose `ifi_ibytes`/`ifi_obytes` are
/// `u_int32_t` and therefore wrap every 4 GiB. Widening a wrapped counter to
/// `UInt64` before subtracting turns one wrap into a ~1.8e19 byte delta, which
/// pinned the chart's Y scale for the rest of the window and flattened every
/// real reading to zero. `if_data64` doesn't wrap.
final class NetworkSampler {
    /// Samples retained for the graph. At the default 2 s tick that's 2 minutes.
    private let historyLength = 60

    /// Longest plausible gap between two ticks. Anything larger means the app
    /// was suspended (sleep/wake, or a settings-driven restart), so the byte
    /// delta spans an unknown stretch of time and would render as a fake spike.
    private let maxGapSeconds: TimeInterval = 15

    private var previousIn: UInt64 = 0
    private var previousOut: UInt64 = 0
    private var previousTime: Date?
    private var downloadHistory: [Double]
    private var uploadHistory: [Double]

    /// Histories start empty and grow to `historyLength`. Pre-filling with
    /// zeros drew a fake flat line across the graph for the first minutes after
    /// launch; the view right-anchors a partial series against `capacity`.
    init() {
        downloadHistory = []
        uploadHistory = []
    }

    func sample(interval: TimeInterval) -> NetworkSample {
        guard let (bytesIn, bytesOut) = readCounters() else {
            return makeSample(down: 0, up: 0, interval: interval)
        }
        let now = Date()

        defer {
            previousIn = bytesIn
            previousOut = bytesOut
            previousTime = now
        }

        // First tick has no baseline; a long gap means the byte delta spans an
        // unknown stretch of time and isn't a rate.
        guard let prev = previousTime else {
            return makeSample(down: 0, up: 0, interval: interval)
        }
        let dt = now.timeIntervalSince(prev)
        guard dt > 0, dt <= maxGapSeconds else {
            return push(down: 0, up: 0, interval: interval)
        }

        // Interfaces can be removed and re-added (VPN, dock, Wi-Fi toggle),
        // which restarts their counters. Clamp instead of underflowing.
        let deltaIn = bytesIn > previousIn ? bytesIn - previousIn : 0
        let deltaOut = bytesOut > previousOut ? bytesOut - previousOut : 0

        return push(down: Double(deltaIn) / dt, up: Double(deltaOut) / dt, interval: interval)
    }

    private func push(down: Double, up: Double, interval: TimeInterval) -> NetworkSample {
        downloadHistory.append(down)
        uploadHistory.append(up)
        if downloadHistory.count > historyLength {
            downloadHistory.removeFirst(downloadHistory.count - historyLength)
        }
        if uploadHistory.count > historyLength {
            uploadHistory.removeFirst(uploadHistory.count - historyLength)
        }
        return makeSample(down: down, up: up, interval: interval)
    }

    private func makeSample(down: Double, up: Double, interval: TimeInterval) -> NetworkSample {
        NetworkSample(
            downloadBps: down,
            uploadBps: up,
            downloadHistory: downloadHistory,
            uploadHistory: uploadHistory,
            downloadString: Self.format(down),
            uploadString: Self.format(up),
            windowSeconds: Int(Double(historyLength) * interval),
            capacity: historyLength
        )
    }

    /// Interfaces that would double-count or add noise: `utun` (VPN/Tailscale, where
    /// the same bytes already traverse the physical link), `awdl`/`llw` (AirDrop
    /// and low-latency WLAN), `anpi` (internal baseband link), plus the usual
    /// virtual and bridged families.
    private static let skippedPrefixes = [
        "utun", "awdl", "llw", "anpi", "ap", "bridge", "gif", "stf", "feth", "vmenet"
    ]

    private func readCounters() -> (UInt64, UInt64)? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]

        var len = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: len)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            sysctl(&mib, u_int(mib.count), raw.baseAddress, &len, nil, 0) == 0
        }
        guard ok else { return nil }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        let byteCount = min(len, buffer.count)

        buffer.withUnsafeBytes { raw in
            var offset = 0
            // Messages are packed without padding, so loads must be unaligned.
            while offset + MemoryLayout<if_msghdr>.size <= byteCount {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                defer { offset += messageLength }

                // The list also carries multicast-address messages; only
                // RTM_IFINFO2 records are laid out as `if_msghdr2`.
                guard header.ifm_type == RTM_IFINFO2,
                      offset + MemoryLayout<if_msghdr2>.size <= byteCount else { continue }

                let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                let flags = UInt32(bitPattern: info.ifm_flags)
                guard (flags & UInt32(IFF_UP)) != 0,
                      (flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }

                let nameOffset = offset + MemoryLayout<if_msghdr2>.size
                guard let name = interfaceName(raw, at: nameOffset, limit: byteCount),
                      !Self.skippedPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

                bytesIn &+= info.ifm_data.ifi_ibytes
                bytesOut &+= info.ifm_data.ifi_obytes
            }
        }

        return (bytesIn, bytesOut)
    }

    /// The `sockaddr_dl` immediately following the header carries the interface
    /// name as `sdl_nlen` bytes at the head of `sdl_data`, not NUL-terminated.
    private func interfaceName(_ raw: UnsafeRawBufferPointer, at offset: Int, limit: Int) -> String? {
        guard offset + MemoryLayout<sockaddr_dl>.size <= limit else { return nil }
        let sdl = raw.loadUnaligned(fromByteOffset: offset, as: sockaddr_dl.self)
        let nameLength = Int(sdl.sdl_nlen)
        guard nameLength > 0 else { return nil }
        let bytes = withUnsafeBytes(of: sdl.sdl_data) { Array($0.prefix(nameLength)) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func format(_ bps: Double) -> String {
        let gb = Double(1 << 30)
        let mb = Double(1 << 20)
        let kb = Double(1 << 10)
        if bps >= gb { return String(format: "%.1f GB/s", bps / gb) }
        if bps >= mb { return String(format: "%.1f MB/s", bps / mb) }
        if bps >= kb { return String(format: "%.0f KB/s", bps / kb) }
        return String(format: "%.0f B/s", bps)
    }
}
