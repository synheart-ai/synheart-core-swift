// SPDX-License-Identifier: Apache-2.0
//
// Smoke tests for HealthKitRuntimeSink. Pure-Swift — uses a fake
// HealthHistoryReader and records pushDaily / triggerRecompute calls,
// so no native runtime or HealthKit is required.

import XCTest
import SynheartWear
@testable import SynheartCore

final class HealthKitRuntimeSinkTests: XCTestCase {

    private let zone = TimeZone(identifier: "UTC")!

    // Fixture wake-day used by the "full data" cases: 2026-01-15 (UTC).
    private var day: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
    }

    // ────────────────────────────────────────────────────────────── //
    // Test doubles                                                    //
    // ────────────────────────────────────────────────────────────── //

    private struct PushCall: Equatable {
        let dimension: String
        let dayIndex: Int
        let value: Double
        let confidence: Double
        let fidelity: Int32
    }

    private final class Recorder: @unchecked Sendable {
        var pushes: [PushCall] = []
        var recomputeCount = 0
        private let lock = NSLock()

        var pushDaily: PushDailyCallback {
            { [weak self] dim, day, v, c, f in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                self.pushes.append(PushCall(dimension: dim, dayIndex: day, value: v, confidence: c, fidelity: f))
            }
        }
        var triggerRecompute: TriggerRecomputeCallback {
            { [weak self] in
                guard let self else { return }
                self.lock.lock(); defer { self.lock.unlock() }
                self.recomputeCount += 1
            }
        }
    }

    private final class FakeReader: HealthHistoryReader, @unchecked Sendable {
        private let available: Bool
        private let sleep: [Date: SleepNightSummary]
        private let overnight: [Date: OvernightPhysiologySummary]

        init(available: Bool = true,
             sleep: [Date: SleepNightSummary] = [:],
             overnight: [Date: OvernightPhysiologySummary] = [:]) {
            self.available = available
            self.sleep = sleep
            self.overnight = overnight
        }

        func isAvailable() async -> Bool { available }
        func fetchSleepNights(start: Date, end: Date, timeZone: TimeZone) async throws -> [Date: SleepNightSummary] { sleep }
        func fetchOvernightPhysiology(start: Date, end: Date, timeZone: TimeZone) async throws -> [Date: OvernightPhysiologySummary] { overnight }
    }

    private func makeSink(reader: HealthHistoryReader, recorder: Recorder = Recorder()) -> (HealthKitRuntimeSink, Recorder) {
        let s = HealthKitRuntimeSink(
            reader: reader,
            pushDaily: recorder.pushDaily,
            triggerRecompute: recorder.triggerRecompute,
            timeZone: zone
        )
        return (s, recorder)
    }

    // ────────────────────────────────────────────────────────────── //
    // Skip paths                                                      //
    // ────────────────────────────────────────────────────────────── //

    func testNonPositiveDaysBackShortCircuits() async throws {
        let (sink, recorder) = makeSink(reader: FakeReader())
        let result = try await sink.backfill(daysBack: 0)
        XCTAssertTrue(result.skipped)
        XCTAssertEqual(result.skipReason, "daysBack must be positive")
        XCTAssertEqual(result.dimensionsPushed, 0)
        XCTAssertEqual(result.daysIngested, 0)
        XCTAssertTrue(recorder.pushes.isEmpty)
        XCTAssertEqual(recorder.recomputeCount, 0)
    }

    func testReaderUnavailableShortCircuits() async throws {
        let (sink, recorder) = makeSink(reader: FakeReader(available: false))
        let result = try await sink.backfill(daysBack: 7)
        XCTAssertTrue(result.skipped)
        XCTAssertNotNil(result.skipReason)
        XCTAssertTrue(recorder.pushes.isEmpty)
        XCTAssertEqual(recorder.recomputeCount, 0)
    }

    func testEmptyReaderReturnsZeroDimensionsAndNoRecompute() async throws {
        let (sink, recorder) = makeSink(reader: FakeReader())
        let result = try await sink.backfill(daysBack: 30)
        XCTAssertFalse(result.skipped)
        XCTAssertNil(result.skipReason)
        XCTAssertEqual(result.dimensionsPushed, 0)
        XCTAssertEqual(result.daysIngested, 0)
        XCTAssertTrue(recorder.pushes.isEmpty)
        XCTAssertEqual(recorder.recomputeCount, 0)
    }

    // ────────────────────────────────────────────────────────────── //
    // Push semantics                                                  //
    // ────────────────────────────────────────────────────────────── //

    func testFullSleepPlusOvernightDayPushesAll5Dimensions() async throws {
        let reader = FakeReader(
            sleep: [day: SleepNightSummary(totalAsleepMinutes: 420.0, deepMinutes: 90.0, remMinutes: 110.0)],
            overnight: [day: OvernightPhysiologySummary(hrvRmssdMs: 55.0, restingHrBpm: 58.0)]
        )
        let (sink, recorder) = makeSink(reader: reader)
        let result = try await sink.backfill(daysBack: 30)

        XCTAssertEqual(result.dimensionsPushed, 5)
        XCTAssertEqual(result.daysIngested, 1)
        XCTAssertEqual(recorder.recomputeCount, 1)

        let dims = Dictionary(uniqueKeysWithValues: recorder.pushes.map { ($0.dimension, $0) })
        XCTAssertEqual(Set(dims.keys),
                       ["sleep_need", "deep_sleep_min", "rem_sleep_min", "hrv_rmssd", "resting_hr"])

        XCTAssertEqual(dims["sleep_need"]!.value, 420.0 * 60.0, accuracy: 0.0001)
        XCTAssertEqual(dims["deep_sleep_min"]!.value, 90.0, accuracy: 0.0001)
        XCTAssertEqual(dims["rem_sleep_min"]!.value, 110.0, accuracy: 0.0001)
        XCTAssertEqual(dims["hrv_rmssd"]!.value, 55.0, accuracy: 0.0001)
        XCTAssertEqual(dims["resting_hr"]!.value, 58.0, accuracy: 0.0001)

        let expectedDayIndex = HealthKitRuntimeSink.epochDay(for: day)
        for p in recorder.pushes {
            XCTAssertEqual(p.confidence, 0.85, accuracy: 0.0001)
            XCTAssertEqual(p.fidelity, 1)
            XCTAssertEqual(p.dayIndex, expectedDayIndex)
        }
    }

    func testZeroOrNilStageMinutesAreSkipped() async throws {
        let reader = FakeReader(
            sleep: [day: SleepNightSummary(totalAsleepMinutes: 300.0, deepMinutes: nil, remMinutes: 0.0)]
        )
        let (sink, recorder) = makeSink(reader: reader)
        let result = try await sink.backfill(daysBack: 30)

        XCTAssertEqual(result.dimensionsPushed, 1)
        XCTAssertEqual(result.daysIngested, 1)
        XCTAssertEqual(Set(recorder.pushes.map(\.dimension)), ["sleep_need"])
    }

    func testSleepWithZeroAsleepMinutesPushesNothing() async throws {
        let reader = FakeReader(
            sleep: [day: SleepNightSummary(totalAsleepMinutes: 0.0, deepMinutes: 90.0, remMinutes: 110.0)]
        )
        let (sink, recorder) = makeSink(reader: reader)
        let result = try await sink.backfill(daysBack: 30)

        // Stage pushes are nested under totalAsleep > 0.
        XCTAssertEqual(result.dimensionsPushed, 0)
        XCTAssertEqual(result.daysIngested, 0)
        XCTAssertEqual(recorder.recomputeCount, 0)
    }

    func testOvernightOnlyDayStillCountsAsIngested() async throws {
        let reader = FakeReader(
            overnight: [day: OvernightPhysiologySummary(hrvRmssdMs: 50.0, restingHrBpm: nil)]
        )
        let (sink, recorder) = makeSink(reader: reader)
        let result = try await sink.backfill(daysBack: 30)

        XCTAssertEqual(result.dimensionsPushed, 1)
        XCTAssertEqual(result.daysIngested, 1)
        XCTAssertEqual(recorder.recomputeCount, 1)
        XCTAssertEqual(Set(recorder.pushes.map(\.dimension)), ["hrv_rmssd"])
    }

    func testMultipleDaysAreAggregatedIndependently() async throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let d1 = cal.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let d2 = cal.date(from: DateComponents(year: 2026, month: 1, day: 11))!

        let reader = FakeReader(
            sleep: [
                d1: SleepNightSummary(totalAsleepMinutes: 400.0, deepMinutes: 80.0, remMinutes: 100.0),
                d2: SleepNightSummary(totalAsleepMinutes: 360.0, deepMinutes: nil, remMinutes: nil),
            ],
            overnight: [
                d1: OvernightPhysiologySummary(hrvRmssdMs: 52.0, restingHrBpm: 60.0),
            ]
        )
        let (sink, recorder) = makeSink(reader: reader)
        let result = try await sink.backfill(daysBack: 30)

        XCTAssertEqual(result.dimensionsPushed, 6) // d1=5, d2=1
        XCTAssertEqual(result.daysIngested, 2)
        XCTAssertEqual(recorder.recomputeCount, 1)

        let grouped = Dictionary(grouping: recorder.pushes, by: \.dayIndex)
        XCTAssertEqual(grouped[HealthKitRuntimeSink.epochDay(for: d1)]?.count, 5)
        XCTAssertEqual(grouped[HealthKitRuntimeSink.epochDay(for: d2)]?.count, 1)
    }
}
