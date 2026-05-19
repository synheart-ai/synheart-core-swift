// SPDX-License-Identifier: Apache-2.0
//
// Typed aggregate of host-visible baseline state at a point in time.
// Mirrors Flutter's `lib/src/modules/baselines/baselines_snapshot.dart`
// and Kotlin's `modules/baselines/BaselinesSnapshot.kt`.

import Foundation

/// A typed aggregate of the host-visible baseline state at a point in
/// time. Produced by `Baselines` whenever a new sleep score is ingested
/// or the wearable reference refreshes. Consumers read this to render
/// a "your normal" / SRM overview without having to touch FFI or parse
/// raw JSON.
public struct BaselinesSnapshot: Sendable {
    /// Longitudinal-SRM reference view (status, per-dimension medians,
    /// Path-B `recent_sleep_score_median`). nil before the first
    /// reference is produced — an HSI window has to close before the
    /// engine flushes the ring → reference.
    public let reference: WearableReferenceView?

    /// The most recently computed batch `SleepScoreResult`, or nil if
    /// no sleep event has been ingested this session.
    public let latestSleepScore: SleepScoreResult?

    /// The most recent daily Recovery Score per RFC-RECOVERY-SCORE-0001,
    /// computed alongside the sleep ingest when overnight HR or HRV is
    /// available in the same payload. nil when the user has only sleep
    /// data (sleep-only recovery is forbidden by design) or the runtime
    /// hasn't computed one yet this session.
    public let latestRecoveryScore: RecoveryScoreResult?

    /// The most recent daily Readiness Score per RFC-READINESS-SCORE-0001,
    /// computed automatically each time a Recovery Score lands. nil
    /// until at least one Recovery Score has been computed this session.
    public let latestReadinessScore: ReadinessScoreResult?

    /// Path-B 7-night rolling-window scores in attach order
    /// (oldest → newest). Empty until first ingest.
    public let recentSleepScores: [Int]

    /// Millisecond timestamp when this snapshot was assembled.
    public let capturedAtMs: Int64

    public init(
        reference: WearableReferenceView?,
        latestSleepScore: SleepScoreResult?,
        latestRecoveryScore: RecoveryScoreResult? = nil,
        latestReadinessScore: ReadinessScoreResult? = nil,
        recentSleepScores: [Int] = [],
        capturedAtMs: Int64
    ) {
        self.reference = reference
        self.latestSleepScore = latestSleepScore
        self.latestRecoveryScore = latestRecoveryScore
        self.latestReadinessScore = latestReadinessScore
        self.recentSleepScores = recentSleepScores
        self.capturedAtMs = capturedAtMs
    }

    /// True when nothing has been ingested and the engine hasn't
    /// produced a reference — useful for rendering an empty/warming
    /// state in UI.
    public var isEmpty: Bool {
        return reference == nil && latestSleepScore == nil && recentSleepScores.isEmpty
    }

    /// True when the reference is present and reports `READY` status — all five primary SRM dimensions are mature enough for personalized scoring.
    public var isReady: Bool {
        return (reference?.status ?? "").lowercased() == "ready"
    }

    /// Number of prior nights behind the live score, when available.
    public var priorNightCount: Int? {
        return latestSleepScore?.priorNightCount
    }

    /// Number of nights captured in the Path-B ring this session
    /// (capped at 7). This is the right "nights logged" surface for
    /// the user — `priorNightCount` reflects what the scorer saw, not
    /// the cumulative count of attaches.
    public var nightsLoggedCount: Int {
        return recentSleepScores.count
    }

    /// Median of the recent ring; available immediately after the
    /// 3rd attach, regardless of HSI window state. Falls back to the
    /// reference's median when the ring isn't populated locally.
    public var recentMedian: Int? {
        if recentSleepScores.isEmpty {
            return reference?.recentSleepScoreMedian
        }
        let sorted = recentSleepScores.sorted()
        return sorted[sorted.count / 2]
    }
}
