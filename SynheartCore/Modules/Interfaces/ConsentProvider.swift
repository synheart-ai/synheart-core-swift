import Foundation
import Combine

/// Consent tier indicating the scope of data sharing
public enum ConsentTier: String, Codable {
    /// Data stays on device only
    case local
    /// Data may be synced to cloud
    case cloud
    /// Data may be used for research purposes
    case research
}

/// Types of consent. The raw values are the canonical wire names
/// passed to the runtime FFI (see `synheart_core_grant_consent` /
/// `_revoke_consent`); changing them requires a migration.
public enum ConsentType: String {
    case biosignals = "biosignals"
    case behavior = "behavior"
    case phoneContext = "phone_context"
    case cloudUpload = "cloud_upload"
    case syni = "syni"
    case focusEstimation = "focus_estimation"
    case emotionEstimation = "emotion_estimation"
    case vendorSync = "vendor_sync"
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

    /// Consent for vendor-side sync (wearable cloud → Synheart cloud)
    public let vendorSync: Bool

    /// Consent tier (local, cloud, or research)
    public let tier: ConsentTier

    /// Granular channel-level consent (optional; when nil, module-level booleans are used)
    public let channels: ConsentChannels?

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
        vendorSync: Bool = false,
        tier: ConsentTier = .local,
        channels: ConsentChannels? = nil,
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
        self.vendorSync = vendorSync
        self.tier = tier
        self.channels = channels
        self.timestamp = timestamp
        self.version = version
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case biosignals, behavior, phoneContext, cloudUpload, syni
        case focusEstimation, emotionEstimation, vendorSync
        case tier, channels, timestamp, version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        biosignals = try container.decode(Bool.self, forKey: .biosignals)
        behavior = try container.decode(Bool.self, forKey: .behavior)
        phoneContext = try container.decode(Bool.self, forKey: .phoneContext)
        cloudUpload = try container.decode(Bool.self, forKey: .cloudUpload)
        syni = try container.decode(Bool.self, forKey: .syni)
        focusEstimation = (try? container.decode(Bool.self, forKey: .focusEstimation)) ?? false
        emotionEstimation = (try? container.decode(Bool.self, forKey: .emotionEstimation)) ?? false
        vendorSync = (try? container.decode(Bool.self, forKey: .vendorSync)) ?? false
        tier = (try? container.decode(ConsentTier.self, forKey: .tier)) ?? .local
        channels = try? container.decode(ConsentChannels.self, forKey: .channels)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        version = (try? container.decode(String.self, forKey: .version)) ?? "1.0.0"
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
        case .vendorSync:
            return vendorSync
        }
    }

    /// Check if a specific granular channel is allowed.
    ///
    /// Channel format: "biosignals.vitals", "behavior.digitalActivity", etc.
    /// When `channels` is non-nil, checks the granular channel value.
    /// When `channels` is nil, falls back to the corresponding module-level boolean.
    public func allowsChannel(_ channel: String) -> Bool {
        guard let channels = channels else {
            // Fall back to module-level booleans
            let parts = channel.split(separator: ".", maxSplits: 1)
            guard let module = parts.first else { return false }
            switch module {
            case "biosignals": return biosignals
            case "behavior": return behavior
            case "phoneContext": return phoneContext
            case "interpretation":
                if parts.count > 1 {
                    switch parts[1] {
                    case "focusEstimation": return focusEstimation
                    case "emotionEstimation": return emotionEstimation
                    default: return false
                    }
                }
                return focusEstimation || emotionEstimation
            default: return false
            }
        }

        let parts = channel.split(separator: ".", maxSplits: 1)
        guard let module = parts.first else { return false }
        let sub = parts.count > 1 ? String(parts[1]) : nil

        switch module {
        case "biosignals":
            guard let sub = sub else {
                return channels.biosignals.vitals || channels.biosignals.cardioAdvanced ||
                       channels.biosignals.neuromuscular || channels.biosignals.wearableMotion ||
                       channels.biosignals.sleep
            }
            switch sub {
            case "vitals": return channels.biosignals.vitals
            case "cardioAdvanced": return channels.biosignals.cardioAdvanced
            case "neuromuscular": return channels.biosignals.neuromuscular
            case "wearableMotion": return channels.biosignals.wearableMotion
            case "sleep": return channels.biosignals.sleep
            default: return false
            }
        case "behavior":
            guard let sub = sub else { return channels.behavior.enabled }
            switch sub {
            case "digitalActivity": return channels.behavior.digitalActivity
            case "notificationPatterns": return channels.behavior.notificationPatterns
            case "appContext": return channels.behavior.appContext
            default: return false
            }
        case "phoneContext":
            guard let sub = sub else {
                return channels.phoneContext.deviceMotion || channels.phoneContext.deviceContext ||
                       channels.phoneContext.systemState
            }
            switch sub {
            case "deviceMotion": return channels.phoneContext.deviceMotion
            case "deviceContext": return channels.phoneContext.deviceContext
            case "systemState": return channels.phoneContext.systemState
            default: return false
            }
        case "interpretation":
            guard let sub = sub else {
                return channels.interpretation.focusEstimation || channels.interpretation.emotionEstimation
            }
            switch sub {
            case "focusEstimation": return channels.interpretation.focusEstimation
            case "emotionEstimation": return channels.interpretation.emotionEstimation
            default: return false
            }
        default:
            return false
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
        vendorSync: Bool? = nil,
        tier: ConsentTier? = nil,
        channels: ConsentChannels?? = nil,
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
            vendorSync: vendorSync ?? self.vendorSync,
            tier: tier ?? self.tier,
            channels: channels ?? self.channels,
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
            emotionEstimation: false,
            vendorSync: false,
            tier: .local,
            channels: nil
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
            emotionEstimation: true,
            vendorSync: true,
            tier: .local,
            channels: nil
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
