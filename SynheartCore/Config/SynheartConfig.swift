import Foundation

/// Storage sub-configuration.
public struct StorageConfig {
    public let enabled: Bool
    public let retentionDays: Int?

    public init(enabled: Bool = true, retentionDays: Int? = nil) {
        self.enabled = enabled
        self.retentionDays = retentionDays
    }
}

/// Sync sub-configuration.
public struct SyncConfig {
    public let enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }
}

/// Privacy sub-configuration.
public struct PrivacyConfig {
    public let allowResearch: Bool

    public init(allowResearch: Bool = false) {
        self.allowResearch = allowResearch
    }
}

/// Main configuration for Synheart SDK
public struct SynheartConfig {
    public let appId: String
    public let subjectId: String
    public let mode: SynheartMode
    public let appVersion: String
    public let appName: String
    public let category: String
    public let developer: String
    public let additionalAppMetadata: [String: Any]
    public let deviceId: String
    public let platform: String
    /// Device role — controls which modules are enabled. Defaults to .phone.
    public let deviceRole: DeviceRole
    public let storage: StorageConfig
    public let sync: SyncConfig
    public let privacy: PrivacyConfig

    public let cloudConfig: CloudConfig?
    public let labIngestConfig: LabIngestConfig?
    public let consentConfig: ConsentConfig?

    /// Server-signed capability token for feature gating
    public let capabilityToken: CapabilityToken?

    /// HMAC secret for verifying the capability token signature
    public let capabilitySecret: String?

    /// When true, allows SDK to run with default capabilities and no signed token (debug only)
    public let allowUnsignedCapabilities: Bool

    public init(
        appId: String = "",
        subjectId: String = "",
        mode: SynheartMode = .personal,
        appVersion: String = "0.0.0",
        appName: String = "",
        category: String = "",
        developer: String = "",
        additionalAppMetadata: [String: Any] = [:],
        deviceId: String = "",
        platform: String = "ios",
        deviceRole: DeviceRole = .phone,
        storage: StorageConfig = StorageConfig(),
        sync: SyncConfig = SyncConfig(),
        privacy: PrivacyConfig = PrivacyConfig(),
        cloudConfig: CloudConfig? = nil,
        labIngestConfig: LabIngestConfig? = nil,
        consentConfig: ConsentConfig? = nil,
        capabilityToken: CapabilityToken? = nil,
        capabilitySecret: String? = nil,
        allowUnsignedCapabilities: Bool = false
    ) {
        self.appId = appId
        self.subjectId = subjectId
        self.mode = mode
        self.appVersion = appVersion
        self.appName = appName
        self.category = category
        self.developer = developer
        self.additionalAppMetadata = additionalAppMetadata
        self.deviceId = deviceId
        self.platform = platform
        self.deviceRole = deviceRole
        self.storage = storage
        self.sync = sync
        self.privacy = privacy
        self.cloudConfig = cloudConfig
        self.labIngestConfig = labIngestConfig
        self.consentConfig = consentConfig
        self.capabilityToken = capabilityToken
        self.capabilitySecret = capabilitySecret
        self.allowUnsignedCapabilities = allowUnsignedCapabilities
    }

    /// Validate config and throw on violations.
    public func validate() throws {
        if mode == .research && !privacy.allowResearch {
            throw SynheartCoreError.researchNotAllowed
        }
        guard !appId.isEmpty else {
            throw SynheartCoreError.notConfigured("appId must not be empty")
        }
        guard !subjectId.isEmpty else {
            throw SynheartCoreError.notConfigured("subjectId must not be empty")
        }
        guard !subjectId.contains("|") else {
            throw SynheartCoreError.invalidMode("subjectId must not contain pipe character")
        }
    }
}

/// Cloud Connector configuration
///
/// Required for cloud upload functionality.
///
/// Example:
/// ```swift
/// let cloudConfig = CloudConfig(
///     subjectId: "pseudonymous_user_123",
///     instanceId: UUID().uuidString
/// )
/// ```
public struct CloudConfig {
    /// Base URL for Synheart Platform (default: production)
    public let baseUrl: String

    /// Auth provider for request signing. The runtime signs every ingest
    /// request with the device's hardware-backed ECDSA P-256 key; this is
    /// an override hook for hosts that need to stub it (e.g. in tests).
    public let authProvider: AuthProvider?

    /// Subject ID (pseudonymous user identifier)
    public let subjectId: String

    /// Subject type (default: "pseudonymous_user")
    public let subjectType: String

    /// Instance ID (UUID for this SDK instance)
    public let instanceId: String

    /// Max upload queue size (default: 100)
    public let maxQueueSize: Int

    /// Batch size for uploads (default: 10)
    public let batchSize: Int

    /// Upload interval (default: 5 minutes)
    public let uploadInterval: TimeInterval

    /// Max retry attempts (default: 3)
    public let maxRetries: Int

    /// Enable backlog persistence (default: true)
    public let enableBacklog: Bool

    public init(
        authProvider: AuthProvider? = nil,
        subjectId: String,
        instanceId: String = UUID().uuidString,
        baseUrl: String = ApiEndpoints.defaultCloudBaseUrl,
        subjectType: String = "pseudonymous_user",
        maxQueueSize: Int = 100,
        batchSize: Int = 10,
        uploadInterval: TimeInterval = 300, // 5 minutes
        maxRetries: Int = 3,
        enableBacklog: Bool = true
    ) {
        self.authProvider = authProvider
        self.subjectId = subjectId
        self.instanceId = instanceId
        self.baseUrl = baseUrl
        self.subjectType = subjectType
        self.maxQueueSize = maxQueueSize
        self.batchSize = batchSize
        self.uploadInterval = uploadInterval
        self.maxRetries = maxRetries
        self.enableBacklog = enableBacklog
    }
}

/// Configuration for Consent Service integration
///
/// When configured with appId and appApiKey, the SDK can fetch consent profiles
/// from the cloud consent service and issue JWT tokens for cloud uploads.
public struct ConsentConfig {
    /// Base URL for consent service
    public let consentServiceUrl: String

    /// App ID for consent service
    public let appId: String?

    /// App API key for consent service authentication
    public let appApiKey: String?

    /// Device ID (UUID for this device, auto-generated if not provided)
    public let deviceId: String?

    /// Platform identifier ("ios", "android")
    public let platform: String

    /// User ID (optional, for pseudonymous identification)
    public let userId: String?

    /// Region code (e.g., "US", "EU")
    public let region: String?

    public init(
        consentServiceUrl: String = ApiEndpoints.defaultConsentBaseUrl,
        appId: String? = nil,
        appApiKey: String? = nil,
        deviceId: String? = nil,
        platform: String = "ios",
        userId: String? = nil,
        region: String? = nil
    ) {
        self.consentServiceUrl = consentServiceUrl
        self.appId = appId
        self.appApiKey = appApiKey
        self.deviceId = deviceId
        self.platform = platform
        self.userId = userId
        self.region = region
    }

    /// Check if consent service is configured
    public var isConfigured: Bool {
        appId != nil && appApiKey != nil
    }
}
