import Foundation

/// Per-stratum snapshot for serialization.
public struct StratumSnapshot {
    public let stratum: SRMStratum
    public let status: SRMBaselineStatus
    public let entries: [BufferEntry]
    public let reference: [String: MetricReference]
    public let distinctDays: Int
}

/// Complete SRM snapshot — all strata, versioned.
///
/// Used for in-memory save/restore of SRM state across session boundaries.
public struct SRMSnapshot {
    public let srmVersion: String
    public let createdAtUtc: Date
    public let strata: [SRMStratum: StratumSnapshot]
}
