import Foundation

/// Quality flags that can be raised on the HSV.
public enum HsvQualityFlag: String, Codable {
    /// At least one modality has stale data.
    case staleData
    /// Only a single modality contributed (low fusion diversity).
    case singleModality
    /// Baselines have not yet converged (insufficient history).
    case lowBaselineHistory
    /// Sensor data had gaps or interpolation was needed.
    case sensorGaps
}

/// Aggregated quality assessment for the Human State Vector.
///
/// Mirrors the runtime's `StateQuality`.
/// Summarizes the reliability and completeness of the fused state.
/// Downstream consumers can use `overallConfidence`
/// and `degraded` to decide whether to export or gate readings.
public struct StateQuality: Codable {
    /// Overall confidence in the fused HSV, [0.0, 1.0].
    public let overallConfidence: Float

    /// Number of modalities that contributed data (0–3).
    public let modalityCount: Int

    /// True when quality is below acceptable thresholds.
    public let degraded: Bool

    /// Set of active quality flags.
    public let qualityFlags: Set<HsvQualityFlag>

    public init(
        overallConfidence: Float = 0.0,
        modalityCount: Int = 0,
        degraded: Bool = true,
        qualityFlags: Set<HsvQualityFlag> = []
    ) {
        self.overallConfidence = overallConfidence
        self.modalityCount = modalityCount
        self.degraded = degraded
        self.qualityFlags = qualityFlags
    }

    /// Default quality indicating no data available.
    public static let empty = StateQuality()
}
