import Foundation

public struct TimeRange: Codable {
    public let startMs: Int64
    public let endMs: Int64

    public init(startMs: Int64, endMs: Int64) {
        self.startMs = startMs
        self.endMs = endMs
    }

    enum CodingKeys: String, CodingKey {
        case startMs = "start_ms"
        case endMs = "end_ms"
    }
}

public struct SchemaRef: Codable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// Common header for all Synheart artifacts.
///
/// See RFC-CORE-0006 Section 4.
public struct ArtifactHeader: Codable {
    public let artifactVersion: String
    public let type: String
    public let artifactId: String
    public let subjectId: String
    public let sessionId: String?
    public let timeRange: TimeRange
    public let seq: Int?
    public let schema: SchemaRef
    public let createdAtMs: Int64

    public init(
        artifactVersion: String = "1",
        type: String,
        subjectId: String,
        sessionId: String? = nil,
        timeRange: TimeRange,
        seq: Int? = nil,
        schema: SchemaRef,
        createdAtMs: Int64? = nil
    ) {
        self.artifactVersion = artifactVersion
        self.type = type
        self.subjectId = subjectId
        self.sessionId = sessionId
        self.timeRange = timeRange
        self.seq = seq
        self.schema = schema
        self.createdAtMs = createdAtMs ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.artifactId = computeArtifactId(
            type: type,
            subjectId: subjectId,
            sessionId: sessionId,
            startMs: timeRange.startMs,
            endMs: timeRange.endMs,
            schemaName: schema.name,
            schemaVersion: schema.version
        )
    }

    enum CodingKeys: String, CodingKey {
        case artifactVersion = "artifact_version"
        case type
        case artifactId = "artifact_id"
        case subjectId = "subject_id"
        case sessionId = "session_id"
        case timeRange = "time_range"
        case seq
        case schema
        case createdAtMs = "created_at_ms"
    }
}
