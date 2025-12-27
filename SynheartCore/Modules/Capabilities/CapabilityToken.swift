import Foundation

/// Capability token received from authentication service
public struct CapabilityToken: Codable {
    /// Organization ID
    public let orgId: String

    /// Project ID
    public let projectId: String

    /// Environment (dev, staging, production)
    public let environment: String

    /// Capability levels per module
    public let capabilities: [String: String]

    /// HMAC signature for verification
    public let signature: String

    /// Token expiration timestamp
    public let expiresAt: Date

    /// Token issue timestamp
    public let issuedAt: Date

    public init(
        orgId: String,
        projectId: String,
        environment: String,
        capabilities: [String: String],
        signature: String,
        expiresAt: Date,
        issuedAt: Date
    ) {
        self.orgId = orgId
        self.projectId = projectId
        self.environment = environment
        self.capabilities = capabilities
        self.signature = signature
        self.expiresAt = expiresAt
        self.issuedAt = issuedAt
    }

    /// Check if token is expired
    public var isExpired: Bool {
        return Date() > expiresAt
    }

    /// Check if token is valid (not expired and issued in past)
    public var isValid: Bool {
        let now = Date()
        return !isExpired && now > issuedAt && expiresAt > issuedAt
    }

    private enum CodingKeys: String, CodingKey {
        case orgId = "org_id"
        case projectId = "project_id"
        case environment
        case capabilities
        case signature
        case expiresAt = "expires_at"
        case issuedAt = "issued_at"
    }
}

/// SDK capabilities parsed from token
public struct SDKCapabilities {
    /// Behavior module capability level
    public let behavior: CapabilityLevel

    /// Wear module capability level
    public let wear: CapabilityLevel

    /// Phone module capability level
    public let phone: CapabilityLevel

    /// HSI module capability level
    public let hsi: CapabilityLevel

    /// Cloud module capability level
    public let cloud: CapabilityLevel

    public init(
        behavior: CapabilityLevel,
        wear: CapabilityLevel,
        phone: CapabilityLevel,
        hsi: CapabilityLevel,
        cloud: CapabilityLevel
    ) {
        self.behavior = behavior
        self.wear = wear
        self.phone = phone
        self.hsi = hsi
        self.cloud = cloud
    }

    /// Get capability level for a module
    public func getLevel(_ module: Module) -> CapabilityLevel {
        switch module {
        case .behavior:
            return behavior
        case .wear:
            return wear
        case .phone:
            return phone
        case .hsi:
            return hsi
        case .cloud:
            return cloud
        }
    }

    /// Create capabilities from token
    public static func fromToken(_ token: CapabilityToken) -> SDKCapabilities {
        return SDKCapabilities(
            behavior: parseLevel(token.capabilities["behavior"]),
            wear: parseLevel(token.capabilities["wear"]),
            phone: parseLevel(token.capabilities["phone"]),
            hsi: parseLevel(token.capabilities["hsi"]),
            cloud: parseLevel(token.capabilities["cloud"])
        )
    }

    /// Parse capability level from string
    private static func parseLevel(_ level: String?) -> CapabilityLevel {
        guard let level = level?.lowercased() else {
            return .none
        }

        switch level {
        case "core":
            return .core
        case "extended":
            return .extended
        case "research":
            return .research
        default:
            return .none
        }
    }

    /// Create default capabilities (core level for all modules)
    public static func defaultCapabilities() -> SDKCapabilities {
        return SDKCapabilities(
            behavior: .core,
            wear: .core,
            phone: .core,
            hsi: .core,
            cloud: .core
        )
    }
}
