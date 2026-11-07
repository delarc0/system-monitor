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
    private var downloadRate = RateCounter()
    private var uploadRate = RateCounter()
    private var downloadHistory: [Double] = []
    private var uploadHistory: [Double] = []

    func sample() -> NetworkSample {
        let now = Date()
        let counters = readCounters()
        let down = downloadRate.rate(counters.in, now: now)
        let up = uploadRate.rate(counters.out, now: now)
        if let down, let up {
            downloadHistory.pushToHistory(down)
            uploadHistory.pushToHistory(up)
        }
        return NetworkSample(
            downloadBps: down ?? 0,
            uploadBps: up ?? 0,
            downloadHistory: downloadHistory,
            uploadHistory: uploadHistory
        )
    }

    /// Interfaces that would double-count or add noise: `utun` (VPN/Tailscale, where
    /// the same bytes already traverse the physical link), `awdl`/`llw` (AirDrop
    /// and low-latency WLAN), `anpi` (internal baseband link), plus the usual
    /// virtual and bridged families.
    private static let skippedPrefixes = [
        "utun", "awdl", "llw", "anpi", "ap", "bridge", "gif", "stf", "feth", "vmenet"
    ]

    private func readCounters() -> (in: [String: UInt64], out: [String: UInt64]) {
        var bytesIn: [String: UInt64] = [:]
        var bytesOut: [String: UInt64] = [:]
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]

        var len = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return (bytesIn, bytesOut) }

        var buffer = [UInt8](repeating: 0, count: len)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            sysctl(&mib, u_int(mib.count), raw.baseAddress, &len, nil, 0) == 0
        }
        guard ok else { return (bytesIn, bytesOut) }

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

                bytesIn[name] = info.ifm_data.ifi_ibytes
                bytesOut[name] = info.ifm_data.ifi_obytes
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
}
