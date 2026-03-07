import Foundation

public struct TombstoneData: Codable {
    public let targetArtifactId: String
    public let reason: String
    public let deletedAtMs: Int64

    public init(targetArtifactId: String, reason: String, deletedAtMs: Int64) {
        self.targetArtifactId = targetArtifactId
        self.reason = reason
        self.deletedAtMs = deletedAtMs
    }

    enum CodingKeys: String, CodingKey {
        case targetArtifactId = "target_artifact_id"
        case reason
        case deletedAtMs = "deleted_at_ms"
    }
}

/// Propagates deletion across devices/apps.
///
/// See RFC-CORE-0006 Section 6.4.
public struct TombstoneArtifact: Codable {
    public let header: ArtifactHeader
    public let tombstone: TombstoneData

    public init(header: ArtifactHeader, tombstone: TombstoneData) {
        self.header = header
        self.tombstone = tombstone
    }

    public static func create(
        subjectId: String,
        targetArtifactId: String,
        reason: String
    ) -> TombstoneArtifact {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let header = ArtifactHeader(
            type: "tombstone",
            subjectId: subjectId,
            sessionId: nil,
            timeRange: TimeRange(startMs: now, endMs: now),
            schema: SchemaRef(name: "tombstone", version: "1")
        )
        return TombstoneArtifact(
            header: header,
            tombstone: TombstoneData(
                targetArtifactId: targetArtifactId,
                reason: reason,
                deletedAtMs: now
            )
        )
    }
}
