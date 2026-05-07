// SPDX-License-Identifier: Apache-2.0
//
// Tests for the in-memory fallback path of `SynheartPriority`. The
// FFI path is exercised by the runtime's own Rust tests.

import XCTest
@testable import SynheartCore

final class SynheartPriorityTests: XCTestCase {

    // MARK: - Wire names

    func testWireNamesAreStable() {
        // Persisted in the runtime SQLite schema. Renaming requires
        // a migration.
        XCTAssertEqual(PriorityMetric.heartRate.wireName, "heart_rate")
        XCTAssertEqual(PriorityMetric.hrv.wireName, "hrv")
        XCTAssertEqual(PriorityMetric.steps.wireName, "steps")
        XCTAssertEqual(PriorityMetric.sleep.wireName, "sleep")
        XCTAssertEqual(PriorityMetric.calories.wireName, "calories")
        XCTAssertEqual(PriorityMetric.spo2.wireName, "spo2")
        XCTAssertEqual(PriorityMetric.temperature.wireName, "temperature")
        XCTAssertEqual(PriorityMetric.stress.wireName, "stress")
    }

    func testAllCasesEnumerated() {
        XCTAssertEqual(PriorityMetric.allCases.count, 8)
    }

    // MARK: - In-memory fallback

    func testReportsNotUsingNativeStore() {
        let p = SynheartPriority(forceInMemory: true)
        XCTAssertFalse(p.usingNativeStore)
    }

    func testUnknownProviderReturnsUnranked() {
        let p = SynheartPriority(forceInMemory: true)
        XCTAssertEqual(
            p.effectiveRank(.heartRate, provider: "apple_watch"),
            kPriorityUnranked
        )
    }

    func testSetThenReadProvider() throws {
        let p = SynheartPriority(forceInMemory: true)
        try p.setProviderPriority("apple_watch", rank: 10)
        XCTAssertEqual(p.effectiveRank(.heartRate, provider: "apple_watch"), 10)
    }

    func testMetricOverrideBeatsGlobal() throws {
        let p = SynheartPriority(forceInMemory: true)
        try p.setProviderPriority("oura_ring", rank: 40)
        XCTAssertEqual(p.effectiveRank(.heartRate, provider: "oura_ring"), 40)
        try p.setMetricOverride(.sleep, provider: "oura_ring", rank: 5)
        XCTAssertEqual(p.effectiveRank(.sleep, provider: "oura_ring"), 5)
        // Override only applies to the named metric.
        XCTAssertEqual(p.effectiveRank(.heartRate, provider: "oura_ring"), 40)
    }

    func testClearOverrideFallsBackToGlobal() throws {
        let p = SynheartPriority(forceInMemory: true)
        try p.setProviderPriority("oura_ring", rank: 40)
        try p.setMetricOverride(.sleep, provider: "oura_ring", rank: 5)
        try p.setMetricOverride(.sleep, provider: "oura_ring", rank: nil)
        XCTAssertEqual(p.effectiveRank(.sleep, provider: "oura_ring"), 40)
    }

    func testEmptyProviderThrows() {
        let p = SynheartPriority(forceInMemory: true)
        XCTAssertThrowsError(try p.setProviderPriority("", rank: 1)) { err in
            XCTAssertEqual(err as? PriorityError, .emptyProvider)
        }
        XCTAssertThrowsError(
            try p.setMetricOverride(.hrv, provider: "", rank: 1)
        ) { err in
            XCTAssertEqual(err as? PriorityError, .emptyProvider)
        }
    }

    // MARK: - Resolve

    func testResolveEmptyReturnsNil() {
        let p = SynheartPriority(forceInMemory: true)
        XCTAssertNil(p.resolve(.heartRate, samplesByProvider: [:]))
    }

    func testResolveAllZeroCountsReturnsNil() {
        let p = SynheartPriority(forceInMemory: true)
        XCTAssertNil(p.resolve(.heartRate, samplesByProvider: [
            "apple_watch": 0,
            "oura_ring": 0,
        ]))
    }

    func testResolveLowestRankWins() throws {
        let p = SynheartPriority(forceInMemory: true)
        try p.setProviderPriority("apple_watch", rank: 10)
        try p.setProviderPriority("oura_ring", rank: 40)
        try p.setProviderPriority("phone", rank: 90)

        let r = p.resolve(.heartRate, samplesByProvider: [
            "apple_watch": 100,
            "oura_ring": 100,
            "phone": 100,
        ])
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.winner, "apple_watch")
        XCTAssertEqual(r?.rank, 10)
        XCTAssertEqual(r?.alsoRan.count, 2)
        XCTAssertEqual(r?.alsoRan[0].provider, "oura_ring")
        XCTAssertEqual(r?.alsoRan[1].provider, "phone")
    }

    func testResolveOverrideChangesWinner() throws {
        let p = SynheartPriority(forceInMemory: true)
        try p.setProviderPriority("apple_watch", rank: 10)
        try p.setProviderPriority("oura_ring", rank: 40)
        try p.setMetricOverride(.sleep, provider: "oura_ring", rank: 5)

        let r = p.resolve(.sleep, samplesByProvider: [
            "apple_watch": 100,
            "oura_ring": 100,
        ])
        XCTAssertEqual(r?.winner, "oura_ring")
        XCTAssertEqual(r?.rank, 5)
    }

    func testResolveTieBreakBySampleCountThenAlpha() throws {
        let p = SynheartPriority(forceInMemory: true)
        try p.setProviderPriority("alpha", rank: 10)
        try p.setProviderPriority("beta", rank: 10)
        try p.setProviderPriority("charlie", rank: 10)

        // beta has the highest count → wins
        let r1 = p.resolve(.steps, samplesByProvider: [
            "alpha": 50, "beta": 200, "charlie": 50,
        ])
        XCTAssertEqual(r1?.winner, "beta")

        // tie on count → alphabetical picks alpha
        let r2 = p.resolve(.steps, samplesByProvider: [
            "alpha": 100, "beta": 100,
        ])
        XCTAssertEqual(r2?.winner, "alpha")
    }

    func testResolveUnknownProviderLosesToKnown() throws {
        let p = SynheartPriority(forceInMemory: true)
        try p.setProviderPriority("apple_watch", rank: 10)
        let r = p.resolve(.heartRate, samplesByProvider: [
            "apple_watch": 10,
            "ghost_tracker": 10,
        ])
        XCTAssertEqual(r?.winner, "apple_watch")
    }

    func testResolveUnknownOnlyStillResolves() {
        let p = SynheartPriority(forceInMemory: true)
        let r = p.resolve(.heartRate, samplesByProvider: ["ghost_tracker": 5])
        XCTAssertEqual(r?.winner, "ghost_tracker")
        XCTAssertEqual(r?.rank, kPriorityUnranked)
    }
}
