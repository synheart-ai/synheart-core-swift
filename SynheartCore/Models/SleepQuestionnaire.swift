// SPDX-License-Identifier: Apache-2.0
//
// Self-reported sleep questionnaire — Phase-2 input lane for the
// RFC-SLEEP-SCORE-PIPELINE-0001 scorer. Converts a small set of
// subjective answers into the same `aggregated` shape vendor payloads
// produce, so the engine can score without special-casing.

import Foundation

/// "Did you wake up feeling rested?"
public enum SleepFeltRested: String, Sendable {
    case no, somewhat, yes
}

/// One night of self-reported sleep. All fields are optional except
/// `bedtime` and `wakeTime` — without them we can't bound TIB.
public struct SleepQuestionnaireAnswers: Sendable {
    public let bedtime: Date
    public let wakeTime: Date
    public let sleepLatencyMinutes: Int
    public let awakenings: Int
    public let subjectiveQuality: Int?
    public let feltRested: SleepFeltRested?

    public init(bedtime: Date, wakeTime: Date, sleepLatencyMinutes: Int = 15,
                awakenings: Int = 0, subjectiveQuality: Int? = nil,
                feltRested: SleepFeltRested? = nil) {
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.sleepLatencyMinutes = sleepLatencyMinutes
        self.awakenings = awakenings
        self.subjectiveQuality = subjectiveQuality
        self.feltRested = feltRested
    }

    /// Time-in-bed in minutes (wake − bedtime, never negative).
    public var timeInBedMinutes: Double {
        let diff = wakeTime.timeIntervalSince(bedtime) / 60.0
        return diff < 0 ? 0 : diff
    }

    /// Heuristic awake minutes: latency + 5 min per awakening. A
    /// reasonable lower-bound — users typically remember fewer
    /// awakenings than actually occurred, but we'd rather under-count
    /// than fabricate.
    public var awakeMinutes: Double {
        return Double(sleepLatencyMinutes + awakenings * 5)
    }

    /// Estimated total asleep minutes.
    public var totalSleepMinutes: Double {
        let asleep = timeInBedMinutes - awakeMinutes
        return asleep < 0 ? 0 : asleep
    }

    /// Wire-shape payload for the SDK's `Baselines.ingestVendorSleep`
    /// call. Engine treats `kind: aggregated` with nil deep/rem as the
    /// honest "we know totals, not stages" path.
    public func toIngestPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "timestamp": Self.iso8601Formatter.string(from: wakeTime),
            "self_report_data": [
                "time_in_bed_minutes": timeInBedMinutes,
                "total_sleep_minutes": totalSleepMinutes,
                "awake_minutes": awakeMinutes,
                "awakenings": awakenings,
                "session_start_ms": Int64(bedtime.timeIntervalSince1970 * 1000),
                "session_end_ms": Int64(wakeTime.timeIntervalSince1970 * 1000),
            ],
        ]
        if let q = subjectiveQuality { payload["subjective_quality"] = q }
        if let r = feltRested { payload["felt_rested"] = r.rawValue }
        return payload
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
