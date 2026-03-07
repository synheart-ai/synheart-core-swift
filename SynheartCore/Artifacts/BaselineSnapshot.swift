import Foundation

public struct AxisStats: Codable {
    public let mean: Double
    public let std: Double
    public let confidence: Double

    public init(mean: Double, std: Double, confidence: Double) {
        self.mean = mean
        self.std = std
        self.confidence = confidence
    }
}

public struct BaselineCoverage: Codable {
    public let startMs: Int64
    public let endMs: Int64
    public let totalWindows: Int

    public init(startMs: Int64, endMs: Int64, totalWindows: Int) {
        self.startMs = startMs
        self.endMs = endMs
        self.totalWindows = totalWindows
    }

    enum CodingKeys: String, CodingKey {
        case startMs = "start_ms"
        case endMs = "end_ms"
        case totalWindows = "total_windows"
    }
}

public struct BaselineAxes: Codable {
    public let sleep: AxisStats
    public let capacity: AxisStats
    public let arousal: AxisStats
    public let focus: AxisStats

    public init(sleep: AxisStats, capacity: AxisStats, arousal: AxisStats, focus: AxisStats) {
        self.sleep = sleep
        self.capacity = capacity
        self.arousal = arousal
        self.focus = focus
    }
}

public struct BaselineModelRef: Codable {
    public let modelId: String
    public let modelVersion: String

    public init(modelId: String, modelVersion: String) {
        self.modelId = modelId
        self.modelVersion = modelVersion
    }

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case modelVersion = "model_version"
    }
}

public struct BaselineData: Codable {
    public let coverage: BaselineCoverage
    public let axes: BaselineAxes
    public let model: BaselineModelRef

    public init(coverage: BaselineCoverage, axes: BaselineAxes, model: BaselineModelRef) {
        self.coverage = coverage
        self.axes = axes
        self.model = model
    }
}

/// A compact representation of the user's baseline state.
///
/// See RFC-CORE-0006 Section 6.1.
public struct BaselineSnapshotArtifact: Codable {
    public let header: ArtifactHeader
    public let baseline: BaselineData

    public init(header: ArtifactHeader, baseline: BaselineData) {
        self.header = header
        self.baseline = baseline
    }

    public static func create(subjectId: String, baseline: BaselineData) -> BaselineSnapshotArtifact {
        let header = ArtifactHeader(
            type: "baseline_snapshot",
            subjectId: subjectId,
            sessionId: nil,
            timeRange: TimeRange(startMs: baseline.coverage.startMs, endMs: baseline.coverage.endMs),
            schema: SchemaRef(name: "baseline_snapshot", version: "1")
        )
        return BaselineSnapshotArtifact(header: header, baseline: baseline)
    }
}
