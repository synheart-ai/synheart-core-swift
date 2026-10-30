// SPDX-License-Identifier: Apache-2.0
//
// Typed Swift models for the daily readiness scorer. Mirrors the JSON
// shapes of the Synheart Runtime's `ReadinessScore` computation
// (`readiness_score/3.0.0`). snake_case wire keys for cross-language
// portability.
//
// Readiness is the decision layer that runs after Sleep and Recovery for the
// day, and answers:
//
//     "How much demand can the user take today?"
//
// It blends Recovery (0.50), Sleep (0.25) and how far overnight HR / HRV sit
// from the person's baseline (0.25). Without overnight physiology the
// alignment weight moves onto Recovery and Sleep and confidence drops.

import Foundation

/// Discrete readiness band. The Swift names are the action each band
/// recommends; ``wire`` is the engine's name for the band.
public enum ReadinessBand: String, Sendable, CaseIterable {
    /// 0–39, "Low Readiness": rest, reduce difficulty, avoid high strain.
    case rest = "low"
    /// 40–59, "Reduced Readiness": light activity, lower load, more breaks.
    case light = "reduced"
    /// 60–79, "Normal Readiness": standard task / training schedule.
    case normal = "normal"
    /// 80–100, "High Readiness": may tolerate higher demand.
    case push = "high"

    /// The engine's name for the band.
    public var wire: String { rawValue }

    /// The band for `s`, or the band `score` falls in when `s` is missing or
    /// unknown — the engine derives the band from the score with the same
    /// breakpoints, so this never invents one.
    public static func fromWire(_ s: String?, score: Int) -> ReadinessBand {
        if let s, let v = ReadinessBand(rawValue: s) { return v }
        return fromScore(score)
    }

    /// The band a `0...100` score falls in (breakpoints 40 / 60 / 80).
    public static func fromScore(_ score: Int) -> ReadinessBand {
        if score < 40 { return .rest }
        if score < 60 { return .light }
        if score < 80 { return .normal }
        return .push
    }

    public var label: String {
        switch self {
        case .rest: return "Rest"
        case .light: return "Light"
        case .normal: return "Normal"
        case .push: return "Push"
        }
    }

    /// The engine's one-line recommendation for the band.
    public var recommendation: String {
        switch self {
        case .rest: return "Rest, reduce difficulty, avoid high strain"
        case .light: return "Light activity, lower cognitive load, more breaks"
        case .normal: return "Standard task / training schedule"
        case .push: return "You may tolerate higher demand"
        }
    }
}

/// Discrete reasons surfaced for "why is your readiness X?" panels.
public enum ReadinessFactor: String, Sendable, CaseIterable {
    case strongRecovery = "strong_recovery"
    case lowRecovery = "low_recovery"
    case poorSleep = "poor_sleep"
    case goodSleep = "good_sleep"
    case hrvAboveBaseline = "hrv_above_baseline"
    case hrvBelowBaseline = "hrv_below_baseline"
    case restingHrElevated = "resting_hr_elevated"
    /// The HR/HRV baseline is immature or absent.
    case baselineImmature = "baseline_immature"
    case recoveryColdStart = "recovery_cold_start"
    case sleepColdStart = "sleep_cold_start"
    /// No overnight HR/HRV: readiness is a Recovery + Sleep blend.
    case scoresOnly = "scores_only"
}

/// Overnight physiology against the person's baselines, for the
/// baseline-alignment term. All four values are required; pass no
/// `OvernightAlignment` at all when any is unavailable.
public struct OvernightAlignment: Sendable, Equatable {
    /// Mean HR during sleep (bpm).
    public let hrSleepBpm: Double
    /// Personal rolling resting HR baseline (bpm).
    public let hrBaseBpm: Double
    /// Mean RMSSD during sleep (ms).
    public let rmssdSleepMs: Double
    /// Personal rolling resting RMSSD baseline (ms).
    public let rmssdBaseMs: Double

    public init(hrSleepBpm: Double, hrBaseBpm: Double,
                rmssdSleepMs: Double, rmssdBaseMs: Double) {
        self.hrSleepBpm = hrSleepBpm; self.hrBaseBpm = hrBaseBpm
        self.rmssdSleepMs = rmssdSleepMs; self.rmssdBaseMs = rmssdBaseMs
    }

    public func toJson() -> [String: Any] {
        return [
            "hr_sleep_bpm": hrSleepBpm,
            "hr_base_bpm": hrBaseBpm,
            "rmssd_sleep_ms": rmssdSleepMs,
            "rmssd_base_ms": rmssdBaseMs,
        ]
    }
}

/// Top-level input bundle. Recovery and Sleep are both required: readiness
/// runs after both are known for the day.
public struct ReadinessScoreInput: Sendable {
    /// Today's Recovery Score, `0...100`.
    public let recoveryScore: Int
    /// Today's Sleep Score, `0...100`.
    public let sleepScore: Int
    /// Overnight HR/HRV against baselines, or `nil` when either is missing.
    public let alignment: OvernightAlignment?
    /// Today's Recovery Score is a cold-start estimate (Recovery stage 1).
    public let recoveryColdStart: Bool
    /// Today's Sleep Score is a cold-start estimate (Sleep mode 1).
    public let sleepColdStart: Bool
    /// Maturity of the overnight HR/HRV baselines, `0...1`: the lower of the
    /// two confidences in ``Synheart/dailyBaselineRefs()`` (see
    /// ``BaselineRefs/maturity``), or `0` when it returns `nil`. At or below
    /// `0.30` the baseline counts as immature.
    public let baselineMaturity: Double

    public init(recoveryScore: Int, sleepScore: Int,
                alignment: OvernightAlignment? = nil,
                recoveryColdStart: Bool = false, sleepColdStart: Bool = false,
                baselineMaturity: Double = 0) {
        self.recoveryScore = recoveryScore
        self.sleepScore = sleepScore
        self.alignment = alignment
        self.recoveryColdStart = recoveryColdStart
        self.sleepColdStart = sleepColdStart
        self.baselineMaturity = baselineMaturity
    }

    public func toJson() -> [String: Any] {
        return [
            "recovery_score": min(max(recoveryScore, 0), 100),
            "sleep_score": min(max(sleepScore, 0), 100),
            "alignment": alignment?.toJson() as Any? ?? NSNull(),
            "recovery_cold_start": recoveryColdStart,
            "sleep_cold_start": sleepColdStart,
            "baseline_maturity": baselineMaturity.isFinite
                ? min(max(baselineMaturity, 0), 1) : 0.0,
        ]
    }

    public func toJsonString() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: toJson(), options: []),
              let s = String(data: data, encoding: .utf8) else {
            SynheartLogger.log("[ReadinessScore] toJsonString: serialization failed; returning empty object")
            return "{}"
        }
        return s
    }
}

/// Per-component breakdown, every value on `0...100`. The alignment values
/// are `nil` when overnight HR/HRV or a baseline was unavailable, so "not
/// measured" never reads as a mid-range score.
public struct ReadinessComponents: Sendable, Equatable {
    public let recovery: Double
    public let sleep: Double
    public let baselineAlignment: Double?
    public let hrAlignment: Double?
    public let hrvAlignment: Double?

    public init(recovery: Double, sleep: Double, baselineAlignment: Double? = nil,
                hrAlignment: Double? = nil, hrvAlignment: Double? = nil) {
        self.recovery = recovery
        self.sleep = sleep
        self.baselineAlignment = baselineAlignment
        self.hrAlignment = hrAlignment
        self.hrvAlignment = hrvAlignment
    }

    public static func fromJson(_ json: [String: Any]) -> ReadinessComponents {
        return ReadinessComponents(
            recovery: optDouble(json, "recovery") ?? 0,
            sleep: optDouble(json, "sleep") ?? 0,
            baselineAlignment: optDouble(json, "baseline_alignment"),
            hrAlignment: optDouble(json, "hr_alignment"),
            hrvAlignment: optDouble(json, "hrv_alignment")
        )
    }

    public func toJson() -> [String: Any] {
        return [
            "recovery": recovery,
            "sleep": sleep,
            "baseline_alignment": baselineAlignment as Any? ?? NSNull(),
            "hr_alignment": hrAlignment as Any? ?? NSNull(),
            "hrv_alignment": hrvAlignment as Any? ?? NSNull(),
        ]
    }
}

/// Canonical output of the Readiness Score scorer.
public struct ReadinessScoreResult: Sendable {
    public let score: Int
    public let band: ReadinessBand
    /// The Recovery Score the result was computed from.
    public let recoveryAnchor: Int
    /// The Sleep Score the result was computed from.
    public let sleepAnchor: Int
    public let components: ReadinessComponents
    public let confidence: Double
    public let explanation: [ReadinessFactor]
    public let modelId: String
    public let modelVersion: String
    public let pipelineVersion: String

    public init(score: Int, band: ReadinessBand, recoveryAnchor: Int, sleepAnchor: Int,
                components: ReadinessComponents, confidence: Double,
                explanation: [ReadinessFactor] = [], modelId: String,
                modelVersion: String, pipelineVersion: String) {
        self.score = score; self.band = band
        self.recoveryAnchor = recoveryAnchor; self.sleepAnchor = sleepAnchor
        self.components = components; self.confidence = confidence
        self.explanation = explanation; self.modelId = modelId
        self.modelVersion = modelVersion; self.pipelineVersion = pipelineVersion
    }

    public static func fromJson(_ json: [String: Any]) -> ReadinessScoreResult {
        let rawExpl = json["explanation"] as? [Any] ?? []
        let factors: [ReadinessFactor] = rawExpl.compactMap { e in
            guard let s = e as? String else { return nil }
            return ReadinessFactor(rawValue: s)
        }
        let score = optInt(json, "score") ?? 0
        return ReadinessScoreResult(
            score: score,
            band: ReadinessBand.fromWire(json["band"] as? String, score: score),
            recoveryAnchor: optInt(json, "recovery_anchor") ?? 0,
            sleepAnchor: optInt(json, "sleep_anchor") ?? 0,
            components: ReadinessComponents.fromJson(json["components"] as? [String: Any] ?? [:]),
            confidence: optDouble(json, "confidence") ?? 0,
            explanation: factors,
            modelId: json["model_id"] as? String ?? "",
            modelVersion: json["model_version"] as? String ?? "",
            pipelineVersion: json["pipeline_version"] as? String ?? ""
        )
    }

    public static func fromJsonString(_ s: String) throws -> ReadinessScoreResult {
        let data = s.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        return fromJson(obj as? [String: Any] ?? [:])
    }

    /// The engine's JSON shape, for persisting a result and reading it back
    /// with ``fromJson(_:)``.
    public func toJson() -> [String: Any] {
        return [
            "score": score,
            "band": band.wire,
            "recovery_anchor": recoveryAnchor,
            "sleep_anchor": sleepAnchor,
            "components": components.toJson(),
            "confidence": confidence,
            "explanation": explanation.map { $0.rawValue },
            "model_id": modelId,
            "model_version": modelVersion,
            "pipeline_version": pipelineVersion,
        ]
    }
}
