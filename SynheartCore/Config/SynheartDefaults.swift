import Foundation

/// Default constants used across the Synheart SDK.
///
/// Centralizes magic numbers for runtime configuration, biosignal validation,
/// and physiological range boundaries.
public enum SynheartDefaults {
    /// Default runtime window duration in milliseconds (60 seconds).
    public static let runtimeWindowMs: Int64 = 60_000

    /// Default runtime step interval in milliseconds (5 seconds).
    public static let runtimeStepMs: Int64 = 5_000

    /// Default runtime tick interval in seconds.
    public static let runtimeTickIntervalSeconds: TimeInterval = 5.0

    /// Maximum daily steps used for motion normalization (0–1 range).
    public static let maxStepsForMotion: Double = 10_000.0

    /// Minimum valid heart rate in BPM.
    public static let hrMinBpm: Double = 40.0

    /// Maximum valid heart rate in BPM.
    public static let hrMaxBpm: Double = 180.0

    /// Minimum valid RR interval in milliseconds.
    public static let rrMinMs: Double = 300.0

    /// Maximum valid RR interval in milliseconds.
    public static let rrMaxMs: Double = 2_000.0

    /// Milliseconds per minute, used for HR ↔ RR conversion.
    public static let msPerMinute: Double = 60_000.0
}
