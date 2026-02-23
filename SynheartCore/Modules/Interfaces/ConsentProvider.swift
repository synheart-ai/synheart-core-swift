import Foundation
import Combine

/// Types of consent
public enum ConsentType {
    /// Consent for biosignal collection
    case biosignals

    /// Consent for behavioral data collection
    case behavior

    /// Consent for phone context data collection
    case phoneContext

    /// Consent for cloud uploads
    case cloudUpload

    /// Consent for Syni personalization
    case syni

    /// Consent for focus estimation
    case focusEstimation

    /// Consent for emotion estimation
    case emotionEstimation
}

/// Snapshot of user consent at a point in time
public struct ConsentSnapshot: Codable {
    /// Consent for biosignal collection
    public let biosignals: Bool

    /// Consent for behavioral data collection
    public let behavior: Bool

    /// Consent for phone context data collection
    public let phoneContext: Bool

    /// Consent for cloud uploads
    public let cloudUpload: Bool

    /// Consent for Syni personalization
    public let syni: Bool

    /// Consent for focus estimation
    public let focusEstimation: Bool

    /// Consent for emotion estimation
    public let emotionEstimation: Bool

    /// Timestamp when this consent was given
    public let timestamp: Date

    /// Schema version for this consent snapshot
    public let version: String

    public init(
        biosignals: Bool,
        behavior: Bool,
        phoneContext: Bool,
        cloudUpload: Bool,
        syni: Bool,
        focusEstimation: Bool = false,
        emotionEstimation: Bool = false,
        timestamp: Date = Date(),
        version: String = "1.0.0"
    ) {
        self.biosignals = biosignals
        self.behavior = behavior
        self.phoneContext = phoneContext
        self.cloudUpload = cloudUpload
        self.syni = syni
        self.focusEstimation = focusEstimation
        self.emotionEstimation = emotionEstimation
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
        case .phoneContext:
            return phoneContext
        case .cloudUpload:
            return cloudUpload
        case .syni:
            return syni
        case .focusEstimation:
            return focusEstimation
        case .emotionEstimation:
            return emotionEstimation
        }
    }

    /// Create a copy with updated values
    public func copyWith(
        biosignals: Bool? = nil,
        behavior: Bool? = nil,
        phoneContext: Bool? = nil,
        cloudUpload: Bool? = nil,
        syni: Bool? = nil,
        focusEstimation: Bool? = nil,
        emotionEstimation: Bool? = nil,
        timestamp: Date? = nil,
        version: String? = nil
    ) -> ConsentSnapshot {
        return ConsentSnapshot(
            biosignals: biosignals ?? self.biosignals,
            behavior: behavior ?? self.behavior,
            phoneContext: phoneContext ?? self.phoneContext,
            cloudUpload: cloudUpload ?? self.cloudUpload,
            syni: syni ?? self.syni,
            focusEstimation: focusEstimation ?? self.focusEstimation,
            emotionEstimation: emotionEstimation ?? self.emotionEstimation,
            timestamp: timestamp ?? self.timestamp,
            version: version ?? self.version
        )
    }

    /// Create a consent snapshot with all consents denied
    public static func none() -> ConsentSnapshot {
        return ConsentSnapshot(
            biosignals: false,
            behavior: false,
            phoneContext: false,
            cloudUpload: false,
            syni: false,
            focusEstimation: false,
            emotionEstimation: false
        )
    }

    /// Create a consent snapshot with all consents granted
    public static func all() -> ConsentSnapshot {
        return ConsentSnapshot(
            biosignals: true,
            behavior: true,
            phoneContext: true,
            cloudUpload: true,
            syni: true,
            focusEstimation: true,
            emotionEstimation: true
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
