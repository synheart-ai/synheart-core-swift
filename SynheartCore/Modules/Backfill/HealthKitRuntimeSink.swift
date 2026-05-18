// SPDX-License-Identifier: Apache-2.0
//
// HealthKit historical-read backfill — Swift parallel to Flutter's
// `lib/src/backfill/health_connect_runtime_sink.dart` and the Kotlin
// `HealthConnectRuntimeSink` in synheart-core-kotlin.
//
// Architecture mirrors the cross-platform shape:
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
//                                          .pushWearableDailyValue(...)
//
// Core stays HealthKit-agnostic. All HealthKit SDK calls, authorization
// gating, and availability checks live in wear. Core only knows: given
// these typed daily summaries, push five dimensions per night
// (sleep_need, deep_sleep_min, rem_sleep_min, hrv_rmssd, resting_hr)
// to the runtime SRM.
//
// Apple HealthKit retention is effectively user-owned — the OS preserves
// data as long as the user keeps it, so years of history are routinely
// available. Caller decides `daysBack`; the wear reader returns whatever
// the user has authorised.

import Foundation
import SynheartWear

/// Outcome of a HealthKit historical pull. Mirrors Kotlin's
/// `HealthConnectBackfillResult` and Flutter's
/// `HealthConnectBackfillResult`.
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

/// Push-daily callback — matches the runtime's `pushWearableDailyValue`
/// shape. Injectable so tests can substitute a recorder without booting
/// the native runtime.
public typealias PushDailyCallback = @Sendable (
    _ dimension: String,
    _ dayIndex: Int,
    _ value: Double,
    _ confidence: Double,
    _ fidelity: Int32
) -> Void

public typealias TriggerRecomputeCallback = @Sendable () -> Void

/// High-level "bring your Apple Health history" call. Pulls
/// sleep + overnight HR/HRV from `reader` across `daysBack` days,
/// aggregates per local wake-day, and replays into the runtime SRM
/// via `CoreRuntimeBridge.pushWearableDailyValue(...)`.
///
/// Confidence (`0.85`) and fidelity (`1`) match the Apple Health XML
/// import path and the Android Health Connect path, so all three
/// produce comparable SRM weights.
///
/// ```swift
/// let sink = HealthKitRuntimeSink(
///     reader: HealthKitHistoryReader(),
///     pushDaily: { dim, day, value, conf, fid in
///         bridge.pushWearableDailyValue(
///             dimension: dim,
///             dayIndex: day,
///             value: value,
///             confidence: conf,
///             fidelity: fid
///         )
///     },
///     triggerRecompute: { bridge.triggerWearableRecompute(triggerType: 0, asOfDay: 0) }
/// )
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
            let dayIndex = Self.epochDay(for: day)
            var dayDidPush = false

            if let night = sleep[day], night.totalAsleepMinutes > 0 {
                pushDaily("sleep_need", dayIndex, night.totalAsleepMinutes * 60.0, 0.85, 1)
                dimensionsPushed += 1
                dayDidPush = true

                // Stage pushes are nested under totalAsleep > 0 (matches
                // Flutter / Kotlin). A night with stages but zero asleep
                // minutes is treated as no usable sleep data.
                if let deep = night.deepMinutes, deep > 0 {
                    pushDaily("deep_sleep_min", dayIndex, deep, 0.85, 1)
                    dimensionsPushed += 1
                }
                if let rem = night.remMinutes, rem > 0 {
                    pushDaily("rem_sleep_min", dayIndex, rem, 0.85, 1)
                    dimensionsPushed += 1
                }
            }

            if let o = overnight[day] {
                if let hrv = o.hrvRmssdMs, hrv > 0 {
                    pushDaily("hrv_rmssd", dayIndex, hrv, 0.85, 1)
                    dimensionsPushed += 1
                    dayDidPush = true
                }
                if let hr = o.restingHrBpm, hr > 0 {
                    pushDaily("resting_hr", dayIndex, hr, 0.85, 1)
                    dimensionsPushed += 1
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

    /// Unix-epoch day index. Mirrors `LocalDate.toEpochDay()` on Kotlin
    /// and `epochDayFor` in the Flutter SDK — always UTC-anchored so
    /// the index is stable across timezone changes.
    static func epochDay(for date: Date) -> Int {
        return Int(date.timeIntervalSince1970 / 86_400.0)
    }
}
