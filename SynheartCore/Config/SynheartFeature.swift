import Foundation

/// RFC-0005 Section 6: Synheart feature identifiers for the four-authority activation model.
///
/// A feature is **operational** when all four conditions hold:
/// ```
/// FeatureOperational = Activation AND Consent AND Capability AND SessionActive
/// ```
public enum SynheartFeature: String, CaseIterable, Sendable {
    /// Biosignal collection (HR, HRV) via wearable
    case wear

    /// User interaction tracking (taps, keystrokes, gestures)
    case behavior

    /// Device motion, screen state, and app context
    case phoneContext

    /// Cloud upload connector
    case cloud

    /// Syni hooks integration
    case syni

    /// The consent type required for this feature to operate.
    public var requiredConsent: String {
        switch self {
        case .wear:         return "biosignals"
        case .behavior:     return "behavior"
        case .phoneContext:  return "phoneContext"
        case .cloud:        return "cloudUpload"
        case .syni:         return "syni"
        }
    }
}
