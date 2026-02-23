import Foundation

/// SRM context strata for baseline partitioning.
///
/// Each stratum maintains an independent reference buffer to prevent
/// distributional contamination across contexts (SRM.pdf §3.2).
public enum SRMStratum: String, CaseIterable, Codable {
    case sleep
    case rest
    case breathing
    case morning
    case other

    public static func from(_ value: String) -> SRMStratum? {
        return SRMStratum(rawValue: value.lowercased())
    }
}
