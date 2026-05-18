// SPDX-License-Identifier: Apache-2.0
//
// Typed Swift models for the RFC-SLEEP-SCORE-PIPELINE-0001 batch
// scorer. Mirrors the JSON shapes produced by the Synheart Runtime's
// `SleepScore` computation. snake_case wire keys for cross-language
// portability — Flutter (`lib/src/models/sleep_score.dart`) and
// Kotlin emit the same JSON.

import Foundation

/// Canonical sleep stage.
public enum SleepStage: String, Sendable {
    case awake, light, deep, rem, unknown

    public static func fromWire(_ s: String?) -> SleepStage {
        // `Self` avoids name collision with SynheartWear.SleepStage
        // (Apple-Health-XML's stage enum has different cases).
        guard let s = s, let v = Self(rawValue: s) else { return .unknown }
        return v
    }
}

/// Which pipeline path produced a score.
public enum SleepPath: String, Sendable {
    case stage
    case aggregated
    case vendorScore = "vendor_score"
    case proxy

    public static func fromWire(_ s: String?) -> SleepPath {
        guard let s = s, let v = SleepPath(rawValue: s) else { return .proxy }
        return v
    }
}

/// Mode derived from history length (0 → cold, 1–6 → short, ≥ 7 → stable).
public enum SleepScoreMode: String, Sendable {
    case coldStart = "cold_start"
    case shortHistory = "short_history"
    case stable

    public static func fromWire(_ s: String?) -> SleepScoreMode {
        guard let s = s, let v = SleepScoreMode(rawValue: s) else { return .coldStart }
        return v
    }
}

/// Reason a score was absent or degraded.
public enum SleepScoreReason: String, Sendable {
    case noSleepData = "no_sleep_data"
    case insufficientData = "insufficient_data"
    case proxyFallback = "proxy_fallback"
    case vendorPassthrough = "vendor_passthrough"

    public static func fromWire(_ s: String?) -> SleepScoreReason? {
        guard let s = s else { return nil }
        return SleepScoreReason(rawValue: s)
    }
}

/// A contiguous stage interval. Half-open: `[startMs, endMs)`.
public struct StageSegment: Sendable, Equatable {
    public let stage: SleepStage
    public let startMs: Int64
    public let endMs: Int64

    public init(stage: SleepStage, startMs: Int64, endMs: Int64) {
        self.stage = stage; self.startMs = startMs; self.endMs = endMs
    }

    public func toJson() -> [String: Any] {
        return [
            "stage": stage.rawValue,
            "start_ms": startMs,
            "end_ms": endMs,
        ]
    }
}

/// Aggregate per-night totals for vendors that don't expose a timeline.
///
/// Stage durations (`deepSleepMinutes`, `remSleepMinutes`) are
/// optional: pass `nil` when the source genuinely cannot distinguish
/// stages. The engine then scores on duration + continuity only
/// instead of treating zero deep/REM as "absurdly poor stage profile"
/// and tanking the result.
public struct AggregatedTotals: Sendable, Equatable {
    public let totalSleepMinutes: Double
    public let deepSleepMinutes: Double?
    public let remSleepMinutes: Double?
    public let awakeMinutes: Double
    public let awakenings: Int?
    public let timeInBedMinutes: Double?

    public init(totalSleepMinutes: Double, deepSleepMinutes: Double? = nil,
                remSleepMinutes: Double? = nil, awakeMinutes: Double,
                awakenings: Int? = nil, timeInBedMinutes: Double? = nil) {
        self.totalSleepMinutes = totalSleepMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.awakeMinutes = awakeMinutes
        self.awakenings = awakenings
        self.timeInBedMinutes = timeInBedMinutes
    }

    public func toJson() -> [String: Any] {
        var out: [String: Any] = [
            "total_sleep_minutes": totalSleepMinutes,
            "awake_minutes": awakeMinutes,
            "awakenings": awakenings as Any? ?? NSNull(),
            "time_in_bed_minutes": timeInBedMinutes as Any? ?? NSNull(),
        ]
        if let d = deepSleepMinutes { out["deep_sleep_minutes"] = d }
        if let r = remSleepMinutes { out["rem_sleep_minutes"] = r }
        return out
    }
}

/// The three vendor-input shapes. The runtime's `NightInput` is a
/// tagged enum (`kind: segmented | aggregated | vendor_score`).
public enum NightInput: Sendable {
    case segmented(sessionStartMs: Int64, sessionEndMs: Int64, zoneId: String, segments: [StageSegment])
    case aggregated(sessionStartMs: Int64?, sessionEndMs: Int64?, totals: AggregatedTotals)
    case vendorScore(score: Int)

    public func toJson() -> [String: Any] {
        switch self {
        case let .segmented(start, end, zone, segments):
            return [
                "kind": "segmented",
                "session_start_ms": start,
                "session_end_ms": end,
                "zone_id": zone,
                "segments": segments.map { $0.toJson() },
            ]
        case let .aggregated(start, end, totals):
            return [
                "kind": "aggregated",
                "session_start_ms": start as Any? ?? NSNull(),
                "session_end_ms": end as Any? ?? NSNull(),
                "totals": totals.toJson(),
            ]
        case let .vendorScore(score):
            return ["kind": "vendor_score", "score": score]
        }
    }
}

/// One night's raw input + optional session-window HR.
public struct NightRaw: Sendable {
    public let wakeCalendarDate: Int
    public let detail: NightInput
    public let avgHrBpm: Double?

    public init(wakeCalendarDate: Int, detail: NightInput, avgHrBpm: Double? = nil) {
        self.wakeCalendarDate = wakeCalendarDate
        self.detail = detail
        self.avgHrBpm = avgHrBpm
    }

    public func toJson() -> [String: Any] {
        return [
            "wake_calendar_date": wakeCalendarDate,
            "detail": detail.toJson(),
            "avg_hr_bpm": avgHrBpm as Any? ?? NSNull(),
        ]
    }
}

/// Full input to the scorer.
public struct SleepScoreInput: Sendable {
    public let tonight: NightRaw
    public let priorsNewestFirst: [NightRaw]
    public let pipelineVersion: String

    public init(tonight: NightRaw, priorsNewestFirst: [NightRaw] = [], pipelineVersion: String = "") {
        self.tonight = tonight
        self.priorsNewestFirst = priorsNewestFirst
        self.pipelineVersion = pipelineVersion
    }

    public func toJson() -> [String: Any] {
        return [
            "tonight": tonight.toJson(),
            "priors_newest_first": priorsNewestFirst.map { $0.toJson() },
            "pipeline_version": pipelineVersion,
        ]
    }

    public func toJsonString() -> String {
        let data = try! JSONSerialization.data(withJSONObject: toJson(), options: [])
        return String(data: data, encoding: .utf8)!
    }
}

/// Per-component breakdown; fields populated per-path.
public struct SleepScoreBreakdown: Sendable, Equatable {
    public let duration: Int?
    public let quality: Int?
    public let continuity: Int?
    public let consistency: Int?
    public let personalization: Int?
    public let vendorScore: Int?
    public let proxyHr: Int?

    public init(duration: Int? = nil, quality: Int? = nil, continuity: Int? = nil,
                consistency: Int? = nil, personalization: Int? = nil,
                vendorScore: Int? = nil, proxyHr: Int? = nil) {
        self.duration = duration; self.quality = quality
        self.continuity = continuity; self.consistency = consistency
        self.personalization = personalization; self.vendorScore = vendorScore
        self.proxyHr = proxyHr
    }

    public static func fromJson(_ json: [String: Any]) -> SleepScoreBreakdown {
        return SleepScoreBreakdown(
            duration: optInt(json, "duration"),
            quality: optInt(json, "quality"),
            continuity: optInt(json, "continuity"),
            consistency: optInt(json, "consistency"),
            personalization: optInt(json, "personalization"),
            vendorScore: optInt(json, "vendor_score"),
            proxyHr: optInt(json, "proxy_hr")
        )
    }
}

public struct SleepScoreAdjust: Sendable, Equatable {
    public let debtPenalty: Int
    public let hrAdjustment: Int

    public init(debtPenalty: Int, hrAdjustment: Int) {
        self.debtPenalty = debtPenalty; self.hrAdjustment = hrAdjustment
    }

    public static func fromJson(_ json: [String: Any]) -> SleepScoreAdjust {
        return SleepScoreAdjust(
            debtPenalty: optInt(json, "debt_penalty") ?? 0,
            hrAdjustment: optInt(json, "hr_adjustment") ?? 0
        )
    }
}

public struct ComponentWeights: Sendable, Equatable {
    public let duration: Double
    public let quality: Double
    public let continuity: Double
    public let consistency: Double
    public let personalization: Double

    public init(duration: Double = 0, quality: Double = 0, continuity: Double = 0,
                consistency: Double = 0, personalization: Double = 0) {
        self.duration = duration; self.quality = quality
        self.continuity = continuity; self.consistency = consistency
        self.personalization = personalization
    }

    public static func fromJson(_ json: [String: Any]) -> ComponentWeights {
        return ComponentWeights(
            duration: optDouble(json, "duration") ?? 0,
            quality: optDouble(json, "quality") ?? 0,
            continuity: optDouble(json, "continuity") ?? 0,
            consistency: optDouble(json, "consistency") ?? 0,
            personalization: optDouble(json, "personalization") ?? 0
        )
    }
}

/// The canonical output of the batch scorer.
public struct SleepScoreResult: Sendable {
    public let score: Int?
    public let scoreNormalized: Double?
    public let confidence: Double
    public let path: SleepPath
    public let mode: SleepScoreMode
    public let components: SleepScoreBreakdown
    public let adjustments: SleepScoreAdjust
    public let effectiveWeights: ComponentWeights
    public let reason: SleepScoreReason?
    public let priorNightCount: Int
    public let pipelineVersion: String
    public let modelId: String
    public let constantsHash: String

    public init(score: Int? = nil, scoreNormalized: Double? = nil, confidence: Double,
                path: SleepPath, mode: SleepScoreMode, components: SleepScoreBreakdown,
                adjustments: SleepScoreAdjust, effectiveWeights: ComponentWeights,
                reason: SleepScoreReason? = nil, priorNightCount: Int,
                pipelineVersion: String, modelId: String, constantsHash: String) {
        self.score = score; self.scoreNormalized = scoreNormalized
        self.confidence = confidence; self.path = path; self.mode = mode
        self.components = components; self.adjustments = adjustments
        self.effectiveWeights = effectiveWeights; self.reason = reason
        self.priorNightCount = priorNightCount
        self.pipelineVersion = pipelineVersion
        self.modelId = modelId; self.constantsHash = constantsHash
    }

    public static func fromJson(_ json: [String: Any]) -> SleepScoreResult {
        return SleepScoreResult(
            score: optInt(json, "score"),
            scoreNormalized: optDouble(json, "score_normalized"),
            confidence: optDouble(json, "confidence") ?? 0,
            path: SleepPath.fromWire(json["path"] as? String),
            mode: SleepScoreMode.fromWire(json["mode"] as? String),
            components: SleepScoreBreakdown.fromJson(json["components"] as? [String: Any] ?? [:]),
            adjustments: SleepScoreAdjust.fromJson(json["adjustments"] as? [String: Any] ?? [:]),
            effectiveWeights: ComponentWeights.fromJson(json["effective_weights"] as? [String: Any] ?? [:]),
            reason: SleepScoreReason.fromWire(json["reason"] as? String),
            priorNightCount: optInt(json, "prior_night_count") ?? 0,
            pipelineVersion: json["pipeline_version"] as? String ?? "",
            modelId: json["model_id"] as? String ?? "",
            constantsHash: json["constants_hash"] as? String ?? ""
        )
    }

    public static func fromJsonString(_ s: String) throws -> SleepScoreResult {
        let data = s.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        return fromJson(obj as? [String: Any] ?? [:])
    }
}

/// Wearable reference view over the Longitudinal SRM engine output.
///
/// Surfaces the high-signal fields typed (status, Path-B median) and
/// keeps the raw maps accessible for UI that wants to walk every
/// dimension.
public struct WearableReferenceView: Sendable {
    public let status: String
    public let modelVersion: String?
    public let recentSleepScoreMedian: Int?
    /// Per-dimension numeric values (e.g. `hrv_rmssd_ms`).
    public let dimensions: [String: Double]
    /// Per-dimension confidence ∈ [0, 1].
    public let confidence: [String: Double]

    public init(status: String, modelVersion: String? = nil,
                recentSleepScoreMedian: Int? = nil,
                dimensions: [String: Double] = [:],
                confidence: [String: Double] = [:]) {
        self.status = status; self.modelVersion = modelVersion
        self.recentSleepScoreMedian = recentSleepScoreMedian
        self.dimensions = dimensions; self.confidence = confidence
    }

    public static func fromJson(_ json: [String: Any]) -> WearableReferenceView {
        let dimsRaw = json["dimensions"] as? [String: Any] ?? [:]
        let confRaw = json["confidence"] as? [String: Any] ?? [:]

        var dims: [String: Double] = [:]
        for (k, v) in dimsRaw {
            if let n = v as? NSNumber { dims[k] = n.doubleValue }
        }
        var conf: [String: Double] = [:]
        for (k, v) in confRaw {
            if let n = v as? NSNumber { conf[k] = n.doubleValue }
        }

        return WearableReferenceView(
            status: json["status"] as? String ?? "Empty",
            modelVersion: json["model_version"] as? String,
            recentSleepScoreMedian: optInt(dimsRaw, "recent_sleep_score_median"),
            dimensions: dims,
            confidence: conf
        )
    }

    public static func fromJsonString(_ s: String) throws -> WearableReferenceView {
        let data = s.data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        return fromJson(obj as? [String: Any] ?? [:])
    }
}

// MARK: - JSON helpers

/// `optInt` / `optDouble` — return nil when the value is absent or NSNull
/// (so callers can distinguish "not present" from "zero").
internal func optInt(_ json: [String: Any], _ key: String) -> Int? {
    guard let v = json[key], !(v is NSNull) else { return nil }
    return (v as? NSNumber)?.intValue
}

internal func optDouble(_ json: [String: Any], _ key: String) -> Double? {
    guard let v = json[key], !(v is NSNull) else { return nil }
    return (v as? NSNumber)?.doubleValue
}
