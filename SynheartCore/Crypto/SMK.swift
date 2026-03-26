import Foundation
import Security

/// Storage Master Key — 32-byte symmetric key for local encryption-at-rest.
///
/// Stored in the iOS/macOS Keychain. Never leaves the device.
/// See RFC-CORE-0004 Section 9.1.
public final class SMK {
    public static let keyLengthBytes = 32
    private static let keychainService = "ai.synheart.smk"
    private static let keychainAccount = "storage_master_key"

    public let bytes: Data

    private init(_ bytes: Data) {
        precondition(bytes.count == SMK.keyLengthBytes, "SMK must be \(SMK.keyLengthBytes) bytes")
        self.bytes = bytes
    }

    /// Load an existing SMK from Keychain or generate a new one.
    public static func loadOrCreate() throws -> SMK {
        if let existing = try loadFromKeychain() {
            return existing
        }
        let smk = generate()
        try saveToKeychain(smk.bytes)
        return smk
    }

    /// Generate a fresh 32-byte SMK using a secure random source.
    public static func generate() -> SMK {
        var bytes = Data(count: keyLengthBytes)
        let result = bytes.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, keyLengthBytes, ptr.baseAddress!)
        }
        precondition(result == errSecSuccess, "Failed to generate random bytes")
        return SMK(bytes)
    }

    /// Construct from raw bytes (e.g. for testing).
    public static func fromBytes(_ bytes: Data) -> SMK {
        SMK(bytes)
    }

    /// Delete the SMK from Keychain (irreversible).
    public static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain helpers

    private static func loadFromKeychain() throws -> SMK? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SynheartCoreError.cryptoKeyUnavailable
        }
        return SMK(data)
    }

    private static func saveToKeychain(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SynheartCoreError.cryptoKeyUnavailable
        }
    }
}
