import Foundation

/// JWT consent token issued by consent service
public struct ConsentToken: Codable {
    /// JWT token string
    public let token: String

    /// Token expiration time
    public let expiresAt: Date

    /// Consent profile ID that this token was issued for
    public let profileId: String

    /// Token scopes (e.g., ["bio:vitals", "cloud:upload"])
    public let scopes: [String]

    /// Decoded JWT claims (for validation)
    public let claims: [String: AnyCodable]

    public init(
        token: String,
        expiresAt: Date,
        profileId: String,
        scopes: [String],
        claims: [String: AnyCodable]
    ) {
        self.token = token
        self.expiresAt = expiresAt
        self.profileId = profileId
        self.scopes = scopes
        self.claims = claims
    }

    /// Check if token is expired
    public var isExpired: Bool {
        Date() > expiresAt
    }

    /// Check if token is valid (not expired)
    public var isValid: Bool {
        !isExpired
    }

    /// Check if token expires soon (within specified duration)
    public func expiresSoon(threshold: TimeInterval = 300) -> Bool {
        expiresAt.timeIntervalSinceNow <= threshold
    }

    // MARK: - JSON Parsing (API response)

    /// Create from JSON API response
    ///
    /// Supports multiple API response formats:
    /// 1. RFC format: { "token": "...", "expires_at": "2026-01-10T19:00:00Z", "profile_id": "...", "scopes": [...] }
    /// 2. Actual API format: { "access_token": "...", "expires_in": 86400, "consent_profile_id": "...", "token_type": "Bearer" }
    public static func fromAPIResponse(_ json: [String: Any]) throws -> ConsentToken {
        // Extract token (required field)
        guard let tokenValue = json["token"] as? String ?? json["access_token"] as? String else {
            let keys = json.keys.joined(separator: ", ")
            throw ConsentTokenError.missingField(
                "Missing required field \"token\" or \"access_token\". Available keys: \(keys)"
            )
        }

        // Extract expiration time
        let expiresAt: Date
        if let expiresAtStr = json["expires_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: expiresAtStr) {
                expiresAt = date
            } else {
                // Try without fractional seconds
                let basic = ISO8601DateFormatter()
                guard let date = basic.date(from: expiresAtStr) else {
                    throw ConsentTokenError.invalidFormat("Cannot parse expires_at: \(expiresAtStr)")
                }
                expiresAt = date
            }
        } else if let expiresIn = json["expires_in"] as? Int {
            expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            let keys = json.keys.joined(separator: ", ")
            throw ConsentTokenError.missingField(
                "Missing required field \"expires_at\" or \"expires_in\". Available keys: \(keys)"
            )
        }

        // Decode JWT to extract claims
        let parts = tokenValue.split(separator: ".")
        guard parts.count == 3 else {
            throw ConsentTokenError.invalidFormat("Invalid JWT format")
        }

        let payload = String(parts[1])
        let claims = try decodeJWTPayload(payload)

        // Extract profile ID
        let profileId = json["profile_id"] as? String
            ?? json["consent_profile_id"] as? String
            ?? claims["profile_id"] as? String
            ?? claims["consent_profile_id"] as? String
            ?? ""

        // Extract scopes
        let scopes: [String]
        if let jsonScopes = json["scopes"] as? [String] {
            scopes = jsonScopes
        } else if let claimsScopes = claims["scopes"] as? [String] {
            scopes = claimsScopes
        } else {
            scopes = []
        }

        let codableClaims = claims.mapValues { AnyCodable($0) }

        return ConsentToken(
            token: tokenValue,
            expiresAt: expiresAt,
            profileId: profileId,
            scopes: scopes,
            claims: codableClaims
        )
    }

    /// Decode base64url-encoded JWT payload
    private static func decodeJWTPayload(_ payload: String) throws -> [String: Any] {
        // Pad base64url string
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else {
            throw ConsentTokenError.invalidFormat("Failed to decode JWT payload")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConsentTokenError.invalidFormat("JWT payload is not a valid JSON object")
        }

        return json
    }

    // MARK: - Codable (for storage)

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case profileId = "profile_id"
        case scopes
        case claims
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)

        let expiresAtString = try container.decode(String.self, forKey: .expiresAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAtString) {
            expiresAt = date
        } else {
            let basic = ISO8601DateFormatter()
            guard let date = basic.date(from: expiresAtString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .expiresAt,
                    in: container,
                    debugDescription: "Cannot parse date: \(expiresAtString)"
                )
            }
            expiresAt = date
        }

        profileId = try container.decode(String.self, forKey: .profileId)
        scopes = try container.decode([String].self, forKey: .scopes)
        claims = try container.decode([String: AnyCodable].self, forKey: .claims)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: expiresAt), forKey: .expiresAt)
        try container.encode(profileId, forKey: .profileId)
        try container.encode(scopes, forKey: .scopes)
        try container.encode(claims, forKey: .claims)
    }
}

/// Consent status enumeration
public enum ConsentStatus {
    /// Consent granted with valid token
    case granted

    /// Consent pending (user hasn't responded)
    case pending

    /// Consent denied by user
    case denied

    /// Token expired
    case expired
}

/// Errors related to consent token parsing
public enum ConsentTokenError: Error, LocalizedError {
    case missingField(String)
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .missingField(let message):
            return "ConsentTokenError: \(message)"
        case .invalidFormat(let message):
            return "ConsentTokenError: \(message)"
        }
    }
}
