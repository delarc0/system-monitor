import XCTest
@testable import SystemMonitor

/// The logic a UI screenshot cannot prove, and where a wrong number would hide.
final class LogicTests: XCTestCase {
    func testNiceCeilingNeverBelowPeak() {
        var peak = 1.0
        while peak < 1e13 {
            XCTAssertGreaterThanOrEqual(niceByteCeiling(peak), peak, "peak \(peak)")
            peak *= 1.37
        }
        for exact: Double in [1024, 1_048_576, 2 * 1_048_576, 5 * 1_073_741_824] {
            XCTAssertGreaterThanOrEqual(niceByteCeiling(exact), exact)
        }
    }

    func testRateCounterIgnoresMembershipChangesAndGaps() {
        var counter = RateCounter()
        let t0 = Date()
        func rate(_ seconds: Double, _ counters: [String: UInt64]) -> Double? {
            counter.rate(counters, now: t0.addingTimeInterval(seconds))
        }

        XCTAssertNil(rate(0, ["en0": 1000]), "first read has no baseline")
        XCTAssertEqual(rate(2, ["en0": 3000]), 1000)
        XCTAssertEqual(
            rate(4, ["en0": 5000, "en7": 900_000_000_000]), 1000,
            "an interface coming up with old bytes only sets a baseline, it is not a burst"
        )
        XCTAssertEqual(rate(6, ["en0": 5000, "en7": 100]), 0, "a restarted counter reads as idle, never underflows")
        XCTAssertNil(rate(60, ["en0": 9_000_000]), "a long gap means the Mac slept")
    }

    func testMemoryUsedExcludesFileCacheAndCannotUnderflow() {
        XCTAssertEqual(MemorySampler.usedPages(internal: 100, purgeable: 10, wired: 20, compressed: 5), 115)
        XCTAssertEqual(MemorySampler.usedPages(internal: 5, purgeable: 10, wired: 20, compressed: 5), 25)
    }

    func testProcessRowsParseSpacedPathsAndSkipBadLines() {
        let rows = ProcessSampler.parseRows("""
            12.5  2048 /Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Renderer).app/Contents/MacOS/Code Helper (Renderer)
             0.0   512 /bin/ps
            145,6 2048 /usr/libexec/syspolicyd
            garbage
            """)
        XCTAssertEqual(rows.count, 1, "ps itself and non-numeric rows are dropped")
        XCTAssertEqual(rows.first?.cpu, 12.5)
        XCTAssertEqual(rows.first?.rssKB, 2048)
        XCTAssertTrue(rows.first?.executablePath.hasSuffix("Code Helper (Renderer)") ?? false)
    }

    func testClaudeUsageParsesRealOutputAndNeverInventsZero() throws {
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-11-07T15:00:00Z"))
        let output = """
            You are currently using your subscription to power your Claude Code usage

            Current week (all models): 57% used · resets Nov 11 at 4pm (Europe/Stockholm)
            Current week (Fable): 30% used · resets Nov 11 at 3:59pm (Europe/Stockholm)
            """.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        let usage = try XCTUnwrap(ClaudeSampler.parse(output, now: now))
        XCTAssertEqual(usage.percent, 57, "all models, not the first percent it finds")
        XCTAssertEqual(usage.resets, "Nov 11 at 4pm")
        XCTAssertEqual(try XCTUnwrap(usage.weekElapsed), 3.0 / 7, accuracy: 0.001)

        XCTAssertNil(ClaudeSampler.parse("Total cost: $0.0000", now: now), "other output is no data, not 0%")
        let oddDate = ClaudeSampler.parse("Current week (all models): 10% used · resets soon", now: now)
        XCTAssertEqual(oddDate?.percent, 10)
        XCTAssertNil(oddDate?.weekElapsed, "an unreadable reset only hides the pace")
    }
}
