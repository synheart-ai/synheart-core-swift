import Foundation
import Combine

/// Types of consent
public enum ConsentType {
    /// Consent for biosignal collection
    case biosignals

    /// Consent for behavioral data collection
    case behavior

    /// Consent for motion/context data collection
    case motion

    /// Consent for cloud uploads
    case cloudUpload

    /// Consent for Syni personalization
    case syni
}

/// Snapshot of user consent at a point in time
public struct ConsentSnapshot: Codable {
    /// Consent for biosignal collection
    public let biosignals: Bool

    /// Consent for behavioral data collection
    public let behavior: Bool

    /// Consent for motion/context data collection
    public let motion: Bool

    /// Consent for cloud uploads
    public let cloudUpload: Bool

    /// Consent for Syni personalization
    public let syni: Bool

    /// Timestamp when this consent was given
    public let timestamp: Date

    /// Schema version for this consent snapshot
    public let version: String

    public init(
        biosignals: Bool,
        behavior: Bool,
        motion: Bool,
        cloudUpload: Bool,
        syni: Bool,
        timestamp: Date = Date(),
        version: String = "1.0.0"
    ) {
        self.biosignals = biosignals
        self.behavior = behavior
        self.motion = motion
        self.cloudUpload = cloudUpload
        self.syni = syni
        self.timestamp = timestamp
        self.version = version
    }

    /// Check if a specific consent type is allowed
    public func allows(_ type: ConsentType) -> Bool {
        switch type {
        case .biosignals:
            return biosignals
        case .behavior:
            return behavior
        case .motion:
            return motion
        case .cloudUpload:
            return cloudUpload
        case .syni:
            return syni
        }
    }

    /// Create a copy with updated values
    public func copyWith(
        biosignals: Bool? = nil,
        behavior: Bool? = nil,
        motion: Bool? = nil,
        cloudUpload: Bool? = nil,
        syni: Bool? = nil,
        timestamp: Date? = nil,
        version: String? = nil
    ) -> ConsentSnapshot {
        return ConsentSnapshot(
            biosignals: biosignals ?? self.biosignals,
            behavior: behavior ?? self.behavior,
            motion: motion ?? self.motion,
            cloudUpload: cloudUpload ?? self.cloudUpload,
            syni: syni ?? self.syni,
            timestamp: timestamp ?? self.timestamp,
            version: version ?? self.version
        )
    }

    /// Create a consent snapshot with all consents denied
    public static func none() -> ConsentSnapshot {
        return ConsentSnapshot(
            biosignals: false,
            behavior: false,
            motion: false,
            cloudUpload: false,
            syni: false
        )
    }

    /// Create a consent snapshot with all consents granted
    public static func all() -> ConsentSnapshot {
        return ConsentSnapshot(
            biosignals: true,
            behavior: true,
            motion: true,
            cloudUpload: true,
            syni: true
        )
    }
}

/// Provider interface for consent management
public protocol ConsentProvider: AnyObject {
    /// Get the current consent snapshot
    func current() -> ConsentSnapshot

    /// Observe consent changes
    func observe() -> AnyPublisher<ConsentSnapshot, Never>

    /// Update consent (internal use)
    func updateConsent(_ newConsent: ConsentSnapshot) async throws
}
