// SPDX-License-Identifier: Apache-2.0
//
// Typed Swift models for the RFC-RECOVERY-SCORE-0001 daily scorer.
// Mirrors the JSON shapes produced by the Synheart Runtime's
// `RecoveryScore` computation. snake_case wire keys for cross-language
// portability.
//
// Three-stage scoring per RFC §"Adaptation Logic":
//   - Stage 1 (FirstDay):     1 night of sleep + (HR or HRV)
//   - Stage 2 (ShortHistory): ≥ 3 nights with HR/HRV trends
//   - Stage 3 (Personalized): ≥ 7 nights + stable wearable baselines

import Foundation

/// Which staged-history mode the engine used to compute the score.
public enum RecoveryStage: String, Sendable {
    case firstDay = "first_day"
    case shortHistory = "short_history"
    case personalized

    public static func fromWire(_ s: String?) -> RecoveryStage {
        guard let s = s, let v = RecoveryStage(rawValue: s) else { return .firstDay }
        return v
    }
}

/// User-facing label for the score's confidence regime.
public enum RecoveryScoreMode: String, Sendable {
    case estimate, trended, personalized

    public static func fromWire(_ s: String?) -> RecoveryScoreMode {
        guard let s = s, let v = RecoveryScoreMode(rawValue: s) else { return .estimate }
        return v
    }
}

/// Discrete reasons surfaced for "why is your recovery score X?" panels.
public enum RecoveryFactor: String, Sendable, CaseIterable {
    case hrvAboveBaseline = "hrv_above_baseline"
    case hrvBelowBaseline = "hrv_below_baseline"
    case restingHrElevated = "resting_hr_elevated"
    case strongSleepQuality = "strong_sleep_quality"
    case fragmentedSleep = "fragmented_sleep"
    case inconsistentSchedule = "inconsistent_schedule"
    case highStrainYesterday = "high_strain_yesterday"
    case earlyEstimate = "early_estimate"
    case shortHistoryTrend = "short_history_trend"
    case personalizedBaseline = "personalized_baseline"

    public static func fromWire(_ s: String) -> RecoveryFactor? {
        return RecoveryFactor(rawValue: s)
    }
}

/// Aggregate sleep totals for one night. Stage durations are optional
/// (self-report / basic Health Connect can't break stages out).
public struct NightSummary: Sendable {
    public let wakeCalendarDate: Int
    public let totalSleepMinutes: Double
    public let deepSleepMinutes: Double?
    public let remSleepMinutes: Double?
    public let wasoMinutes: Double?
    public let awakeningCount: Int?
    public let sleepEfficiency: Double?
    public let bedtimeMidpointHours: Double?

    public init(wakeCalendarDate: Int, totalSleepMinutes: Double,
                deepSleepMinutes: Double? = nil, remSleepMinutes: Double? = nil,
                wasoMinutes: Double? = nil, awakeningCount: Int? = nil,
                sleepEfficiency: Double? = nil, bedtimeMidpointHours: Double? = nil) {
        self.wakeCalendarDate = wakeCalendarDate
        self.totalSleepMinutes = totalSleepMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.wasoMinutes = wasoMinutes
        self.awakeningCount = awakeningCount
        self.sleepEfficiency = sleepEfficiency
        self.bedtimeMidpointHours = bedtimeMidpointHours
    }

    public func toJson() -> [String: Any] {
        return [
            "wake_calendar_date": wakeCalendarDate,
            "total_sleep_minutes": totalSleepMinutes,
            "deep_sleep_minutes": deepSleepMinutes as Any? ?? NSNull(),
            "rem_sleep_minutes": remSleepMinutes as Any? ?? NSNull(),
            "waso_minutes": wasoMinutes as Any? ?? NSNull(),
            "awakening_count": awakeningCount as Any? ?? NSNull(),
            "sleep_efficiency": sleepEfficiency as Any? ?? NSNull(),
            "bedtime_midpoint_hours": bedtimeMidpointHours as Any? ?? NSNull(),
        ]
    }
}

/// Per-night overnight physiology (HR + HRV). At least one of the two
/// must be present for the engine to emit a score.
public struct OvernightPhysiology: Sendable {
    public let hrvRmssdMs: Double?
    public let hrvSdnnMs: Double?
    public let hrStdBpm: Double?
    public let stepsCount: Double?
    public let overnightHrBpm: Double?
    public let respiratoryRateBrpm: Double?
    public let spo2Pct: Double?

    public init(hrvRmssdMs: Double? = nil, hrvSdnnMs: Double? = nil,
                hrStdBpm: Double? = nil, stepsCount: Double? = nil,
                overnightHrBpm: Double? = nil, respiratoryRateBrpm: Double? = nil,
                spo2Pct: Double? = nil) {
        self.hrvRmssdMs = hrvRmssdMs
        self.hrvSdnnMs = hrvSdnnMs
        self.hrStdBpm = hrStdBpm
        self.stepsCount = stepsCount
        self.overnightHrBpm = overnightHrBpm
        self.respiratoryRateBrpm = respiratoryRateBrpm
        self.spo2Pct = spo2Pct
    }

    /// `true` if at least one of HR or HRV is reported. SDNN, hr-std,
    /// and steps are *not* consulted: the Recovery formula keys off
    /// RMSSD; the others only warm baseline dimensions and shouldn't
    /// spuriously trigger Recovery on a night that lacks the signals
    /// it actually needs.
    public var hasSignal: Bool {
        return hrvRmssdMs != nil || overnightHrBpm != nil
    }

    public func toJson() -> [String: Any] {
        return [
            "hrv_rmssd_ms": hrvRmssdMs as Any? ?? NSNull(),
            "hrv_sdnn_ms": hrvSdnnMs as Any? ?? NSNull(),
            "hr_std_bpm": hrStdBpm as Any? ?? NSNull(),
            "steps_count": stepsCount as Any? ?? NSNull(),
            "overnight_hr_bpm": overnightHrBpm as Any? ?? NSNull(),
            "respiratory_rate_brpm": respiratoryRateBrpm as Any? ?? NSNull(),
            "spo2_pct": spo2Pct as Any? ?? NSNull(),
        ]
    }
}

/// Stage-3 personal baselines pulled from the longitudinal SRM. Pass
/// `nil` (on `RecoveryScoreInput.baselines`) if the user doesn't have
/// stable references yet — the engine will dispatch to Stage 1 or 2.
public struct BaselineRefs: Sendable, Equatable {
    public let hrvRmssdMs: Double
    public let hrvConfidence: Double
    public let restingHrBpm: Double
    public let rhrConfidence: Double

    public init(hrvRmssdMs: Double, hrvConfidence: Double,
                restingHrBpm: Double, rhrConfidence: Double) {
        self.hrvRmssdMs = hrvRmssdMs; self.hrvConfidence = hrvConfidence
        self.restingHrBpm = restingHrBpm; self.rhrConfidence = rhrConfidence
    }

    public func toJson() -> [String: Any] {
        return [
            "hrv_rmssd_ms": hrvRmssdMs,
            "hrv_confidence": hrvConfidence,
            "resting_hr_bpm": restingHrBpm,
            "rhr_confidence": rhrConfidence,
        ]
    }
}

/// Strain context for Stage 3's strain-adjustment component. Any
/// signal may be `nil`; the engine uses whichever is present in
/// priority order.
public struct StrainContext: Sendable {
    public let previousDayStrain: Double?
    public let workoutMinutes: Int?
    public let stepCount: Int?
    public let activeMinutes: Int?
    public let sleepDebtHours: Double?

    public init(previousDayStrain: Double? = nil, workoutMinutes: Int? = nil,
                stepCount: Int? = nil, activeMinutes: Int? = nil,
                sleepDebtHours: Double? = nil) {
        self.previousDayStrain = previousDayStrain
        self.workoutMinutes = workoutMinutes
        self.stepCount = stepCount
        self.activeMinutes = activeMinutes
        self.sleepDebtHours = sleepDebtHours
    }

    public func toJson() -> [String: Any] {
        return [
            "previous_day_strain": previousDayStrain as Any? ?? NSNull(),
            "workout_minutes": workoutMinutes as Any? ?? NSNull(),
            "step_count": stepCount as Any? ?? NSNull(),
            "active_minutes": activeMinutes as Any? ?? NSNull(),
            "sleep_debt_hours": sleepDebtHours as Any? ?? NSNull(),
        ]
    }
}

/// Top-level input bundle for the Recovery Score scorer.
public struct RecoveryScoreInput: Sendable {
    public let tonight: NightSummary
    public let priors: [NightSummary]
    public let overnight: OvernightPhysiology
    public let priorsOvernight: [OvernightPhysiology]
    public let baselines: BaselineRefs?
    public let strain: StrainContext?

    public init(tonight: NightSummary, priors: [NightSummary] = [],
                overnight: OvernightPhysiology,
                priorsOvernight: [OvernightPhysiology] = [],
                baselines: BaselineRefs? = nil, strain: StrainContext? = nil) {
        self.tonight = tonight
        self.priors = priors
        self.overnight = overnight
        self.priorsOvernight = priorsOvernight
        self.baselines = baselines
        self.strain = strain
    }

    public func toJson() -> [String: Any] {
        return [
            "tonight": tonight.toJson(),
            "priors": priors.map { $0.toJson() },
            "overnight": overnight.toJson(),
            "priors_overnight": priorsOvernight.map { $0.toJson() },
            "baselines": baselines?.toJson() as Any? ?? NSNull(),
            "strain": strain?.toJson() as Any? ?? NSNull(),
        ]
    }

    public func toJsonString() -> String {
        let data = try! JSONSerialization.data(withJSONObject: toJson(), options: [])
        return String(data: data, encoding: .utf8)!
    }
}

/// Per-component breakdown — populated per-stage. Components missing
/// for the active stage are `nil`.
public struct RecoveryComponents: Sendable, Equatable {
    public let sleepQuality: Double?
    public let continuity: Double?
    public let consistency: Double?
    public let overnightHrLevel: Double?
    public let hrvLevel: Double?
    public let hrvTrend: Double?
    public let hrTrend: Double?
    public let hrvDeviation: Double?
    public let rhrDeviation: Double?
    public let strainAdjustment: Double?

    public init(sleepQuality: Double? = nil, continuity: Double? = nil,
                consistency: Double? = nil, overnightHrLevel: Double? = nil,
                hrvLevel: Double? = nil, hrvTrend: Double? = nil,
                hrTrend: Double? = nil, hrvDeviation: Double? = nil,
                rhrDeviation: Double? = nil, strainAdjustment: Double? = nil) {
        self.sleepQuality = sleepQuality
        self.continuity = continuity; self.consistency = consistency
        self.overnightHrLevel = overnightHrLevel; self.hrvLevel = hrvLevel
        self.hrvTrend = hrvTrend; self.hrTrend = hrTrend
        self.hrvDeviation = hrvDeviation; self.rhrDeviation = rhrDeviation
        self.strainAdjustment = strainAdjustment
    }

    public static func fromJson(_ json: [String: Any]) -> RecoveryComponents {
        return RecoveryComponents(
            sleepQuality: optDouble(json, "sleep_quality"),
            continuity: optDouble(json, "continuity"),
            consistency: optDouble(json, "consistency"),
            overnightHrLevel: optDouble(json, "overnight_hr_level"),
            hrvLevel: optDouble(json, "hrv_level"),
            hrvTrend: optDouble(json, "hrv_trend"),
            hrTrend: optDouble(json, "hr_trend"),
            hrvDeviation: optDouble(json, "hrv_deviation"),
            rhrDeviation: optDouble(json, "rhr_deviation"),
            strainAdjustment: optDouble(json, "strain_adjustment")
        )
    }
}

/// Canonical output of the Recovery Score scorer.
public struct RecoveryScoreResult: Sendable {
    public let score: Int
    public let stage: RecoveryStage
    public let mode: RecoveryScoreMode
    public let components: RecoveryComponents
    public let confidence: Double
    public let explanation: [RecoveryFactor]
    public let modelId: String
    public let modelVersion: String
    public let pipelineVersion: String

    public init(score: Int, stage: RecoveryStage, mode: RecoveryScoreMode,
                components: RecoveryComponents, confidence: Double,
                explanation: [RecoveryFactor] = [], modelId: String,
                modelVersion: String, pipelineVersion: String) {
        self.score = score; self.stage = stage; self.mode = mode
        self.components = components; self.confidence = confidence
        self.explanation = explanation; self.modelId = modelId
        self.modelVersion = modelVersion; self.pipelineVersion = pipelineVersion
    }

    public static func fromJson(_ json: [String: Any]) -> RecoveryScoreResult {
        let rawExpl = json["explanation"] as? [Any] ?? []
        let factors: [RecoveryFactor] = rawExpl.compactMap { e in
            guard let s = e as? String else { return nil }
            return RecoveryFactor(rawValue: s)
        }
        return RecoveryScoreResult(
            score: optInt(json, "score") ?? 0,
            stage: RecoveryStage.fromWire(json["stage"] as? String),
            mode: RecoveryScoreMode.fromWire(json["mode"] as? String),
            components: RecoveryComponents.fromJson(json["components"] as? [String: Any] ?? [:]),
            confidence: optDouble(json, "confidence") ?? 0,
            explanation: factors,
            modelId: json["model_id"] as? String ?? "",
            modelVersion: json["model_version"] as? String ?? "",
            pipelineVersion: json["pipeline_version"] as? String ?? ""
        )
    }

    public static func fromJsonString(_ s: String) throws -> RecoveryScoreResult {
        let data = s.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        return fromJson(obj as? [String: Any] ?? [:])
    }
}
