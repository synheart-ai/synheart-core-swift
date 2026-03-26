import Foundation
import Security

/// Encrypted storage for consent snapshots using iOS Keychain
public class ConsentStorage {
    private static let storageKey = "synheart_consent_snapshot"
    private let service = "ai.synheart.hsi"
    
    public init() {
    }

    /// Save consent snapshot (encrypted via Keychain)
    func save(_ consent: ConsentSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(consent)

        // Delete existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.storageKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.storageKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConsentStorageError.saveFailed(status)
        }
    }

    /// Load consent snapshot from Keychain
    func load() throws -> ConsentSnapshot? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.storageKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw ConsentStorageError.loadFailed(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConsentSnapshot.self, from: data)
    }

    /// Clear consent data
    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.storageKey
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ConsentStorageError.deleteFailed(status)
        }
    }

    /// Check if consent data exists
    func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.storageKey,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

/// Errors that can occur during consent storage operations
enum ConsentStorageError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var localizedDescription: String {
        switch self {
        case .saveFailed(let status):
            return "Failed to save consent: \(status)"
        case .loadFailed(let status):
            return "Failed to load consent: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete consent: \(status)"
        }
    }
}
