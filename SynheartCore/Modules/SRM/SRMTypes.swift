import Foundation

/// A candidate window submitted by synheart-runtime for SRM consideration.
///
/// Contains the metrics and metadata needed for quality gating,
/// outlier rejection, and buffer update (SRM.pdf §4).
public struct CandidateWindow {
    public let sessionId: String
    public let windowId: String
    public let stratum: SRMStratum
    public let metrics: [String: Double]
    public let qualityScore: Double
    public let motionScore: Double
    public let durationSeconds: Double
    public let observedAtUtc: Date

    public init(
        sessionId: String,
        windowId: String,
        stratum: SRMStratum,
        metrics: [String: Double],
        qualityScore: Double,
        motionScore: Double,
        durationSeconds: Double,
        observedAtUtc: Date
    ) {
        self.sessionId = sessionId
        self.windowId = windowId
        self.stratum = stratum
        self.metrics = metrics
        self.qualityScore = qualityScore
        self.motionScore = motionScore
        self.durationSeconds = durationSeconds
        self.observedAtUtc = observedAtUtc
    }

    /// Check if any metric value is NaN or Inf.
    public var hasInvalidValues: Bool {
        if qualityScore.isNaN || qualityScore.isInfinite { return true }
        if motionScore.isNaN || motionScore.isInfinite { return true }
        if durationSeconds.isNaN || durationSeconds.isInfinite { return true }
        return metrics.values.contains { $0.isNaN || $0.isInfinite }
    }
}

/// Per-metric robust reference (median and MAD).
public struct MetricReference: Codable {
    public let median: Double
    public let mad: Double

    public init(median: Double, mad: Double) {
        self.median = median
        self.mad = mad
    }
}

/// SRM reference for a stratum — per-metric median/MAD plus status.
public struct SRMReference {
    public let stratum: SRMStratum
    public let status: SRMBaselineStatus
    public let metrics: [String: MetricReference]
    public let bufferCount: Int
    public let distinctDays: Int
}

/// Result returned after submitting a candidate window.
public struct SRMResult {
    public let accepted: Bool
    public let rejectionReason: String?
    public let baselineStatus: SRMBaselineStatus
    public let reference: [String: MetricReference]?
    public let srmSnapshotId: String
    public let srmVersion: String

    public init(
        accepted: Bool,
        rejectionReason: String? = nil,
        baselineStatus: SRMBaselineStatus,
        reference: [String: MetricReference]? = nil,
        srmSnapshotId: String,
        srmVersion: String
    ) {
        self.accepted = accepted
        self.rejectionReason = rejectionReason
        self.baselineStatus = baselineStatus
        self.reference = reference
        self.srmSnapshotId = srmSnapshotId
        self.srmVersion = srmVersion
    }
}
