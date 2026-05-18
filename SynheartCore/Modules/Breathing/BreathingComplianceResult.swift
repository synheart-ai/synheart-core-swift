// SPDX-License-Identifier: Apache-2.0
//
// Result of evaluating breathing compliance over the current RR window.
// Mirrors the breathing runtime's `ComplianceResult` JSON shape and
// the Flutter / Kotlin references. See RFC-Breathing-001 for verdict
// semantics.

import Foundation

/// Numeric metrics computed by the 4-pillar detector.
public struct BreathingMetrics: Sendable, Equatable {
    /// Detected breathing peak frequency in Hz.
    public let peakHz: Double
    /// Detected breathing rate in breaths/minute (= peakHz * 60).
    public let peakBpm: Double
    /// Coherence score (peak power / power in 0.04–0.26 Hz band), 0..1.
    public let coherence: Double
    /// RSA amplitude (mean per-cycle HR_max − HR_min), in BPM.
    public let rsaBpm: Double
    /// Peak power as a fraction of total breathing-band power, 0..1.
    public let relativePower: Double
    /// Number of compliance pillars met (0..4).
    public let criteriaMet: Int
    /// Mean of normalized pillar scores, 0..1.
    public let confidence: Double

    public init(peakHz: Double, peakBpm: Double, coherence: Double, rsaBpm: Double,
                relativePower: Double, criteriaMet: Int, confidence: Double) {
        self.peakHz = peakHz; self.peakBpm = peakBpm
        self.coherence = coherence; self.rsaBpm = rsaBpm
        self.relativePower = relativePower
        self.criteriaMet = criteriaMet; self.confidence = confidence
    }

    public static func fromJson(_ json: [String: Any]) -> BreathingMetrics {
        return BreathingMetrics(
            peakHz: optDouble(json, "peak_hz") ?? 0,
            peakBpm: optDouble(json, "peak_bpm") ?? 0,
            coherence: optDouble(json, "coherence") ?? 0,
            rsaBpm: optDouble(json, "rsa_bpm") ?? 0,
            relativePower: optDouble(json, "relative_power") ?? 0,
            criteriaMet: optInt(json, "criteria_met") ?? 0,
            confidence: optDouble(json, "confidence") ?? 0
        )
    }
}

/// Why the user is not following instructions (when verdict is NotCompliant).
public enum NonComplianceReason: Sendable, Equatable {
    case wrongFrequency(detectedBpm: Double, targetBpm: Double)
    case shallowBreathing(rsaBpm: Double)
    case irregularPattern(coherence: Double)
    case noBreathingSignature

    public static func fromJson(_ json: [String: Any]) -> NonComplianceReason {
        switch json["type"] as? String {
        case "WrongFrequency":
            return .wrongFrequency(
                detectedBpm: optDouble(json, "detected_bpm") ?? 0,
                targetBpm: optDouble(json, "target_bpm") ?? 0
            )
        case "ShallowBreathing":
            return .shallowBreathing(rsaBpm: optDouble(json, "rsa_bpm") ?? 0)
        case "IrregularPattern":
            return .irregularPattern(coherence: optDouble(json, "coherence") ?? 0)
        default:
            return .noBreathingSignature
        }
    }
}

/// Why the detector cannot produce a verdict yet.
public enum InsufficientReason: Sendable, Equatable {
    case notEnoughBeats(have: Int, need: Int)
    case windowTooShort(haveSecs: Int, needSecs: Int)
    case vendorOnlyTier(device: String)
    case excessiveArtifacts(rejectedPct: Double)

    public static func fromJson(_ json: [String: Any]) -> InsufficientReason {
        switch json["type"] as? String {
        case "NotEnoughBeats":
            return .notEnoughBeats(
                have: optInt(json, "have") ?? 0,
                need: optInt(json, "need") ?? 50
            )
        case "WindowTooShort":
            return .windowTooShort(
                haveSecs: optInt(json, "have_secs") ?? 0,
                needSecs: optInt(json, "need_secs") ?? 0
            )
        case "VendorOnlyTier":
            return .vendorOnlyTier(device: json["device"] as? String ?? "")
        case "ExcessiveArtifacts":
            return .excessiveArtifacts(rejectedPct: optDouble(json, "rejected_pct") ?? 0)
        default:
            return .notEnoughBeats(have: 0, need: 50)
        }
    }
}

/// Top-level breathing compliance verdict.
public enum BreathingComplianceResult: Sendable {
    case compliant(metrics: BreathingMetrics)
    case notCompliant(metrics: BreathingMetrics, reason: NonComplianceReason)
    case insufficient(reason: InsufficientReason)

    /// Returns the metrics if available (nil for `.insufficient`).
    public var metrics: BreathingMetrics? {
        switch self {
        case let .compliant(m): return m
        case let .notCompliant(m, _): return m
        case .insufficient: return nil
        }
    }

    /// True iff the user is meeting the compliance threshold.
    public var isCompliant: Bool {
        if case .compliant = self { return true }
        return false
    }

    public static func fromJson(_ json: [String: Any]) -> BreathingComplianceResult {
        switch json["verdict"] as? String {
        case "Compliant":
            return .compliant(
                metrics: BreathingMetrics.fromJson(json["metrics"] as? [String: Any] ?? [:])
            )
        case "NotCompliant":
            return .notCompliant(
                metrics: BreathingMetrics.fromJson(json["metrics"] as? [String: Any] ?? [:]),
                reason: NonComplianceReason.fromJson(json["reason"] as? [String: Any] ?? [:])
            )
        default:
            return .insufficient(
                reason: InsufficientReason.fromJson(json["reason"] as? [String: Any] ?? [:])
            )
        }
    }

    public static func fromJsonString(_ s: String) throws -> BreathingComplianceResult {
        let data = s.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data)
        return fromJson(obj as? [String: Any] ?? [:])
    }
}

/// Population threshold profiles. Match the native runtime's enum ordering.
public enum BreathingPopulation: Int, Sendable {
    case beginner = 0
    case experienced = 1
    case clinical = 2
}
