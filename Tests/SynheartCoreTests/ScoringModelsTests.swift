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

    func testReadinessBandFromWireFallsBackToRest() {
        XCTAssertEqual(ReadinessBand.fromWire("push"), .push)
        XCTAssertEqual(ReadinessBand.fromWire("garbage"), .rest)
        XCTAssertEqual(ReadinessBand.light.label, "Light")
    }

    func testReadinessScoreInputFromRecoveryBuildsMinimalInput() {
        let input = ReadinessScoreInput.fromRecovery(72)
        let json = input.toJson()
        XCTAssertEqual(json["recovery_score"] as? Int, 72)
        XCTAssertTrue(json["acute_workload"] is NSNull)
        XCTAssertTrue(json["fatigue"] is NSNull)
    }

    func testReadinessScoreResultRoundTrips() throws {
        let s = """
        {
          "score": 78, "band": "normal", "recovery_anchor": 70,
          "confidence": 0.85,
          "components": {"recovery": 70.0, "acute_load": 1.0, "fatigue": -3.0},
          "explanation": ["acute_load_optimal"],
          "model_id": "readiness_v1",
          "model_version": "1.0.0",
          "pipeline_version": "p1"
        }
        """
        let r = try ReadinessScoreResult.fromJsonString(s)
        XCTAssertEqual(r.score, 78)
        XCTAssertEqual(r.band, .normal)
        XCTAssertEqual(r.recoveryAnchor, 70)
        XCTAssertEqual(r.confidence, 0.85, accuracy: 0.0001)
        XCTAssertEqual(r.components.recovery, 70, accuracy: 0.0001)
        XCTAssertEqual(r.components.acuteLoad, 1.0)
        XCTAssertNil(r.components.history)
        XCTAssertEqual(r.explanation, [.acuteLoadOptimal])
        XCTAssertEqual(r.modelId, "readiness_v1")
    }
}
