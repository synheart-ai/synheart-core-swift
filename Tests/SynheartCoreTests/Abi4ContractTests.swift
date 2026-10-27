import XCTest
@testable import SynheartCore

/// Pins what the SDK sends across C ABI 4.0 (runtime 0.42) that no native call
/// can check for it: the per-sample UTC offset, the local dates of daily
/// values, and the daily metric names. `dlsym` checks no signature, so these
/// are the contract.
final class Abi4ContractTests: XCTestCase {

    func testUtcOffsetIsTheOffsetInForceAtTheSample() {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        // 2026-01-15 and 2026-07-15, noon UTC: CET then CEST.
        XCTAssertEqual(CoreRuntimeBridge.utcOffsetMin(atMs: 1_768_478_400_000, timeZone: berlin), 60)
        XCTAssertEqual(CoreRuntimeBridge.utcOffsetMin(atMs: 1_784_116_800_000, timeZone: berlin), 120)
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        XCTAssertEqual(CoreRuntimeBridge.utcOffsetMin(atMs: 1_768_478_400_000, timeZone: kolkata), 330)
    }

    func testUtcOffsetStaysWithinTheRuntimeBound() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        XCTAssertTrue((-840...840).contains(CoreRuntimeBridge.utcOffsetMin(atMs: now)))
    }

    func testLocalDateIsThePersonsCalendarDate() {
        // 22:30 UTC on the 14th is 07:30 on the 15th in Tokyo.
        let instant = Date(timeIntervalSince1970: 1_768_429_800)
        let d = Synheart.localDate(instant, TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(d.year, 2026)
        XCTAssertEqual(d.month, 1)
        XCTAssertEqual(d.day, 15)
    }

    func testDailyMetricNamesExactlyTheTwelveTheRuntimeAccepts() {
        // The runtime refuses any other name with 1004, including the names
        // these replaced, so this set is the contract.
        XCTAssertEqual(DailyMetric.all, [
            "sleep.duration_s",
            "sleep.midpoint_h",
            "cardiac.overnight_rmssd_ms",
            "cardiac.overnight_sdnn_ms",
            "cardiac.resting_hr_bpm",
            "vendor.recovery_frac",
            "sleep.deep_min",
            "sleep.rem_min",
            "vendor.strain_frac",
            "motion.steps_count",
            "cardiac.hrr_load_au",
            "cardiac.overnight_hr_sd_bpm",
        ])
    }

    func testRecoveryIsSentAsAFraction() {
        XCTAssertEqual(LongitudinalSrmModule.recoveryFraction(72)!, 0.72, accuracy: 1e-9)
        XCTAssertEqual(LongitudinalSrmModule.recoveryFraction(0.72)!, 0.72, accuracy: 1e-9)
        XCTAssertNil(LongitudinalSrmModule.recoveryFraction(140))
        XCTAssertNil(LongitudinalSrmModule.recoveryFraction(-1))
    }

    func testSleepMidpointIsHoursAfterLocalMidnight() {
        // 18:30 UTC is 03:30 in Tokyo.
        let h = LongitudinalSrmModule.midpointHours("2026-01-14T18:30:00Z", timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(h!, 3.5, accuracy: 1e-9)
    }

    // MARK: Input capture gate

    func testInputCaptureRunsOnlyWhileTrackingAndActive() {
        var reports: [Bool] = []
        let gate = InputCaptureGate { reports.append($0) }
        gate.setTracking(true)
        XCTAssertEqual(reports, [])
        gate.setForeground(true)
        XCTAssertEqual(reports, [true])
        gate.setForeground(false)
        XCTAssertEqual(reports, [true, false])
        gate.setForeground(true)
        gate.setTracking(false)
        XCTAssertEqual(reports, [true, false, true, false])
    }

    func testInputCaptureReportsOnlyChangesAndNothingBeforeFirstRunning() {
        var reports: [Bool] = []
        let gate = InputCaptureGate { reports.append($0) }
        gate.setForeground(false)
        gate.setTracking(false)
        gate.setForeground(true)
        XCTAssertEqual(reports, [])
        gate.setTracking(true)
        gate.setTracking(true)
        XCTAssertEqual(reports, [true])
        gate.reset()
        XCTAssertNil(gate.lastReported)
    }
}
