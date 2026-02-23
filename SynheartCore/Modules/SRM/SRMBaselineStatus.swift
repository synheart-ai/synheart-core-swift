import Foundation

/// SRM baseline status per stratum (SRM.pdf §6).
///
/// - `empty`: fewer than M_min accepted windows.
/// - `warming`: between M_min and M_ready accepted windows.
/// - `ready`: at least M_ready windows spanning at least D_min distinct days.
public enum SRMBaselineStatus: Int, CaseIterable, Codable {
    case empty = 0
    case warming = 1
    case ready = 2

    public var uppercased: String {
        switch self {
        case .empty: return "EMPTY"
        case .warming: return "WARMING"
        case .ready: return "READY"
        }
    }
}
