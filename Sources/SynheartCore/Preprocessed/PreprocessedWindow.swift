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
    let schemaVersion: String
    let windowStartMs: Int64
    let windowEndMs: Int64
    let sessionId: String
    let quality: Quality
    let derivedFeatures: DerivedFeatures
    let behaviorFeatures: BehaviorFeatures?
    let srmContext: SrmContext
    let embeddings: Embeddings

    enum CodingKeys: String, CodingKey {
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

    static func fromJson(_ jsonStr: String) throws -> PreprocessedWindow {
        guard let data = jsonStr.data(using: .utf8) else {
            throw NSError(domain: "PreprocessedWindow", code: 1, userInfo: nil)
        }
        return try JSONDecoder().decode(PreprocessedWindow.self, from: data)
    }

    func toJson() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Quality metrics for the window
public struct Quality: Codable {
    let score: Double
    let coveragePct: Double
    let dropoutCount: Int
    let rrCount: Int
    let artifactPct: Double

    enum CodingKeys: String, CodingKey {
        case score
        case coveragePct = "coverage_pct"
        case dropoutCount = "dropout_count"
        case rrCount = "rr_count"
        case artifactPct = "artifact_pct"
    }

    init(
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
    let rmssdMs: Double
    let sdnnMs: Double
    let pnn50: Double
    let meanRrMs: Double
    let hrMeanBpm: Double
    let hrStdBpm: Double
    let rrCount: Int

    enum CodingKeys: String, CodingKey {
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
    let accelRms: Double
    let accelVar: Double
    let stepsEst: Int
    let postureProxy: Double
    let sampleCount: Int

    enum CodingKeys: String, CodingKey {
        case accelRms = "accel_rms"
        case accelVar = "accel_var"
        case stepsEst = "steps_est"
        case postureProxy = "posture_proxy"
        case sampleCount = "sample_count"
    }
}

/// Artifact filtering results
public struct ArtifactResult: Codable {
    let artifactPct: Double
    let ectopicLikePct: Double
    let originalCount: Int

    enum CodingKeys: String, CodingKey {
        case artifactPct = "artifact_pct"
        case ectopicLikePct = "ectopic_like_pct"
        case originalCount = "original_count"
    }
}

/// Derived features (HRV, motion, artifact)
public struct DerivedFeatures: Codable {
    let hrv: HrvFeatures?
    let motion: MotionFeatures?
    let artifact: ArtifactResult?

    init(hrv: HrvFeatures? = nil, motion: MotionFeatures? = nil, artifact: ArtifactResult? = nil) {
        self.hrv = hrv
        self.motion = motion
        self.artifact = artifact
    }
}

/// Behavior features from phone interaction
public struct BehaviorFeatures: Codable {
    let screenOnPct: Double
    let touchRatePerMin: Double
    let appSwitchesPerMin: Double
    let notificationInterruptions: Int

    enum CodingKeys: String, CodingKey {
        case screenOnPct = "screen_on_pct"
        case touchRatePerMin = "touch_rate_per_min"
        case appSwitchesPerMin = "app_switches_per_min"
        case notificationInterruptions = "notification_interruptions"
    }
}

/// SRM baseline deviation context
public struct SrmDeviation: Codable {
    let observed: Double
    let mu: Double
    let sigma: Double
    let zScore: Double
    let status: String // "Ready", "Warming", "Empty"

    enum CodingKeys: String, CodingKey {
        case observed
        case mu
        case sigma
        case zScore = "z_score"
        case status
    }
}

/// SRM baseline context with deviations
public struct SrmContext: Codable {
    let readyCount: Int
    let totalCount: Int
    let deviations: [String: SrmDeviation]

    enum CodingKeys: String, CodingKey {
        case readyCount = "ready_count"
        case totalCount = "total_count"
        case deviations
    }

    init(
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
    let vector: [Double]
    let dimension: Int
    let space: String

    init(vector: [Double] = [], dimension: Int = 0, space: String = "") {
        self.vector = vector
        self.dimension = dimension
        self.space = space
    }
}

/// Embeddings (signal, behavior, combined)
public struct Embeddings: Codable {
    let signalEmbedding: SignalEmbedding

    enum CodingKeys: String, CodingKey {
        case signalEmbedding = "signal_embedding"
    }

    init(signalEmbedding: SignalEmbedding = SignalEmbedding()) {
        self.signalEmbedding = signalEmbedding
    }
}
