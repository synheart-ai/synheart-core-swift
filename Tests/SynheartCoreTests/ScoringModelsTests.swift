// SPDX-License-Identifier: Apache-2.0
//
// Smoke tests for the scoring models. Asserts JSON round-trips and
// edge cases that matter for cross-language wire compatibility
// (null stages, unknown enum wires, default values).

import XCTest
@testable import SynheartCore

final class ScoringModelsTests: XCTestCase {

    // MARK: - SleepScore

    func testSleepPathFromWireFallsBackToProxy() {
        XCTAssertEqual(SleepPath.fromWire("stage"), .stage)
        XCTAssertEqual(SleepPath.fromWire("garbage"), .proxy)
        XCTAssertEqual(SleepPath.fromWire(nil), .proxy)
    }

    func testSleepScoreReasonReturnsNilOnMissing() {
        XCTAssertNil(SleepScoreReason.fromWire(nil))
        XCTAssertNil(SleepScoreReason.fromWire("garbage"))
        XCTAssertEqual(SleepScoreReason.fromWire("no_sleep_data"), .noSleepData)
    }

    func testAggregatedTotalsOmitsNilDeepAndRem() {
        let totals = AggregatedTotals(
            totalSleepMinutes: 420.0,
            deepSleepMinutes: nil, remSleepMinutes: nil,
            awakeMinutes: 30.0
        )
        let json = totals.toJson()
        XCTAssertNil(json["deep_sleep_minutes"])
        XCTAssertNil(json["rem_sleep_minutes"])
        XCTAssertEqual(json["total_sleep_minutes"] as? Double, 420.0)
    }

    func testNightInputAggregatedRoundTripsKindTag() {
        let night = NightInput.aggregated(
            sessionStartMs: 1000,
            sessionEndMs: 2000,
            totals: AggregatedTotals(totalSleepMinutes: 400, awakeMinutes: 20)
        )
        let json = night.toJson()
        XCTAssertEqual(json["kind"] as? String, "aggregated")
        XCTAssertEqual((json["session_start_ms"] as? Int64) ?? -1, 1000)
    }

    func testSleepScoreResultFromJsonToleratesMissingFields() throws {
        let r = try SleepScoreResult.fromJsonString(#"{"score": 72, "path": "stage"}"#)
        XCTAssertEqual(r.score, 72)
        XCTAssertEqual(r.path, .stage)
        XCTAssertEqual(r.mode, .coldStart) // default
        XCTAssertNil(r.reason)
        XCTAssertEqual(r.confidence, 0, accuracy: 0.0001)
        XCTAssertEqual(r.priorNightCount, 0)
    }

    func testWearableReferenceViewReadsRecentSleepScoreMedianFromDimensions() throws {
        let view = try WearableReferenceView.fromJsonString(
            #"{"status":"Stable","dimensions":{"recent_sleep_score_median":78,"hrv_rmssd_ms":42.5}}"#
        )
        XCTAssertEqual(view.status, "Stable")
        XCTAssertEqual(view.recentSleepScoreMedian, 78)
        XCTAssertEqual(view.dimensions["hrv_rmssd_ms"], 42.5)
    }

    // MARK: - SleepQuestionnaire

    func testSleepQuestionnaireComputesAsleepMinutes() {
        let bedtime = Date(timeIntervalSince1970: 1_000_000)
        let wakeTime = bedtime.addingTimeInterval(8 * 3600) // 480 min TIB
        let q = SleepQuestionnaireAnswers(
            bedtime: bedtime, wakeTime: wakeTime,
            sleepLatencyMinutes: 20, awakenings: 4
        )
        XCTAssertEqual(q.timeInBedMinutes, 480, accuracy: 0.0001)
        XCTAssertEqual(q.awakeMinutes, 40, accuracy: 0.0001) // 20 + 4*5
        XCTAssertEqual(q.totalSleepMinutes, 440, accuracy: 0.0001)
    }

    func testSleepQuestionnaireToIngestPayloadIncludesOptionalFields() {
        let bedtime = Date(timeIntervalSince1970: 1_000)
        let wakeTime = Date(timeIntervalSince1970: 2_000)
        let q = SleepQuestionnaireAnswers(
            bedtime: bedtime, wakeTime: wakeTime,
            subjectiveQuality: 4, feltRested: .yes
        )
        let payload = q.toIngestPayload()
        XCTAssertEqual(payload["subjective_quality"] as? Int, 4)
        XCTAssertEqual(payload["felt_rested"] as? String, "yes")
        let self_ = payload["self_report_data"] as? [String: Any]
        XCTAssertEqual(self_?["session_start_ms"] as? Int64, 1_000_000)
        XCTAssertEqual(self_?["session_end_ms"] as? Int64, 2_000_000)
    }

    // MARK: - RecoveryScore

    func testOvernightPhysiologyHasSignal() {
        XCTAssertTrue(OvernightPhysiology(hrvRmssdMs: 42.5).hasSignal)
        XCTAssertTrue(OvernightPhysiology(overnightHrBpm: 58).hasSignal)
        XCTAssertFalse(OvernightPhysiology(hrvSdnnMs: 50, hrStdBpm: 5).hasSignal)
    }

    func testRecoveryScoreResultParsesExplanationFactorsSkipsUnknowns() throws {
        let s = """
        {
          "score": 65,
          "stage": "short_history",
          "mode": "trended",
          "confidence": 0.8,
          "explanation": ["hrv_above_baseline", "garbage_factor", "strong_sleep_quality"]
        }
        """
        let r = try RecoveryScoreResult.fromJsonString(s)
        XCTAssertEqual(r.score, 65)
        XCTAssertEqual(r.stage, .shortHistory)
        XCTAssertEqual(r.mode, .trended)
        XCTAssertEqual(r.explanation, [.hrvAboveBaseline, .strongSleepQuality])
    }

    // MARK: - ReadinessScore

    func testReadinessBandReadsTheEngineNamesAndFallsBackToTheScore() {
        XCTAssertEqual(ReadinessBand.fromWire("low", score: 90), .rest)
        XCTAssertEqual(ReadinessBand.fromWire("reduced", score: 0), .light)
        XCTAssertEqual(ReadinessBand.fromWire("high", score: 0), .push)
        // Unknown or missing: the band the score falls in, never a default.
        XCTAssertEqual(ReadinessBand.fromWire("garbage", score: 39), .rest)
        XCTAssertEqual(ReadinessBand.fromWire(nil, score: 40), .light)
        XCTAssertEqual(ReadinessBand.fromWire(nil, score: 79), .normal)
        XCTAssertEqual(ReadinessBand.fromWire(nil, score: 80), .push)
        XCTAssertEqual(ReadinessBand.light.label, "Light")
        XCTAssertEqual(ReadinessBand.push.wire, "high")
    }

    func testReadinessScoreInputEncodesTheEngineShape() {
        let json = ReadinessScoreInput(recoveryScore: 72, sleepScore: 68).toJson()
        XCTAssertEqual(Set(json.keys), [
            "recovery_score", "sleep_score", "alignment",
            "recovery_cold_start", "sleep_cold_start", "baseline_maturity",
        ])
        XCTAssertEqual(json["recovery_score"] as? Int, 72)
        XCTAssertEqual(json["sleep_score"] as? Int, 68)
        XCTAssertTrue(json["alignment"] is NSNull)
        XCTAssertEqual(json["recovery_cold_start"] as? Bool, false)
        XCTAssertEqual(json["baseline_maturity"] as? Double, 0)
    }

    func testReadinessScoreInputClampsScoresAndMaturity() {
        let json = ReadinessScoreInput(
            recoveryScore: 140, sleepScore: -5,
            alignment: OvernightAlignment(hrSleepBpm: 58, hrBaseBpm: 55, rmssdSleepMs: 42, rmssdBaseMs: 45),
            baselineMaturity: 1.7
        ).toJson()
        XCTAssertEqual(json["recovery_score"] as? Int, 100)
        XCTAssertEqual(json["sleep_score"] as? Int, 0)
        XCTAssertEqual(json["baseline_maturity"] as? Double, 1)
        let alignment = json["alignment"] as? [String: Any]
        XCTAssertEqual(alignment?["hr_sleep_bpm"] as? Double, 58)
        XCTAssertEqual(alignment?["rmssd_base_ms"] as? Double, 45)
        XCTAssertEqual(
            ReadinessScoreInput(recoveryScore: 50, sleepScore: 50, baselineMaturity: .nan)
                .toJson()["baseline_maturity"] as? Double,
            0
        )
    }

    func testReadinessScoreResultRoundTrips() throws {
        let s = """
        {
          "score": 74, "band": "normal", "recovery_anchor": 72, "sleep_anchor": 68,
          "confidence": 0.85,
          "components": {"recovery": 72.0, "sleep": 68.0, "baseline_alignment": 82.67,
                         "hr_alignment": 85.0, "hrv_alignment": null},
          "explanation": ["strong_recovery", "hrv_below_baseline", "not_a_factor"],
          "model_id": "readiness",
          "model_version": "3.0.0",
          "pipeline_version": "readiness_score/3.0.0"
        }
        """
        let r = try ReadinessScoreResult.fromJsonString(s)
        XCTAssertEqual(r.score, 74)
        XCTAssertEqual(r.band, .normal)
        XCTAssertEqual(r.recoveryAnchor, 72)
        XCTAssertEqual(r.sleepAnchor, 68)
        XCTAssertEqual(r.components.sleep, 68, accuracy: 0.0001)
        XCTAssertEqual(r.components.baselineAlignment ?? 0, 82.67, accuracy: 0.0001)
        XCTAssertNil(r.components.hrvAlignment)
        XCTAssertEqual(r.explanation, [.strongRecovery, .hrvBelowBaseline])
        XCTAssertEqual(r.modelVersion, "3.0.0")

        let again = ReadinessScoreResult.fromJson(r.toJson())
        XCTAssertEqual(again.band, r.band)
        XCTAssertEqual(again.sleepAnchor, 68)
        XCTAssertEqual(again.components, r.components)
        XCTAssertEqual(again.explanation, r.explanation)
        XCTAssertEqual(again.pipelineVersion, "readiness_score/3.0.0")
    }

    func testReadinessScoreResultWithoutABandTakesTheScoresBand() {
        let r = ReadinessScoreResult.fromJson(["score": 35])
        XCTAssertEqual(r.band, .rest)
    }
}
