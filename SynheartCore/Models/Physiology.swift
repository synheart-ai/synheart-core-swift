import Foundation

/// A single HSV axis reading: optional score with associated confidence.
///
/// Mirrors Rust `HsvAxisValue { score: Option<f32>, confidence: f32 }` from
/// synheart-engine. Score is nil when the signal is unavailable;
/// confidence reflects measurement quality independent of the score value.
public struct HsvAxisValue: Codable {
    /// Normalized score in [0.0, 1.0], or nil if signal unavailable.
    public let score: Float?

    /// Confidence in the reading [0.0, 1.0].
    public let confidence: Float

    /// Whether a usable score is present.
    public var isPresent: Bool { score != nil }

    public init(score: Float? = nil, confidence: Float = 0.0) {
        self.score = score
        self.confidence = confidence
    }

    /// An absent axis value with zero confidence.
    public static let absent = HsvAxisValue(score: nil, confidence: 0.0)
}

/// Physiology domain of the Human State Vector.
///
/// Contains all wearable-derived physiological readings, each paired with
/// a confidence score. Mirrors Rust `PhysiologyState` from synheart-engine.
///
/// Populated by wearable adapters (WHOOP, Garmin, etc.) via the biosignal
/// pipeline. Emotion and Focus heads in external SDKs (synheart-emotion,
/// synheart-focus) may consume these values but do NOT populate them.
public struct PhysiologyState: Codable {
    /// Sleep efficiency (0–1). Higher is better.
    public var sleepEfficiency: HsvAxisValue

    /// Recovery score (0–1). Higher indicates better recovery.
    public var recoveryScore: HsvAxisValue

    /// HRV deviation from personal baseline (0–1, 0.5 = at baseline).
    public var hrvDeviation: HsvAxisValue

    /// Resting heart rate deviation from baseline (0–1, 0.5 = at baseline).
    public var rhrDeviation: HsvAxisValue

    /// Respiratory rate normalized (0–1).
    public var respiratoryRate: HsvAxisValue

    /// Blood oxygen saturation normalized (0–1).
    public var spo2: HsvAxisValue

    /// Physical strain / exertion (0–1). Higher means more strain.
    public var strain: HsvAxisValue

    /// Sleep duration ratio vs. target (0–1).
    public var sleepDuration: HsvAxisValue

    /// Deep sleep ratio (0–1).
    public var deepSleepRatio: HsvAxisValue

    /// REM sleep ratio (0–1).
    public var remSleepRatio: HsvAxisValue

    /// Sleep fragmentation index (0–1). Higher means more fragmented.
    public var sleepFragmentation: HsvAxisValue

    public init(
        sleepEfficiency: HsvAxisValue = .absent,
        recoveryScore: HsvAxisValue = .absent,
        hrvDeviation: HsvAxisValue = .absent,
        rhrDeviation: HsvAxisValue = .absent,
        respiratoryRate: HsvAxisValue = .absent,
        spo2: HsvAxisValue = .absent,
        strain: HsvAxisValue = .absent,
        sleepDuration: HsvAxisValue = .absent,
        deepSleepRatio: HsvAxisValue = .absent,
        remSleepRatio: HsvAxisValue = .absent,
        sleepFragmentation: HsvAxisValue = .absent
    ) {
        self.sleepEfficiency = sleepEfficiency
        self.recoveryScore = recoveryScore
        self.hrvDeviation = hrvDeviation
        self.rhrDeviation = rhrDeviation
        self.respiratoryRate = respiratoryRate
        self.spo2 = spo2
        self.strain = strain
        self.sleepDuration = sleepDuration
        self.deepSleepRatio = deepSleepRatio
        self.remSleepRatio = remSleepRatio
        self.sleepFragmentation = sleepFragmentation
    }

    /// Count of axes that have a present (non-nil) score.
    public var presentCount: Int {
        allAxes.filter { $0.isPresent }.count
    }

    /// All axis values in declaration order.
    public var allAxes: [HsvAxisValue] {
        [sleepEfficiency, recoveryScore, hrvDeviation, rhrDeviation,
         respiratoryRate, spo2, strain, sleepDuration, deepSleepRatio,
         remSleepRatio, sleepFragmentation]
    }

    /// Empty physiology with no present axes.
    public static let empty = PhysiologyState()
}
