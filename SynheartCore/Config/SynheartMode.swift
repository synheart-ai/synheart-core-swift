import Foundation

/// Operational mode for Synheart SDK.
///
/// See RFC-CORE-0003.
public enum SynheartMode: String, Codable, CaseIterable {
    case personal
    case insight
    case research
}
