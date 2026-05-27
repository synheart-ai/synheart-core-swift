import Foundation
import Security

/// Secure storage for consent tokens and profiles using iOS Keychain
public class ConsentTokenStorage {
    private static let tokenKey = "synheart_consent_token"
    private static let profilesCacheKey = "synheart_consent_profiles_cache"
    private static let profilesCacheTimestampKey = "synheart_consent_profiles_cache_ts"
    private static let profilesCacheTTL: TimeInterval = 24 * 60 * 60 // 24 hours

    private let service = "ai.synheart.consent"

    public init() {}

    // MARK: - Token Storage

    /// Save consent token
    public func saveToken(_ token: ConsentToken) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(token)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ConsentTokenStorageError.encodingFailed
        }
        try save(key: Self.tokenKey, value: jsonString)
    }

    /// Load consent token
    public func loadToken() -> ConsentToken? {
        do {
            guard let jsonString = try load(key: Self.tokenKey) else {
                return nil
            }
            guard let data = jsonString.data(using: .utf8) else {
                return nil
            }
            let decoder = JSONDecoder()
            return try decoder.decode(ConsentToken.self, from: data)
        } catch {
            SynheartLogger.log("[ConsentTokenStorage] Error loading token: \(error)")
            return nil
        }
    }

    /// Delete consent token
    public func deleteToken() {
        delete(key: Self.tokenKey)
    }

    /// Check if a valid token exists
    public func hasToken() -> Bool {
        guard let token = loadToken() else { return false }
        return token.isValid
    }

    // MARK: - Profile Cache

    /// Cache consent profiles
    public func cacheProfiles(_ profiles: [ConsentProfile]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(profiles)
            guard let jsonString = String(data: data, encoding: .utf8) else { return }
            try save(key: Self.profilesCacheKey, value: jsonString)

            let formatter = ISO8601DateFormatter()
            let timestamp = formatter.string(from: Date())
            try save(key: Self.profilesCacheTimestampKey, value: timestamp)
        } catch {
            SynheartLogger.log("[ConsentTokenStorage] Error caching profiles: \(error)")
        }
    }

    /// Load cached consent profiles (if not expired)
    public func loadCachedProfiles() -> [ConsentProfile]? {
        do {
            guard let timestampStr = try load(key: Self.profilesCacheTimestampKey) else {
                return nil
            }

            let formatter = ISO8601DateFormatter()
            guard let timestamp = formatter.date(from: timestampStr) else {
                return nil
            }

            let age = Date().timeIntervalSince(timestamp)
            if age > Self.profilesCacheTTL {
                // Cache expired
                clearProfilesCache()
                return nil
            }

            guard let profilesJsonString = try load(key: Self.profilesCacheKey) else {
                return nil
            }
            guard let data = profilesJsonString.data(using: .utf8) else {
                return nil
            }

            let decoder = JSONDecoder()
            return try decoder.decode([ConsentProfile].self, from: data)
        } catch {
            SynheartLogger.log("[ConsentTokenStorage] Error loading cached profiles: \(error)")
            return nil
        }
    }

    /// Clear profiles cache
    public func clearProfilesCache() {
        delete(key: Self.profilesCacheKey)
        delete(key: Self.profilesCacheTimestampKey)
    }

    /// Clear all consent data
    public func clearAll() {
        deleteToken()
        clearProfilesCache()
    }

    // MARK: - Keychain Helpers

    private func save(key: String, value: String) throws {
        let data = Data(value.utf8)
        delete(key: key) // Remove existing before insert

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConsentTokenStorageError.saveFailed(status)
        }
    }

    private func load(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }

        guard status == errSecSuccess, let data = result as? Data else {
            throw ConsentTokenStorageError.loadFailed(status)
        }

        return String(data: data, encoding: .utf8)
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Errors that can occur during consent token storage operations
public enum ConsentTokenStorageError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save consent token: \(status)"
        case .loadFailed(let status):
            return "Failed to load consent token: \(status)"
        case .encodingFailed:
            return "Failed to encode consent token"
        }
    }
}
