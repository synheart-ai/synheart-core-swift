// SPDX-License-Identifier: Apache-2.0

import XCTest
import Foundation
@testable import SynheartCore

final class BreathingComplianceResultTests: XCTestCase {

    // MARK: - BreathingMetrics

    func testMetricsDefaultsToZeroOnMissingFields() {
        let m = BreathingMetrics.fromJson([:])
        XCTAssertEqual(m.peakHz, 0, accuracy: 0.0001)
        XCTAssertEqual(m.criteriaMet, 0)
    }

    func testMetricsFromJsonReadsAllFields() {
        let json: [String: Any] = [
            "peak_hz": 0.1, "peak_bpm": 6.0, "coherence": 0.85,
            "rsa_bpm": 8.2, "relative_power": 0.6,
            "criteria_met": 3, "confidence": 0.78,
        ]
        let m = BreathingMetrics.fromJson(json)
        XCTAssertEqual(m.peakHz, 0.1, accuracy: 0.0001)
        XCTAssertEqual(m.peakBpm, 6.0, accuracy: 0.0001)
        XCTAssertEqual(m.coherence, 0.85, accuracy: 0.0001)
        XCTAssertEqual(m.rsaBpm, 8.2, accuracy: 0.0001)
        XCTAssertEqual(m.relativePower, 0.6, accuracy: 0.0001)
        XCTAssertEqual(m.criteriaMet, 3)
        XCTAssertEqual(m.confidence, 0.78, accuracy: 0.0001)
    }

    // MARK: - NonComplianceReason

    func testNonComplianceParsesAllFourVariants() {
        let freq = NonComplianceReason.fromJson([
            "type": "WrongFrequency", "detected_bpm": 9.0, "target_bpm": 6.0,
        ])
        if case let .wrongFrequency(detected, target) = freq {
            XCTAssertEqual(detected, 9.0); XCTAssertEqual(target, 6.0)
        } else { XCTFail("expected wrongFrequency") }

        let shallow = NonComplianceReason.fromJson(["type": "ShallowBreathing", "rsa_bpm": 2.1])
        if case let .shallowBreathing(rsa) = shallow {
            XCTAssertEqual(rsa, 2.1)
        } else { XCTFail("expected shallowBreathing") }

        let irreg = NonComplianceReason.fromJson(["type": "IrregularPattern", "coherence": 0.2])
        if case let .irregularPattern(c) = irreg {
            XCTAssertEqual(c, 0.2)
        } else { XCTFail("expected irregularPattern") }

        let none = NonComplianceReason.fromJson(["type": "NoBreathingSignature"])
        XCTAssertEqual(none, .noBreathingSignature)
    }

    func testNonComplianceFallsBackOnUnknownType() {
        let r = NonComplianceReason.fromJson(["type": "garbage"])
        XCTAssertEqual(r, .noBreathingSignature)
    }

    // MARK: - InsufficientReason

    func testInsufficientParsesAllFourVariants() {
        let nb = InsufficientReason.fromJson(["type": "NotEnoughBeats", "have": 12, "need": 50])
        XCTAssertEqual(nb, .notEnoughBeats(have: 12, need: 50))

        let ws = InsufficientReason.fromJson([
            "type": "WindowTooShort", "have_secs": 20, "need_secs": 30,
        ])
        XCTAssertEqual(ws, .windowTooShort(haveSecs: 20, needSecs: 30))

        let vot = InsufficientReason.fromJson(["type": "VendorOnlyTier", "device": "WHOOP 4.0"])
        XCTAssertEqual(vot, .vendorOnlyTier(device: "WHOOP 4.0"))

        let ea = InsufficientReason.fromJson(["type": "ExcessiveArtifacts", "rejected_pct": 42.5])
        XCTAssertEqual(ea, .excessiveArtifacts(rejectedPct: 42.5))
    }

    // MARK: - BreathingComplianceResult

    func testVerdictCompliantParsesMetricsAndIsCompliant() throws {
        let s = #"{"verdict":"Compliant","metrics":{"peak_bpm":6.0,"criteria_met":4,"confidence":0.9}}"#
        let r = try BreathingComplianceResult.fromJsonString(s)
        XCTAssertTrue(r.isCompliant)
        XCTAssertEqual(r.metrics?.peakBpm, 6.0)
        XCTAssertEqual(r.metrics?.criteriaMet, 4)
    }

    func testVerdictNotCompliantCarriesMetricsPlusReason() throws {
        let s = """
        {"verdict":"NotCompliant",
         "metrics":{"peak_bpm":9.0,"criteria_met":1,"confidence":0.4},
         "reason":{"type":"WrongFrequency","detected_bpm":9.0,"target_bpm":6.0}}
        """
        let r = try BreathingComplianceResult.fromJsonString(s)
        XCTAssertFalse(r.isCompliant)
        XCTAssertEqual(r.metrics?.peakBpm, 9.0)
        if case let .notCompliant(_, reason) = r,
           case let .wrongFrequency(detected, target) = reason {
            XCTAssertEqual(detected, 9.0)
            XCTAssertEqual(target, 6.0)
        } else { XCTFail("wrong shape") }
    }

    func testVerdictInsufficientHasNilMetricsAndCarriesReason() throws {
        let s = #"{"verdict":"Insufficient","reason":{"type":"NotEnoughBeats","have":10,"need":50}}"#
        let r = try BreathingComplianceResult.fromJsonString(s)
        XCTAssertNil(r.metrics)
        XCTAssertFalse(r.isCompliant)
        if case let .insufficient(reason) = r,
           case let .notEnoughBeats(have, _) = reason {
            XCTAssertEqual(have, 10)
        } else { XCTFail("wrong shape") }
    }

    func testUnknownVerdictFallsBackToInsufficient() throws {
        let s = #"{"verdict":"Mystery","reason":{"type":"NotEnoughBeats","have":0,"need":50}}"#
        let r = try BreathingComplianceResult.fromJsonString(s)
        if case .insufficient = r {} else { XCTFail("expected insufficient") }
    }

    // MARK: - BreathingGuidanceCopy

    func testWrongFrequencyCopySwitchesOnDirection() {
        let tooFast = NonComplianceReason.wrongFrequency(detectedBpm: 10.0, targetBpm: 6.0)
        let tooSlow = NonComplianceReason.wrongFrequency(detectedBpm: 4.0, targetBpm: 6.0)
        XCTAssertTrue(BreathingGuidanceCopy.copyFor(tooFast).contains("Slow down"))
        XCTAssertTrue(BreathingGuidanceCopy.copyFor(tooSlow).contains("Speed up"))
    }

    func testLocalizerOverrideIsGlobal() {
        let original = BreathingGuidanceCopy.localize
        defer { BreathingGuidanceCopy.localize = original }
        BreathingGuidanceCopy.localize = { _ in "X" }
        XCTAssertEqual(
            BreathingGuidanceCopy.copyFor(.irregularPattern(coherence: 0)),
            "X"
        )
    }

    // MARK: - BreathingPopulation

    func testBreathingPopulationRawValuesMatchNativeEnum() {
        XCTAssertEqual(BreathingPopulation.beginner.rawValue, 0)
        XCTAssertEqual(BreathingPopulation.experienced.rawValue, 1)
        XCTAssertEqual(BreathingPopulation.clinical.rawValue, 2)
    }
}
