import Foundation

/// Operational mode for Synheart SDK.
public enum SynheartMode: String, Codable, CaseIterable {
    case personal
    case insight
    case research
}
