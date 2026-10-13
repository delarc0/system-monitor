import XCTest
@testable import SystemMonitor

/// The two pieces of logic a UI screenshot cannot prove.
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

    @MainActor
    func testAlertSustainHysteresisAndGapReset() {
        let monitor = AlertMonitor()
        var settings = AlertSettings()
        settings.sustainedSeconds = 10
        let t0 = Date()
        func tick(_ seconds: Double, cpu: Double) -> [MetricAlert] {
            monitor.evaluate(values: [.cpu: cpu, .memory: 0, .disk: 0], settings: settings, now: t0.addingTimeInterval(seconds))
        }

        XCTAssertTrue(tick(0, cpu: 95).isEmpty, "breach must be sustained before it alerts")
        XCTAssertTrue(tick(9, cpu: 95).isEmpty)
        XCTAssertEqual(tick(10, cpu: 95).map(\.metric), [.cpu])
        XCTAssertEqual(monitor.newlyTriggered.map(\.metric), [.cpu], "edge fires once")
        XCTAssertEqual(tick(12, cpu: 87).map(\.metric), [.cpu], "inside the 5 point clear margin stays alerting")
        XCTAssertTrue(monitor.newlyTriggered.isEmpty)
        XCTAssertTrue(tick(14, cpu: 84).isEmpty, "below the margin clears")

        _ = tick(16, cpu: 95)
        XCTAssertTrue(tick(40, cpu: 95).isEmpty, "a 24 s gap means the machine slept: breach clock restarts")
    }

    func testAlertSettingsDecodeToleratesMissingFields() throws {
        let decoded = try JSONDecoder().decode(AlertSettings.self, from: Data(#"{"cpu":75}"#.utf8))
        XCTAssertEqual(decoded.cpu, 75)
        XCTAssertEqual(decoded.memory, 90, "missing field keeps its default instead of wiping everything")
    }
}
