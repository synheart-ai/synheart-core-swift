// SPDX-License-Identifier: Apache-2.0

import XCTest
import Combine
@testable import SynheartCore

final class BaselinesTests: XCTestCase {

    // MARK: - Builders

    private func sleepScore(_ score: Int, priors: Int = 3) -> SleepScoreResult {
        return SleepScoreResult(
            score: score,
            confidence: 0.8,
            path: .stage,
            mode: .shortHistory,
            components: SleepScoreBreakdown(duration: 80, quality: 75),
            adjustments: SleepScoreAdjust(debtPenalty: 0, hrAdjustment: 0),
            effectiveWeights: ComponentWeights(),
            priorNightCount: priors,
            pipelineVersion: "v1",
            modelId: "sleep_v1",
            constantsHash: "abc"
        )
    }

    private func recoveryScore(_ score: Int = 65) -> RecoveryScoreResult {
        return RecoveryScoreResult(
            score: score,
            stage: .shortHistory,
            mode: .trended,
            components: RecoveryComponents(),
            confidence: 0.8,
            modelId: "recovery_v1",
            modelVersion: "1.0",
            pipelineVersion: "v1"
        )
    }

    private func readinessScore(_ score: Int = 72) -> ReadinessScoreResult {
        return ReadinessScoreResult(
            score: score,
            band: .normal,
            recoveryAnchor: 65,
            components: ReadinessComponents(recovery: 65.0),
            confidence: 0.85,
            modelId: "readiness_v1",
            modelVersion: "1.0",
            pipelineVersion: "v1"
        )
    }

    private func reference(status: String, recentMedian: Int? = nil) -> WearableReferenceView {
        return WearableReferenceView(
            status: status,
            recentSleepScoreMedian: recentMedian,
            dimensions: [:]
        )
    }

    // MARK: - Snapshot derived properties

    func testIsEmptyWithNoCachedData() {
        let snap = BaselinesSnapshot(reference: nil, latestSleepScore: nil, capturedAtMs: 0)
        XCTAssertTrue(snap.isEmpty)
        XCTAssertEqual(snap.nightsLoggedCount, 0)
        XCTAssertNil(snap.priorNightCount)
        XCTAssertNil(snap.recentMedian)
    }

    func testIsStableMirrorsReferenceStatusCaseInsensitively() {
        let stable = BaselinesSnapshot(reference: reference(status: "Stable"),
                                       latestSleepScore: nil, capturedAtMs: 0)
        XCTAssertTrue(stable.isStable)
        let warming = BaselinesSnapshot(reference: reference(status: "Warming"),
                                        latestSleepScore: nil, capturedAtMs: 0)
        XCTAssertFalse(warming.isStable)
    }

    func testRecentMedianFromRingWinsOverReference() {
        let snap = BaselinesSnapshot(
            reference: reference(status: "Stable", recentMedian: 99),
            latestSleepScore: nil,
            recentSleepScores: [70, 80, 60],
            capturedAtMs: 0
        )
        XCTAssertEqual(snap.recentMedian, 70)
        XCTAssertEqual(snap.nightsLoggedCount, 3)
    }

    func testRecentMedianFallsBackToReferenceWhenRingEmpty() {
        let snap = BaselinesSnapshot(
            reference: reference(status: "Stable", recentMedian: 78),
            latestSleepScore: nil,
            capturedAtMs: 0
        )
        XCTAssertEqual(snap.recentMedian, 78)
    }

    // MARK: - Facade behavior

    func testCacheSleepScoreEmitsSnapshotWithLatestScoreAndSource() throws {
        let b = Baselines()
        let exp = expectation(description: "snapshot emitted")
        var captured: BaselinesSnapshot?
        let cancellable = b.updates.sink { snap in
            captured = snap
            exp.fulfill()
        }
        b.cacheSleepScore(sleepScore(75), source: "whoop")
        wait(for: [exp], timeout: 1)
        cancellable.cancel()

        XCTAssertEqual(captured?.latestSleepScore?.score, 75)
        XCTAssertEqual(b.lastSource, "whoop")
        XCTAssertEqual(captured?.recentSleepScores, [75])
    }

    func testCacheSleepScoreRollsIntoPathBRingCappedAt7() {
        let b = Baselines()
        for i in 1...10 {
            b.cacheSleepScore(sleepScore(i * 10))
        }
        let snap = b.current()
        XCTAssertEqual(snap.recentSleepScores.count, 7)
        XCTAssertEqual(snap.recentSleepScores, [40, 50, 60, 70, 80, 90, 100])
    }

    func testCacheReferenceAndRecoveryLandOnSameSnapshot() {
        let b = Baselines()
        b.cacheReference(reference(status: "Stable"))
        b.cacheRecoveryScore(recoveryScore(60))
        let snap = b.current()
        XCTAssertEqual(snap.reference?.status, "Stable")
        XCTAssertEqual(snap.latestRecoveryScore?.score, 60)
        XCTAssertNil(snap.latestSleepScore)
    }

    func testCacheReadinessEmitsAndPopulatesReadiness() {
        let b = Baselines()
        b.cacheReadinessScore(readinessScore(80))
        let snap = b.current()
        XCTAssertEqual(snap.latestReadinessScore?.score, 80)
        XCTAssertEqual(snap.latestReadinessScore?.band, .normal)
    }

    func testResetClearsAllCachedStateAndEmitsEmptySnapshot() {
        let b = Baselines()
        b.cacheSleepScore(sleepScore(70), source: "garmin")
        b.cacheRecoveryScore(recoveryScore())
        b.cacheReference(reference(status: "Stable"))
        b.reset()
        let snap = b.current()
        XCTAssertNil(snap.latestSleepScore)
        XCTAssertNil(snap.latestRecoveryScore)
        XCTAssertNil(snap.reference)
        XCTAssertTrue(snap.recentSleepScores.isEmpty)
        XCTAssertNil(b.lastSource)
        XCTAssertTrue(snap.isEmpty)
    }

    func testMultipleCacheCallsProduceMultipleSnapshots() {
        let b = Baselines()
        let exp = expectation(description: "three snapshots emitted")
        exp.expectedFulfillmentCount = 3
        var collected: [BaselinesSnapshot] = []
        let cancellable = b.updates.sink { snap in
            collected.append(snap)
            exp.fulfill()
        }
        b.cacheSleepScore(sleepScore(70))
        b.cacheSleepScore(sleepScore(75))
        b.cacheSleepScore(sleepScore(80))
        wait(for: [exp], timeout: 1)
        cancellable.cancel()

        XCTAssertEqual(collected.count, 3)
        XCTAssertEqual(collected.last?.recentSleepScores, [70, 75, 80])
    }
}
