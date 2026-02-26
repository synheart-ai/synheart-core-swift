import Foundation

/// Pre-processed Window - INTERNAL ONLY
///
/// Intermediate signal processing and feature extraction output from synheart-runtime.
/// Contains quality metrics, derived features, SRM baseline context, and embeddings.
///
/// Used internally for:
/// - On-device model training (transfer learning, fine-tuning)
/// - Research & development (feature engineering, validation)
/// - Diagnostics & debugging (signal quality, pipeline inspection)
/// - Custom inference (alternative models, multi-modal fusion)
///
/// This is NOT part of the public API - follows same internal-only pattern as HSV.
public struct PreprocessedWindow: Codable {
    public let schemaVersion: String
    public let windowStartMs: Int64
    public let windowEndMs: Int64
    public let sessionId: String
    public let quality: Quality
    public let derivedFeatures: DerivedFeatures
    public let behaviorFeatures: BehaviorFeatures?
    public let srmContext: SrmContext
    public let embeddings: Embeddings

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case windowStartMs = "window_start_ms"
        case windowEndMs = "window_end_ms"
        case sessionId = "session_id"
        case quality
        case derivedFeatures = "derived_features"
        case behaviorFeatures = "behavior_features"
        case srmContext = "srm_context"
        case embeddings
    }

    public static func fromJson(_ jsonStr: String) throws -> PreprocessedWindow {
        guard let data = jsonStr.data(using: .utf8) else {
            throw NSError(domain: "PreprocessedWindow", code: 1, userInfo: nil)
        }
        return try JSONDecoder().decode(PreprocessedWindow.self, from: data)
    }

    public func toJson() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Quality metrics for the window
public struct Quality: Codable {
    public let score: Double
    public let coveragePct: Double
    public let dropoutCount: Int
    public let rrCount: Int
    public let artifactPct: Double

    public enum CodingKeys: String, CodingKey {
        case score
        case coveragePct = "coverage_pct"
        case dropoutCount = "dropout_count"
        case rrCount = "rr_count"
        case artifactPct = "artifact_pct"
    }

    public init(
        score: Double = 0.0,
        coveragePct: Double = 0.0,
        dropoutCount: Int = 0,
        rrCount: Int = 0,
        artifactPct: Double = 0.0
    ) {
        self.score = score
        self.coveragePct = coveragePct
        self.dropoutCount = dropoutCount
        self.rrCount = rrCount
        self.artifactPct = artifactPct
    }
}

/// HRV features derived from RR intervals
public struct HrvFeatures: Codable {
    public let rmssdMs: Double
    public let sdnnMs: Double
    public let pnn50: Double
    public let meanRrMs: Double
    public let hrMeanBpm: Double
    public let hrStdBpm: Double
    public let rrCount: Int

    public enum CodingKeys: String, CodingKey {
        case rmssdMs = "rmssd_ms"
        case sdnnMs = "sdnn_ms"
        case pnn50
        case meanRrMs = "mean_rr_ms"
        case hrMeanBpm = "hr_mean_bpm"
        case hrStdBpm = "hr_std_bpm"
        case rrCount = "rr_count"
    }
}

/// Motion features from accelerometer
public struct MotionFeatures: Codable {
    public let accelRms: Double
    public let accelVar: Double
    public let stepsEst: Int
    public let postureProxy: Double
    public let sampleCount: Int

    public enum CodingKeys: String, CodingKey {
        case accelRms = "accel_rms"
        case accelVar = "accel_var"
        case stepsEst = "steps_est"
        case postureProxy = "posture_proxy"
        case sampleCount = "sample_count"
    }
}

/// Artifact filtering results
public struct ArtifactResult: Codable {
    public let artifactPct: Double
    public let ectopicLikePct: Double
    public let originalCount: Int

    public enum CodingKeys: String, CodingKey {
        case artifactPct = "artifact_pct"
        case ectopicLikePct = "ectopic_like_pct"
        case originalCount = "original_count"
    }
}

/// Derived features (HRV, motion, artifact)
public struct DerivedFeatures: Codable {
    public let hrv: HrvFeatures?
    public let motion: MotionFeatures?
    public let artifact: ArtifactResult?

    public init(hrv: HrvFeatures? = nil, motion: MotionFeatures? = nil, artifact: ArtifactResult? = nil) {
        self.hrv = hrv
        self.motion = motion
        self.artifact = artifact
    }
}

/// Behavior features from phone interaction
public struct BehaviorFeatures: Codable {
    public let screenOnPct: Double
    public let touchRatePerMin: Double
    public let appSwitchesPerMin: Double
    public let notificationInterruptions: Int

    public enum CodingKeys: String, CodingKey {
        case screenOnPct = "screen_on_pct"
        case touchRatePerMin = "touch_rate_per_min"
        case appSwitchesPerMin = "app_switches_per_min"
        case notificationInterruptions = "notification_interruptions"
    }
}

/// SRM baseline deviation context
public struct SrmDeviation: Codable {
    public let observed: Double
    public let mu: Double
    public let sigma: Double
    public let zScore: Double
    public let status: String // "Ready", "Warming", "Empty"

    public enum CodingKeys: String, CodingKey {
        case observed
        case mu
        case sigma
        case zScore = "z_score"
        case status
    }
}

/// SRM baseline context with deviations
public struct SrmContext: Codable {
    public let readyCount: Int
    public let totalCount: Int
    public let deviations: [String: SrmDeviation]

    public enum CodingKeys: String, CodingKey {
        case readyCount = "ready_count"
        case totalCount = "total_count"
        case deviations
    }

    public init(
        readyCount: Int = 0,
        totalCount: Int = 0,
        deviations: [String: SrmDeviation] = [:]
    ) {
        self.readyCount = readyCount
        self.totalCount = totalCount
        self.deviations = deviations
    }
}

/// Signal embedding
public struct SignalEmbedding: Codable {
    public let vector: [Double]
    public let dimension: Int
    public let space: String

    public init(vector: [Double] = [], dimension: Int = 0, space: String = "") {
        self.vector = vector
        self.dimension = dimension
        self.space = space
    }
}

/// Embeddings (signal, behavior, combined)
public struct Embeddings: Codable {
    public let signalEmbedding: SignalEmbedding

    public enum CodingKeys: String, CodingKey {
        case signalEmbedding = "signal_embedding"
    }

    public init(signalEmbedding: SignalEmbedding = SignalEmbedding()) {
        self.signalEmbedding = signalEmbedding
    }
}
