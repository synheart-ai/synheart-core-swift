import Foundation

/// Data provenance tracking aligned with synheart-flux HSV.
///
/// Mirrors Rust `ProvenanceInfo` — records the origin and lineage of data
/// that contributed to the Human State Vector.
public struct ProvenanceInfo: Codable {
    /// Unique identifiers of data sources that contributed.
    public let sourceIds: [String]

    /// Vendor names that contributed data (e.g., "whoop", "garmin").
    public let vendors: [String]

    /// Device identifier.
    public let deviceId: String

    /// IANA timezone of the observation.
    public let timezone: String

    /// Number of distinct calendar days in the SRM baseline.
    public let baselineDays: Int

    /// Number of accepted SRM windows (baseline sessions).
    public let baselineSessions: Int

    /// SRM baseline status: EMPTY, WARMING, or READY.
    public let baselineStatus: String?

    /// SRM snapshot identifier for traceability.
    public let srmSnapshotId: String?

    /// Inference mode: deterministic, probabilistic, or composite.
    public let inferenceMode: String?

    public init(
        sourceIds: [String] = [],
        vendors: [String] = [],
        deviceId: String = "",
        timezone: String = "UTC",
        baselineDays: Int = 0,
        baselineSessions: Int = 0,
        baselineStatus: String? = nil,
        srmSnapshotId: String? = nil,
        inferenceMode: String? = nil
    ) {
        self.sourceIds = sourceIds
        self.vendors = vendors
        self.deviceId = deviceId
        self.timezone = timezone
        self.baselineDays = baselineDays
        self.baselineSessions = baselineSessions
        self.baselineStatus = baselineStatus
        self.srmSnapshotId = srmSnapshotId
        self.inferenceMode = inferenceMode
    }

    /// Empty provenance with no source information.
    public static let empty = ProvenanceInfo()
}
