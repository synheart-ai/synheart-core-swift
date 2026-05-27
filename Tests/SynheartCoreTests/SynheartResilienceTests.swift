// SPDX-License-Identifier: Apache-2.0
//
// Tests for the in-memory / unavailable paths of `SynheartResilience`.
// The native FFI path is exercised by the runtime's own Rust tests.

import XCTest
@testable import SynheartCore

final class SynheartResilienceTests: XCTestCase {

    // MARK: - Type round-trips

    func testHrvSampleJsonShape() {
        let s = HrvSample(tsMs: 100, rmssdMs: 42.5)
        let j = s.jsonObject
        XCTAssertEqual(j["ts_ms"] as? Int64, 100)
        XCTAssertEqual(j["rmssd_ms"] as? Double, 42.5)
    }

    func testSleepWindowJsonShape() {
        let w = SleepWindow(startMs: 1_000, endMs: 2_000)
        let j = w.jsonObject
        XCTAssertEqual(j["start_ms"] as? Int64, 1_000)
        XCTAssertEqual(j["end_ms"] as? Int64, 2_000)
    }

    func testResilienceConfigDefaults() {
        let c = ResilienceConfig()
        XCTAssertEqual(c.lookbackDays, 7)
        XCTAssertEqual(c.minDaysRequired, 5)
        XCTAssertEqual(c.minRrSamples, 20)
        XCTAssertEqual(c.cvCeilingPct, 7.0)
        XCTAssertEqual(c.cvFloorPct, 40.0)
    }

    func testResilienceConfigJsonShape() {
        let c = ResilienceConfig()
        let j = c.jsonObject
        XCTAssertEqual(j["lookback_days"] as? Int, 7)
        XCTAssertEqual(j["min_days_required"] as? Int, 5)
        XCTAssertEqual(j["min_rr_samples"] as? Int, 20)
        XCTAssertEqual(j["cv_ceiling_pct"] as? Double, 7.0)
        XCTAssertEqual(j["cv_floor_pct"] as? Double, 40.0)
    }

    // MARK: - Reason mapping

    func testReasonMapping() {
        XCTAssertEqual(ResilienceReason.fromWire("InsufficientDays"), .insufficientDays)
        XCTAssertEqual(ResilienceReason.fromWire("NoSleepWindows"), .noSleepWindows)
        XCTAssertEqual(ResilienceReason.fromWire("InsufficientSamples"), .insufficientSamples)
        XCTAssertEqual(ResilienceReason.fromWire("NoValidSamples"), .noValidSamples)
        XCTAssertEqual(ResilienceReason.fromWire("ZeroMeanHrv"), .zeroMeanHrv)
    }

    func testReasonNullAndUnknownReturnNil() {
        XCTAssertNil(ResilienceReason.fromWire(nil))
        XCTAssertNil(ResilienceReason.fromWire("garbage"))
    }

    // MARK: - Result parsing

    func testResultFromJsonUnavailable() {
        let r = ResilienceResult.fromJson([
            "score": NSNull(),
            "days_used": 0,
            "samples_used": 0,
            "confidence": 0.0,
            "reason": "NoSleepWindows",
            "model_id": "resilience/1.0.0",
            "pipeline_version": "resilience/1.0.0",
            "constants_hash": String(repeating: "a", count: 64),
        ])
        XCTAssertNil(r.score)
        XCTAssertEqual(r.reason, .noSleepWindows)
        XCTAssertEqual(r.daysUsed, 0)
        XCTAssertEqual(r.modelId, "resilience/1.0.0")
        XCTAssertEqual(r.constantsHash.count, 64)
    }

    func testResultFromJsonSuccess() {
        let r = ResilienceResult.fromJson([
            "score": 100,
            "rmssd_ow_ms": 50.0,
            "sdnn_ow_ms": 50.0,
            "hrv_cv_pct": 0.0,
            "days_used": 7,
            "samples_used": 70,
            "confidence": 1.0,
            "model_id": "resilience/1.0.0",
            "pipeline_version": "resilience/1.0.0",
            "constants_hash": String(repeating: "b", count: 64),
        ])
        XCTAssertEqual(r.score, 100)
        XCTAssertNil(r.reason)
        XCTAssertEqual(r.daysUsed, 7)
        XCTAssertEqual(r.samplesUsed, 70)
        XCTAssertEqual(r.confidence, 1.0)
    }

    func testResultFromJsonToleratesMissingFields() {
        let r = ResilienceResult.fromJson([:])
        XCTAssertNil(r.score)
        XCTAssertNil(r.rmssdOwMs)
        XCTAssertEqual(r.modelId, "")
        XCTAssertEqual(r.daysUsed, 0)
    }

    // MARK: - Wrapper unavailable path

    func testIsAvailableFalseWhenForced() {
        let r = SynheartResilience(forceUnavailable: true)
        XCTAssertFalse(r.isAvailable)
    }

    func testComputeThrowsWhenUnavailable() {
        let r = SynheartResilience(forceUnavailable: true)
        XCTAssertThrowsError(try r.compute(samples: [], sleepWindows: [])) { err in
            XCTAssertEqual(err as? ResilienceError, .runtimeUnavailable)
        }
    }
}
