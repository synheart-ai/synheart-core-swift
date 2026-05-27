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
public struct TombstoneArtifact: Codable {
    public let header: ArtifactHeader
    public let tombstone: TombstoneData

    public init(header: ArtifactHeader, tombstone: TombstoneData) {
        self.header = header
        self.tombstone = tombstone
    }

}
