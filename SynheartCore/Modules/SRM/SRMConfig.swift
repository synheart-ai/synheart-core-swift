import Foundation

/// SRM configuration — thresholds, buffer sizes, and gating parameters.
///
/// All values are fixed per deployment and identical across platforms
/// to guarantee deterministic behavior (SRM.pdf §3.4).
public struct SRMConfig {
    /// Tracked metric names.
    public let trackedMetrics: [String]

    /// Maximum buffer size per stratum.
    public let bufferSize: Int

    /// Minimum signal quality score to accept a candidate window.
    public let qualityThreshold: Double

    /// Per-stratum motion thresholds. Windows with motion > beta are rejected.
    public let motionThresholds: [SRMStratum: Double]

    /// Minimum window duration in seconds.
    public let durationThresholdSeconds: Double

    /// Outlier z-score threshold. Reject if |z_k| > kappa for any metric.
    public let outlierKappa: Double

    /// Floor epsilon to prevent division by zero in z-score computation.
    public let epsilon: Double

    /// Minimum accepted windows for WARMING status.
    public let mMin: Int

    /// Minimum accepted windows for READY status.
    public let mReady: Int

    /// Minimum distinct calendar days for READY status.
    public let dMin: Int

    /// SRM schema version for snapshot compatibility.
    public let srmVersion: String

    public init(
        trackedMetrics: [String] = ["hr_mean", "rmssd"],
        bufferSize: Int = 30,
        qualityThreshold: Double = 0.5,
        motionThresholds: [SRMStratum: Double] = [
            .sleep: 0.1,
            .rest: 0.2,
            .breathing: 0.15,
            .morning: 0.3,
            .other: 0.4
        ],
        durationThresholdSeconds: Double = 30.0,
        outlierKappa: Double = 3.0,
        epsilon: Double = 0.001,
        mMin: Int = 3,
        mReady: Int = 10,
        dMin: Int = 3,
        srmVersion: String = "1.0.0"
    ) {
        self.trackedMetrics = trackedMetrics
        self.bufferSize = bufferSize
        self.qualityThreshold = qualityThreshold
        self.motionThresholds = motionThresholds
        self.durationThresholdSeconds = durationThresholdSeconds
        self.outlierKappa = outlierKappa
        self.epsilon = epsilon
        self.mMin = mMin
        self.mReady = mReady
        self.dMin = dMin
        self.srmVersion = srmVersion
    }

    /// Get motion threshold for a stratum, falling back to `other`.
    public func motionThresholdFor(_ stratum: SRMStratum) -> Double {
        return motionThresholds[stratum] ?? motionThresholds[.other] ?? 0.4
    }

    /// Default configuration.
    public static let defaults = SRMConfig()
}
