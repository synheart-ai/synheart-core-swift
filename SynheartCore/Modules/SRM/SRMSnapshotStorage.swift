import Foundation
import Security

/// Encrypted storage for SRM snapshots using iOS Keychain.
///
/// Mirrors the ConsentStorage pattern — Keychain with
/// `kSecAttrAccessibleAfterFirstUnlock`.
public class SRMSnapshotStorage {
    private let service = "ai.synheart.hsi"
    private let account = "synheart_srm_snapshot"

    public init() {}

    /// Save SRM snapshot (encrypted via Keychain)
    public func save(_ snapshot: SRMSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        // Delete existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SRMSnapshotStorageError.saveFailed(status)
        }
    }

    /// Load SRM snapshot from Keychain
    public func load() throws -> SRMSnapshot? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            return nil
        }

        guard status == errSecSuccess else {
            throw SRMSnapshotStorageError.loadFailed(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SRMSnapshot.self, from: data)
    }

    /// Clear SRM snapshot data
    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SRMSnapshotStorageError.deleteFailed(status)
        }
    }
}

/// Errors that can occur during SRM snapshot storage operations
public enum SRMSnapshotStorageError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var localizedDescription: String {
        switch self {
        case .saveFailed(let status):
            return "Failed to save SRM snapshot: \(status)"
        case .loadFailed(let status):
            return "Failed to load SRM snapshot: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete SRM snapshot: \(status)"
        }
    }
}
