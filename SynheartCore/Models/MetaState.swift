import Foundation

/// Metadata about the current state session
public struct MetaState: Codable {
    public let device: DeviceInfo
    public let sessionId: String
    public let timestamp: Date
    public let embeddings: [Float]?

    /// SRM baseline status (EMPTY, WARMING, READY) — nil if SRM not active.
    public let baselineStatus: String?

    /// SRM snapshot identifier — nil if SRM not active.
    public let srmSnapshotId: String?

    /// SRM schema version — nil if SRM not active.
    public let srmVersion: String?

    /// Total distinct calendar days across SRM strata.
    public let baselineDays: Int?

    /// Total accepted windows across SRM strata.
    public let baselineSessions: Int?

    public init(device: DeviceInfo,
                sessionId: String = UUID().uuidString,
                timestamp: Date = Date(),
                embeddings: [Float]? = nil,
                baselineStatus: String? = nil,
                srmSnapshotId: String? = nil,
                srmVersion: String? = nil,
                baselineDays: Int? = nil,
                baselineSessions: Int? = nil) {
        self.device = device
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.embeddings = embeddings
        self.baselineStatus = baselineStatus
        self.srmSnapshotId = srmSnapshotId
        self.srmVersion = srmVersion
        self.baselineDays = baselineDays
        self.baselineSessions = baselineSessions
    }
}

