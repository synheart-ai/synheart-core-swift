// SPDX-License-Identifier: Apache-2.0
//
// HealthKit historical-read backfill.
//
// Architecture:
//
//   wear (synheart-wear-swift)              core (this file)
//   ──────────────────────────              ──────────────────
//   HealthKitHistoryReader
//     .fetchSleepNights()         ─────►  HealthKitRuntimeSink
//     .fetchOvernightPhysiology()           .backfill()
//                                             ↓
//                                        aggregate per local wake-day
//                                             ↓
//                                        CoreRuntimeBridge
//                                          .srmPushWearableDaily(...)
//
// Core stays HealthKit-agnostic. All HealthKit SDK calls, authorization
// gating, and availability checks live in wear. Core only knows: given
// these typed daily summaries, push five daily metrics per night
// (sleep.duration_s, sleep.deep_min, sleep.rem_min,
// cardiac.overnight_rmssd_ms, cardiac.resting_hr_bpm) into the runtime's
// personal baselines under the local wake date.
//
// Apple HealthKit retention is effectively user-owned — the OS preserves
// data as long as the user keeps it, so years of history are routinely
// available. Caller decides `daysBack`; the wear reader returns whatever
// the user has authorised.

import Foundation
import SynheartWear

/// Outcome of a HealthKit historical pull. `dimensionsPushed` counts the
/// values the runtime stored.
public struct HealthKitBackfillResult: Equatable, Sendable {
    public let requestedDaysBack: Int
    public let daysIngested: Int
    public let dimensionsPushed: Int
    public let skipped: Bool
    public let skipReason: String?
    public let durationMs: Int64

    public init(
        requestedDaysBack: Int,
        daysIngested: Int,
        dimensionsPushed: Int,
        skipped: Bool,
        skipReason: String?,
        durationMs: Int64
    ) {
        self.requestedDaysBack = requestedDaysBack
        self.daysIngested = daysIngested
        self.dimensionsPushed = dimensionsPushed
        self.skipped = skipped
        self.skipReason = skipReason
        self.durationMs = durationMs
    }
}

/// Push-daily callback — the shape of `srm_push_wearable_daily`: one value of
/// one ``DailyMetric`` for one local date. Returns the runtime's code (`0`
/// stored, `1004` refused, `5002` out of bounds or not permitted, `-1` no
/// pipeline). Injectable so tests can substitute a recorder without booting
/// the native runtime.
public typealias PushDailyCallback = @Sendable (
    _ provider: String,
    _ metric: String,
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ value: Double,
    _ vendorSummary: Bool
) -> Int32

/// Rebuild the wearable reference once the backfill has stored its values.
public typealias TriggerRecomputeCallback = @Sendable () -> Void

/// High-level "bring your Apple Health history" call. Pulls
/// sleep + overnight HR/HRV from `reader` across `daysBack` days,
/// aggregates per local wake-day, and pushes each value into the runtime's
/// personal baselines under the provider `apple_health`, then rebuilds the
/// wearable reference as of today.
///
/// HealthKit's nightly figures are platform summaries, so every value is
/// pushed as a vendor summary.
///
/// ```swift
/// let sink = HealthKitRuntimeSink(reader: HealthKitHistoryReader(), bridge: bridge)
/// let result = try await sink.backfill(daysBack: 365)
/// ```
public final class HealthKitRuntimeSink: @unchecked Sendable {

    private let reader: HealthHistoryReader
    private let pushDaily: PushDailyCallback
    private let triggerRecompute: TriggerRecomputeCallback
    private let timeZone: TimeZone

    public init(
        reader: HealthHistoryReader,
        pushDaily: @escaping PushDailyCallback,
        triggerRecompute: @escaping TriggerRecomputeCallback,
        timeZone: TimeZone = .current
    ) {
        self.reader = reader
        self.pushDaily = pushDaily
        self.triggerRecompute = triggerRecompute
        self.timeZone = timeZone
    }

    /// A sink that pushes into `bridge` with `srm_push_wearable_daily` and
    /// refreshes the wearable reference as of today.
    public convenience init(
        reader: HealthHistoryReader,
        bridge: CoreRuntimeBridge?,
        timeZone: TimeZone = .current
    ) {
        self.init(
            reader: reader,
            pushDaily: Self.defaultPushDaily(bridge: bridge),
            triggerRecompute: Self.defaultTriggerRecompute(bridge: bridge, timeZone: timeZone),
            timeZone: timeZone
        )
    }

    /// The provider name every HealthKit value is stored under.
    public static let provider = "apple_health"

    /// Default push: `srm_push_wearable_daily` on `bridge`; `-1` without one.
    public static func defaultPushDaily(bridge: CoreRuntimeBridge?) -> PushDailyCallback {
        { provider, metric, year, month, day, value, vendorSummary in
            bridge?.srmPushWearableDaily(
                provider: provider, metric: metric,
                year: year, month: month, day: day,
                value: value, vendorSummary: vendorSummary
            ) ?? -1
        }
    }

    /// Default trigger: rebuild the wearable reference as of today. The
    /// runtime builds it from the dates before the one given, so every
    /// backfilled night is in and no day is in its own baseline.
    public static func defaultTriggerRecompute(
        bridge: CoreRuntimeBridge?, timeZone: TimeZone = .current
    ) -> TriggerRecomputeCallback {
        {
            let today = Synheart.localDate(Date(), timeZone)
            bridge?.srmRefreshWearableReference(year: today.year, month: today.month, day: today.day)
        }
    }

    public func backfill(daysBack: Int = 365) async throws -> HealthKitBackfillResult {
        let startedAt = Self.nowMs()

        if daysBack <= 0 {
            return skipResult(daysBack: daysBack,
                              reason: "daysBack must be positive",
                              startedAt: startedAt)
        }

        let available = await reader.isAvailable()
        if !available {
            return skipResult(daysBack: daysBack,
                              reason: "HealthKit not available on this device",
                              startedAt: startedAt)
        }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let end = Date()
        let startOfToday = cal.startOfDay(for: end)
        guard let start = cal.date(byAdding: .day, value: -daysBack, to: startOfToday) else {
            return skipResult(daysBack: daysBack,
                              reason: "Could not compute backfill window",
                              startedAt: startedAt)
        }

        async let sleepFetch = reader.fetchSleepNights(start: start, end: end, timeZone: timeZone)
        async let overnightFetch = reader.fetchOvernightPhysiology(start: start, end: end, timeZone: timeZone)
        let sleep = try await sleepFetch
        let overnight = try await overnightFetch

        let allDays = Set(sleep.keys).union(overnight.keys).sorted()

        var dimensionsPushed = 0
        var daysIngested = 0
        for day in allDays {
            // The reader keys each night by the start of its local wake day;
            // read that date in the same zone. (A UTC day index of that
            // instant would file every night a day early east of UTC.)
            let date = Self.localDate(of: day, timeZone: timeZone)
            var dayDidPush = false

            func push(_ metric: String, _ value: Double) -> Bool {
                let rc = pushDaily(Self.provider, metric, date.year, date.month, date.day, value, true)
                if rc != 0 {
                    SynheartLogger.log(
                        "[HealthKitRuntimeSink] \(metric) on \(date.year)-\(date.month)-\(date.day) not stored (rc=\(rc))"
                    )
                    return false
                }
                dimensionsPushed += 1
                return true
            }

            if let night = sleep[day], night.totalAsleepMinutes > 0 {
                if push(DailyMetric.sleepDurationS, night.totalAsleepMinutes * 60.0) {
                    dayDidPush = true
                }

                // Stage pushes are nested under totalAsleep > 0. A night with
                // stages but zero asleep minutes is treated as no usable sleep
                // data.
                if let deep = night.deepMinutes, deep > 0 {
                    _ = push(DailyMetric.sleepDeepMin, deep)
                }
                if let rem = night.remMinutes, rem > 0 {
                    _ = push(DailyMetric.sleepRemMin, rem)
                }
            }

            if let o = overnight[day] {
                if let hrv = o.hrvRmssdMs, hrv > 0, push(DailyMetric.overnightRmssdMs, hrv) {
                    dayDidPush = true
                }
                if let hr = o.restingHrBpm, hr > 0, push(DailyMetric.restingHrBpm, hr) {
                    dayDidPush = true
                }
            }

            if dayDidPush { daysIngested += 1 }
        }

        if dimensionsPushed > 0 {
            triggerRecompute()
        }

        return HealthKitBackfillResult(
            requestedDaysBack: daysBack,
            daysIngested: daysIngested,
            dimensionsPushed: dimensionsPushed,
            skipped: false,
            skipReason: nil,
            durationMs: Self.nowMs() - startedAt
        )
    }

    // ────────────────────────────────────────────────────────────── //
    // Helpers                                                         //
    // ────────────────────────────────────────────────────────────── //

    private func skipResult(daysBack: Int, reason: String, startedAt: Int64) -> HealthKitBackfillResult {
        return HealthKitBackfillResult(
            requestedDaysBack: daysBack,
            daysIngested: 0,
            dimensionsPushed: 0,
            skipped: true,
            skipReason: reason,
            durationMs: Self.nowMs() - startedAt
        )
    }

    private static func nowMs() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    /// The calendar date of `date` in `timeZone`.
    static func localDate(of date: Date, timeZone: TimeZone) -> (year: Int, month: Int, day: Int) {
        Synheart.localDate(date, timeZone)
    }
}
