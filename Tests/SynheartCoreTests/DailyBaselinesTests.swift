import XCTest
@testable import SynheartCore

final class DailyBaselinesTests: XCTestCase {

    // MARK: - BaselineRefs

    func testBaselineRefsReadsAllFourFields() {
        let refs = BaselineRefs.fromJson([
            "hrv_rmssd_ms": 48.5, "hrv_confidence": 0.62,
            "resting_hr_bpm": 56, "rhr_confidence": 0.4,
        ])
        XCTAssertEqual(refs?.hrvRmssdMs, 48.5)
        XCTAssertEqual(refs?.restingHrBpm, 56)
        XCTAssertEqual(refs?.maturity ?? -1, 0.4, accuracy: 1e-9)
    }

    func testBaselineRefsIsNilWhenAFieldIsMissingOrNotANumber() {
        XCTAssertNil(BaselineRefs.fromJson([
            "hrv_rmssd_ms": 48.5, "hrv_confidence": 0.62, "resting_hr_bpm": 56,
        ]))
        XCTAssertNil(BaselineRefs.fromJson([
            "hrv_rmssd_ms": 48.5, "hrv_confidence": 0.62,
            "resting_hr_bpm": NSNull(), "rhr_confidence": 0.4,
        ]))
        XCTAssertNil(BaselineRefs.fromJson([
            "hrv_rmssd_ms": "48.5", "hrv_confidence": 0.62,
            "resting_hr_bpm": 56, "rhr_confidence": 0.4,
        ]))
    }

    func testMaturityIsTheLowerConfidenceClampedToUnit() {
        XCTAssertEqual(BaselineRefs(hrvRmssdMs: 1, hrvConfidence: 0.2, restingHrBpm: 1, rhrConfidence: 0.9).maturity, 0.2)
        XCTAssertEqual(BaselineRefs(hrvRmssdMs: 1, hrvConfidence: 1.4, restingHrBpm: 1, rhrConfidence: 2).maturity, 1)
        XCTAssertEqual(BaselineRefs(hrvRmssdMs: 1, hrvConfidence: -0.3, restingHrBpm: 1, rhrConfidence: 0.5).maturity, 0)
        XCTAssertEqual(BaselineRefs(hrvRmssdMs: 1, hrvConfidence: .nan, restingHrBpm: 1, rhrConfidence: 0.5).maturity, 0)
    }

    // MARK: - SleepBaselines

    func testSleepBaselinesReadsEachReferenceAndLeavesTheRestNil() {
        let b = SleepBaselines.fromJson([
            "midpoint_h": ["value": 0.0, "confidence": 0.5],
            "overnight_hr_bpm": ["value": 54.2, "confidence": 0.8],
            "deep_min": NSNull(),
            "rem_min": ["value": 95],
        ])
        // 0.0 is midnight: a value, kept.
        XCTAssertEqual(b.midpointH, DailyRef(value: 0, confidence: 0.5))
        XCTAssertEqual(b.overnightHrBpm?.value, 54.2)
        XCTAssertNil(b.deepMin)
        XCTAssertNil(b.remMin, "a reference without a confidence is not one")
    }

    func testSleepBaselinesFromAnEmptyObjectHasNoReferences() {
        XCTAssertEqual(SleepBaselines.fromJson([:]), SleepBaselines())
    }

    // MARK: - SleepScoreInput

    private let tonight = NightRaw(wakeCalendarDate: 20261030, detail: .vendorScore(score: 80))

    func testSleepScoreInputSendsANullMidpointAndNoBaselinesByDefault() {
        let json = SleepScoreInput(tonight: tonight).toJson()
        XCTAssertTrue(json["tonight_midpoint_h"] is NSNull)
        XCTAssertNil(json["baselines"])
    }

    func testSleepScoreInputSendsTheMidpointAndBaselines() throws {
        let input = SleepScoreInput(
            tonight: tonight,
            tonightMidpointH: 0.0,
            baselines: SleepBaselines(midpointH: DailyRef(value: 3.5, confidence: 0.7))
        )
        let json = input.toJson()
        XCTAssertEqual(json["tonight_midpoint_h"] as? Double, 0.0)
        let baselines = try XCTUnwrap(json["baselines"] as? [String: Any])
        XCTAssertEqual((baselines["midpoint_h"] as? [String: Any])?["value"] as? Double, 3.5)
        XCTAssertTrue(baselines["deep_min"] is NSNull)
        // Serialises: every value is a JSON type.
        XCTAssertNotEqual(input.toJsonString(), "{}")
    }

    // MARK: - DailyMetric

    func testDailyMetricNamesTheAbiFourTwoMetrics() {
        XCTAssertTrue(DailyMetric.all.contains("cardiac.overnight_hr_bpm"))
        XCTAssertTrue(DailyMetric.all.contains("cardiac.rest_rmssd_ms"))
        XCTAssertTrue(DailyMetric.all.contains("motion.active_min"))
        XCTAssertEqual(DailyMetric.all.count, 15)
    }
}
