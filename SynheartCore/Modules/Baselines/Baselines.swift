// SPDX-License-Identifier: Apache-2.0
//
// Host-facing facade for typed baseline state — observable + sync
// getters. Mirrors Flutter's `Baselines` static surface in
// `lib/src/modules/baselines/baselines.dart` (live `updates` stream +
// `latestSleepScore` / `latestRecoveryScore` / `latestReadinessScore`
// / `reference` getters), without the vendor-ingest orchestration
// that lives on the Flutter SDK only.
//
// The full Flutter `Baselines.ingestVendorSleep(...)` pipeline (Whoop /
// Garmin / Apple Health / Health Connect → score → snapshot) is not
// ported here — Swift hosts wire those ingest paths themselves and
// call the `cache*` setters when results land. The facade owns only
// the in-memory cache + snapshot stream.

import Combine
import Foundation

/// Process-wide observable baseline state. Singleton instance via
/// the static `shared`; direct construction is allowed for tests.
///
/// ```swift
/// var cancellables = Set<AnyCancellable>()
/// Baselines.shared.updates
///     .sink { snap in render(snap) }
///     .store(in: &cancellables)
///
/// // From your vendor ingest code:
/// Baselines.shared.cacheSleepScore(result, source: "whoop")
/// Baselines.shared.cacheReference(refView)
/// ```
public final class Baselines: @unchecked Sendable {

    private var _latestSleepScore: SleepScoreResult?
    private var _latestRecoveryScore: RecoveryScoreResult?
    private var _latestReadinessScore: ReadinessScoreResult?
    private var _latestReference: WearableReferenceView?
    private var _recentSleepScores: [Int] = []
    private var _lastSource: String?
    private let lock = NSLock()

    private let subject = CurrentValueSubject<BaselinesSnapshot?, Never>(nil)

    public init() {}

    /// Broadcast stream of baseline snapshots; emits after every
    /// `cache*` call. Late subscribers receive the current snapshot
    /// immediately (CurrentValueSubject semantics).
    public var updates: AnyPublisher<BaselinesSnapshot, Never> {
        subject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    /// The most recent `SleepScoreResult`, or nil if none cached this session.
    public var latestSleepScore: SleepScoreResult? {
        lock.lock(); defer { lock.unlock() }
        return _latestSleepScore
    }

    /// The most recent `RecoveryScoreResult` computed alongside a sleep ingest, or nil.
    public var latestRecoveryScore: RecoveryScoreResult? {
        lock.lock(); defer { lock.unlock() }
        return _latestRecoveryScore
    }

    /// The most recent `ReadinessScoreResult`, or nil until first compute.
    public var latestReadinessScore: ReadinessScoreResult? {
        lock.lock(); defer { lock.unlock() }
        return _latestReadinessScore
    }

    /// The most recent `WearableReferenceView`, or nil if the engine has not yet produced one.
    public var reference: WearableReferenceView? {
        lock.lock(); defer { lock.unlock() }
        return _latestReference
    }

    /// Provider id of the source that produced `latestSleepScore`.
    public var lastSource: String? {
        lock.lock(); defer { lock.unlock() }
        return _lastSource
    }

    /// Current snapshot of cached state (synchronous).
    public func current() -> BaselinesSnapshot {
        lock.lock(); defer { lock.unlock() }
        return assembleSnapshotLocked()
    }

    // MARK: - Cache setters

    /// Cache a new sleep-score result and emit a snapshot.
    ///
    /// - Parameters:
    ///   - result: the score result (e.g. from a runtime sleep-score pipeline)
    ///   - source: provider id — `whoop`, `garmin`, `apple_health`,
    ///             `health_connect`, `self_report`, etc. Persisted on
    ///             the facade as `lastSource`.
    public func cacheSleepScore(_ result: SleepScoreResult, source: String? = nil) {
        lock.lock()
        _latestSleepScore = result
        if let s = source { _lastSource = s }
        if let score = result.score {
            rollIntoRecentRingLocked(score)
        }
        let snap = assembleSnapshotLocked()
        lock.unlock()
        subject.send(snap)
    }

    /// Cache a new recovery-score result and emit a snapshot.
    public func cacheRecoveryScore(_ result: RecoveryScoreResult) {
        lock.lock()
        _latestRecoveryScore = result
        let snap = assembleSnapshotLocked()
        lock.unlock()
        subject.send(snap)
    }

    /// Cache a new readiness-score result and emit a snapshot.
    public func cacheReadinessScore(_ result: ReadinessScoreResult) {
        lock.lock()
        _latestReadinessScore = result
        let snap = assembleSnapshotLocked()
        lock.unlock()
        subject.send(snap)
    }

    /// Cache a new wearable-reference view and emit a snapshot.
    public func cacheReference(_ reference: WearableReferenceView) {
        lock.lock()
        _latestReference = reference
        let snap = assembleSnapshotLocked()
        lock.unlock()
        subject.send(snap)
    }

    /// Forget every cached value and reset the recent-scores ring.
    /// Called on logout / user switch. Subscribers receive one empty
    /// snapshot so UI re-renders.
    public func reset() {
        lock.lock()
        _latestSleepScore = nil
        _latestRecoveryScore = nil
        _latestReadinessScore = nil
        _latestReference = nil
        _recentSleepScores.removeAll()
        _lastSource = nil
        let snap = assembleSnapshotLocked()
        lock.unlock()
        subject.send(snap)
    }

    // MARK: - Internals

    /// Caller must hold `lock`.
    private func assembleSnapshotLocked() -> BaselinesSnapshot {
        return BaselinesSnapshot(
            reference: _latestReference,
            latestSleepScore: _latestSleepScore,
            latestRecoveryScore: _latestRecoveryScore,
            latestReadinessScore: _latestReadinessScore,
            recentSleepScores: _recentSleepScores,
            capturedAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }

    /// Path-B ring: capped at 7 (oldest dropped when full). Caller must hold `lock`.
    private func rollIntoRecentRingLocked(_ score: Int) {
        _recentSleepScores.append(score)
        while _recentSleepScores.count > 7 {
            _recentSleepScores.removeFirst()
        }
    }

    /// Process-wide instance. Wired by `Synheart` at SDK init; tests
    /// can construct their own.
    public static let shared = Baselines()
}
