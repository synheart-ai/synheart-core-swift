// SPDX-License-Identifier: Apache-2.0
//
// Typed Swift models for the RFC-READINESS-SCORE-0001 daily scorer.
// Mirrors the JSON shapes produced by the Synheart Runtime's
// `ReadinessScore` computation. snake_case wire keys for cross-language
// portability.
//
// Readiness layers acute / fatigue / history context on top of today's
// Recovery Score to answer:
//
//     "How much strain should the user take today?"

import Foundation

/// Discrete action label derived from the score.
public enum ReadinessBand: String, Sendable {
    case rest, light, normal, push

    public static func fromWire(_ s: String?) -> ReadinessBand {
        guard let s = s, let v = ReadinessBand(rawValue: s) else { return .rest }
        return v
    }

    public var label: String {
        switch self {
        case .rest: return "Rest"
        case .light: return "Light"
        case .normal: return "Normal"
        case .push: return "Push"
        }
    }
}

/// Discrete reasons surfaced for "why is your readiness X?" panels.
public enum ReadinessFactor: String, Sendable, CaseIterable {
    case strongRecovery = "strong_recovery"
    case lowRecovery = "low_recovery"
    case acuteLoadHigh = "acute_load_high"
    case acuteLoadOptimal = "acute_load_optimal"
    case sleepDebt = "sleep_debt"
    case recoveryDeclining = "recovery_declining"
    case consecutiveOverload = "consecutive_overload"
    case noRecentRest = "no_recent_rest"
    case anchorOnly = "anchor_only"
}

/// Acute / chronic workload context. Hosts can either pre-compute
/// `acuteChronicRatio` or pass the raw loads.
public struct AcuteWorkloadContext: Sendable {
    public let acuteLoad: Double?
    public let chronicLoad: Double?
    public let acuteChronicRatio: Double?

    public init(acuteLoad: Double? = nil, chronicLoad: Double? = nil,
                acuteChronicRatio: Double? = nil) {
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.acuteChronicRatio = acuteChronicRatio
    }

    public func toJson() -> [String: Any] {
        return [
            "acute_load": acuteLoad as Any? ?? NSNull(),
            "chronic_load": chronicLoad as Any? ?? NSNull(),
            "acute_chronic_ratio": acuteChronicRatio as Any? ?? NSNull(),
        ]
    }
}

/// Short-window fatigue indicators.
public struct FatigueContext: Sendable {
    public let sleepDebtHours: Double?
    public let recoverySlopePerDay: Double?
    public let recovery7dMean: Double?

    public init(sleepDebtHours: Double? = nil, recoverySlopePerDay: Double? = nil,
                recovery7dMean: Double? = nil) {
        self.sleepDebtHours = sleepDebtHours
        self.recoverySlopePerDay = recoverySlopePerDay
        self.recovery7dMean = recovery7dMean
    }

    public func toJson() -> [String: Any] {
        return [
            "sleep_debt_hours": sleepDebtHours as Any? ?? NSNull(),
            "recovery_slope_per_day": recoverySlopePerDay as Any? ?? NSNull(),
            "recovery_7d_mean": recovery7dMean as Any? ?? NSNull(),
        ]
    }
}

/// Training-history context.
public struct HistoryContext: Sendable {
    public let consecutiveHighStrainDays: Int?
    public let daysSinceRest: Int?

    public init(consecutiveHighStrainDays: Int? = nil, daysSinceRest: Int? = nil) {
        self.consecutiveHighStrainDays = consecutiveHighStrainDays
        self.daysSinceRest = daysSinceRest
    }

    public func toJson() -> [String: Any] {
        return [
            "consecutive_high_strain_days": consecutiveHighStrainDays as Any? ?? NSNull(),
            "days_since_rest": daysSinceRest as Any? ?? NSNull(),
        ]
    }
}

/// Top-level input bundle. Recovery score is required; everything
/// else is optional and improves confidence when present.
public struct ReadinessScoreInput: Sendable {
    public let recoveryScore: Int
    public let recoveryConfidence: Double?
    public let acuteWorkload: AcuteWorkloadContext?
    public let fatigue: FatigueContext?
    public let history: HistoryContext?

    public init(recoveryScore: Int, recoveryConfidence: Double? = nil,
                acuteWorkload: AcuteWorkloadContext? = nil,
                fatigue: FatigueContext? = nil, history: HistoryContext? = nil) {
        self.recoveryScore = recoveryScore
        self.recoveryConfidence = recoveryConfidence
        self.acuteWorkload = acuteWorkload
        self.fatigue = fatigue
        self.history = history
    }

    /// Build an input from only the recovery score; downstream context
    /// stays empty. Useful while a host is still wiring fatigue / load.
    public static func fromRecovery(_ recoveryScore: Int) -> ReadinessScoreInput {
        return ReadinessScoreInput(recoveryScore: recoveryScore)
    }

    public func toJson() -> [String: Any] {
        return [
            "recovery_score": recoveryScore,
            "recovery_confidence": recoveryConfidence as Any? ?? NSNull(),
            "acute_workload": acuteWorkload?.toJson() as Any? ?? NSNull(),
            "fatigue": fatigue?.toJson() as Any? ?? NSNull(),
            "history": history?.toJson() as Any? ?? NSNull(),
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

/// Per-component breakdown.
public struct ReadinessComponents: Sendable, Equatable {
    public let recovery: Double
    public let acuteLoad: Double?
    public let fatigue: Double?
    public let history: Double?

    public init(recovery: Double, acuteLoad: Double? = nil,
                fatigue: Double? = nil, history: Double? = nil) {
        self.recovery = recovery
        self.acuteLoad = acuteLoad
        self.fatigue = fatigue
        self.history = history
    }

    public static func fromJson(_ json: [String: Any]) -> ReadinessComponents {
        return ReadinessComponents(
            recovery: optDouble(json, "recovery") ?? 0,
            acuteLoad: optDouble(json, "acute_load"),
            fatigue: optDouble(json, "fatigue"),
            history: optDouble(json, "history")
        )
    }
}

/// Canonical output of the Readiness Score scorer.
public struct ReadinessScoreResult: Sendable {
    public let score: Int
    public let band: ReadinessBand
    public let recoveryAnchor: Int
    public let components: ReadinessComponents
    public let confidence: Double
    public let explanation: [ReadinessFactor]
    public let modelId: String
    public let modelVersion: String
    public let pipelineVersion: String

    public init(score: Int, band: ReadinessBand, recoveryAnchor: Int,
                components: ReadinessComponents, confidence: Double,
                explanation: [ReadinessFactor] = [], modelId: String,
                modelVersion: String, pipelineVersion: String) {
        self.score = score; self.band = band; self.recoveryAnchor = recoveryAnchor
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
        return ReadinessScoreResult(
            score: optInt(json, "score") ?? 0,
            band: ReadinessBand.fromWire(json["band"] as? String),
            recoveryAnchor: optInt(json, "recovery_anchor") ?? 0,
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
}
