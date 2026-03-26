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

/// Device role determines which modules the SDK enables.
///
/// - ``phone``: Full pipeline — all modules, cloud upload, session management.
///   The phone is the source of truth for data persistence and cloud sync.
///
/// - ``watch``: Edge pipeline — wear + runtime only. No behavior tracking,
///   no cloud upload, no phone context. Sessions are captured locally and
///   relayed to the phone via the companion channel.
public enum DeviceRole: String, Sendable {
    case phone
    case watch

    /// Features available on this device role.
    public var supportedFeatures: Set<SynheartFeature> {
        switch self {
        case .phone: return Set(SynheartFeature.allCases)
        case .watch: return [.wear]
        }
    }

    /// Whether this role supports cloud upload (only phone).
    public var supportsCloud: Bool { self == .phone }

    /// Whether this role supports behavior tracking (only phone).
    public var supportsBehavior: Bool { self == .phone }

    /// Whether this role supports phone context (only phone).
    public var supportsPhoneContext: Bool { self == .phone }

    /// Whether this role manages its own session persistence (only phone).
    public var managesStorage: Bool { self == .phone }
}
