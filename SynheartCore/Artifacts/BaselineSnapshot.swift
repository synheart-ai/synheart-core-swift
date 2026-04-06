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
public struct BaselineSnapshotArtifact: Codable {
    public let header: ArtifactHeader
    public let baseline: BaselineData
    public let wearableReference: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case header
        case baseline
        case wearableReference = "wearable_reference"
    }

    public init(header: ArtifactHeader, baseline: BaselineData, wearableReference: [String: Any]? = nil) {
        self.header = header
        self.baseline = baseline
        self.wearableReference = wearableReference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        header = try container.decode(ArtifactHeader.self, forKey: .header)
        baseline = try container.decode(BaselineData.self, forKey: .baseline)

        // Decode [String: Any] from a JSON string or dictionary
        if let jsonString = try? container.decode(String.self, forKey: .wearableReference),
           let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            wearableReference = dict
        } else {
            wearableReference = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(header, forKey: .header)
        try container.encode(baseline, forKey: .baseline)

        if let ref = wearableReference,
           let data = try? JSONSerialization.data(withJSONObject: ref),
           let str = String(data: data, encoding: .utf8) {
            try container.encode(str, forKey: .wearableReference)
        } else {
            try container.encodeNil(forKey: .wearableReference)
        }
    }

}
