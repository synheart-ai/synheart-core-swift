import Foundation

/// Per-stratum snapshot for serialization.
public struct StratumSnapshot: Codable {
    public let stratum: SRMStratum
    public let status: SRMBaselineStatus
    public let entries: [BufferEntry]
    public let reference: [String: MetricReference]
    public let distinctDays: Int

    private enum CodingKeys: String, CodingKey {
        case stratum
        case status
        case entries
        case reference
        case distinctDays = "distinct_days"
    }
}

/// Complete SRM snapshot — all strata, versioned.
///
/// Used for in-memory save/restore of SRM state across session boundaries.
public struct SRMSnapshot: Codable {
    public let srmVersion: String
    public let createdAtUtc: Date
    public let strata: [SRMStratum: StratumSnapshot]

    private enum CodingKeys: String, CodingKey {
        case srmVersion = "srm_version"
        case createdAtUtc = "created_at_utc"
        case strata
    }
}
