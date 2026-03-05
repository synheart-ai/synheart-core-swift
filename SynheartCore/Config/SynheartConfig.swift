import Foundation

/// Main configuration for Synheart SDK
public struct SynheartConfig {
    public let enableWear: Bool
    public let enablePhone: Bool
    public let enableBehavior: Bool
    public let cloudConfig: CloudConfig?

    /// Server-signed capability token for feature gating
    public let capabilityToken: CapabilityToken?

    /// HMAC secret for verifying the capability token signature
    public let capabilitySecret: String?

    /// When true, allows SDK to run with default capabilities and no signed token (debug only)
    public let allowUnsignedCapabilities: Bool

    public init(
        enableWear: Bool = true,
        enablePhone: Bool = true,
        enableBehavior: Bool = true,
        cloudConfig: CloudConfig? = nil,
        capabilityToken: CapabilityToken? = nil,
        capabilitySecret: String? = nil,
        allowUnsignedCapabilities: Bool = false
    ) {
        self.enableWear = enableWear
        self.enablePhone = enablePhone
        self.enableBehavior = enableBehavior
        self.cloudConfig = cloudConfig
        self.capabilityToken = capabilityToken
        self.capabilitySecret = capabilitySecret
        self.allowUnsignedCapabilities = allowUnsignedCapabilities
    }
}

/// Cloud Connector configuration
///
/// Required for cloud upload functionality.
///
/// Example:
/// ```swift
/// let cloudConfig = CloudConfig(
///     tenantId: "your_tenant_id",
///     hmacSecret: "your_hmac_secret",
///     subjectId: "pseudonymous_user_123",
///     instanceId: UUID().uuidString
/// )
/// ```
public struct CloudConfig {
    /// Base URL for Synheart Platform (default: production)
    public let baseUrl: String

    /// Tenant ID (from app registration)
    public let tenantId: String

    /// HMAC secret for signing requests (nil when authProvider is used)
    public let hmacSecret: String?

    /// Custom auth provider for request signing (e.g., ECDSA device-identity).
    /// When set, takes precedence over the HMAC path.
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
        tenantId: String,
        hmacSecret: String? = nil,
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
        precondition(
            hmacSecret != nil || authProvider != nil,
            "CloudConfig requires either hmacSecret or authProvider"
        )
        self.tenantId = tenantId
        self.hmacSecret = hmacSecret
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
