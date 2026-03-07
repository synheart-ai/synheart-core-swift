import Foundation
import Security

/// Secure token storage using iOS/macOS Keychain (RFC-CORE-0008 §1.5).
public class TokenStorage {
    private static let service = "com.synheart.auth"

    private enum Key: String {
        case refreshToken = "refresh_token"
        case subjectId = "subject_id"
        case sessionSecret = "session_secret"
    }

    public init() {}

    func saveRefreshToken(_ token: String) throws {
        try save(key: .refreshToken, value: token)
    }

    func loadRefreshToken() throws -> String? {
        try load(key: .refreshToken)
    }

    func saveSubjectId(_ id: String) throws {
        try save(key: .subjectId, value: id)
    }

    func loadSubjectId() throws -> String? {
        try load(key: .subjectId)
    }

    func saveSessionSecret(_ secret: String) throws {
        try save(key: .sessionSecret, value: secret)
    }

    func loadSessionSecret() throws -> String? {
        try load(key: .sessionSecret)
    }

    func clearAll() {
        for key in [Key.refreshToken, .subjectId, .sessionSecret] {
            delete(key: key)
        }
    }

    // MARK: - Keychain helpers

    private func save(key: Key, value: String) throws {
        let data = Data(value.utf8)
        delete(key: key) // Remove existing before insert

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: TokenStorage.service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "TokenStorage", code: Int(status))
        }
    }

    private func load(key: Key) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: TokenStorage.service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: "TokenStorage", code: Int(status))
        }
        return String(data: data, encoding: .utf8)
    }

    private func delete(key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: TokenStorage.service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
