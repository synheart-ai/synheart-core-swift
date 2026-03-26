import Foundation
import CryptoKit
import Security

/// User Root Key management for E2EE sync (RFC-CORE-0005 §3).
///
/// URK is a 32-byte key used to derive per-artifact encryption keys for sync.
public final class URK {
    public static let keyLengthBytes = 32
    private static let keychainService = "ai.synheart.urk"
    private static let wrappedAccount = "urk_wrapped"
    private static let kekAccount = "urk_kek"
    private static let bundleKdfInfo = "synheart-urk-bundle:v1"
    private static let syncKdfInfo = "synheart-sync:v1"

    public let bytes: Data

    private init(_ bytes: Data) {
        precondition(bytes.count == URK.keyLengthBytes, "URK must be \(URK.keyLengthBytes) bytes")
        self.bytes = bytes
    }

    /// Generate a fresh 32-byte URK.
    public static func generate() -> URK {
        var bytes = Data(count: keyLengthBytes)
        let result = bytes.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, keyLengthBytes, ptr.baseAddress!)
        }
        precondition(result == errSecSuccess)
        return URK(bytes)
    }

    /// Construct from raw bytes.
    public static func fromBytes(_ bytes: Data) -> URK {
        URK(bytes)
    }

    /// Derive a Bundle Encryption Key from the auth session secret.
    public static func deriveBEK(sessionSecret: String, subjectId: String) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(sessionSecret.utf8))
        let salt = Data(subjectId.utf8)
        let info = Data(bundleKdfInfo.utf8)
        return deriveKey(inputKey: inputKey, salt: salt, info: info)
    }

    /// Derive a per-artifact encryption key for sync.
    public static func deriveArtifactKey(urk: Data, artifactId: String) -> SymmetricKey {
        let inputKey = SymmetricKey(data: urk)
        let salt = Data(artifactId.utf8)
        let info = Data(syncKdfInfo.utf8)
        return deriveKey(inputKey: inputKey, salt: salt, info: info)
    }

    /// Encrypt URK for cloud storage as a bundle.
    public static func encryptBundle(urk: Data, sessionSecret: String, subjectId: String) throws -> [String: String] {
        let bek = deriveBEK(sessionSecret: sessionSecret, subjectId: subjectId)
        let sealedBox = try ChaChaPoly.seal(urk, using: bek)
        let combined = sealedBox.combined

        // ChaChaPoly.combined = nonce(12) || ciphertext || tag(16)
        let nonce = combined.prefix(12)
        let ctAndTag = combined.dropFirst(12)

        return [
            "urk_bundle_version": "1",
            "ciphertext_b64": ctAndTag.base64EncodedString(),
            "nonce_b64": nonce.base64EncodedString(),
            "kdf_info": bundleKdfInfo,
        ]
    }

    /// Decrypt a URK bundle downloaded from the server.
    public static func decryptBundle(bundle: [String: Any], sessionSecret: String, subjectId: String) throws -> URK {
        let bek = deriveBEK(sessionSecret: sessionSecret, subjectId: subjectId)
        let ctAndTag = Data(base64Encoded: bundle["ciphertext_b64"] as! String)!
        let nonce = Data(base64Encoded: bundle["nonce_b64"] as! String)!

        // Reconstruct combined format: nonce || ciphertext || tag
        var combined = Data()
        combined.append(nonce)
        combined.append(ctAndTag)

        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        let plaintext = try ChaChaPoly.open(sealedBox, using: bek)

        return URK(plaintext)
    }

    /// Wrap and store URK locally using a KEK in Keychain.
    public func wrapAndStore() throws {
        // Get or create KEK
        let kek: SymmetricKey
        if let existing = try URK.loadKeychainData(account: URK.kekAccount) {
            kek = SymmetricKey(data: existing)
        } else {
            kek = SymmetricKey(size: .bits256)
            try saveKeychainData(kek.withUnsafeBytes { Data($0) }, account: URK.kekAccount)
        }

        let sealedBox = try ChaChaPoly.seal(bytes, using: kek)
        try saveKeychainData(sealedBox.combined, account: URK.wrappedAccount)
    }

    /// Unwrap URK from local Keychain storage.
    public static func unwrap() throws -> URK? {
        guard let wrapped = try loadKeychainData(account: wrappedAccount),
              let kekData = try loadKeychainData(account: kekAccount) else {
            return nil
        }

        let kek = SymmetricKey(data: kekData)
        let sealedBox = try ChaChaPoly.SealedBox(combined: wrapped)
        let plaintext = try ChaChaPoly.open(sealedBox, using: kek)

        return URK(plaintext)
    }

    /// Delete URK and KEK from Keychain.
    public static func delete() {
        deleteKeychainData(account: wrappedAccount)
        deleteKeychainData(account: kekAccount)
    }

    // MARK: - HKDF

    private static func deriveKey(inputKey: SymmetricKey, salt: Data, info: Data) -> SymmetricKey {
        let prk = inputKey.withUnsafeBytes { ikm -> SymmetricKey in
            let key = HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: salt))
            return SymmetricKey(data: Data(key))
        }

        // HKDF-Expand
        var okm = Data()
        var t = Data()
        var counter: UInt8 = 1
        while okm.count < keyLengthBytes {
            var input = t
            input.append(info)
            input.append(counter)
            let block = HMAC<SHA256>.authenticationCode(for: input, using: prk)
            t = Data(block)
            okm.append(t)
            counter += 1
        }
        return SymmetricKey(data: okm.prefix(keyLengthBytes))
    }

    // MARK: - Keychain helpers

    private static func loadKeychainData(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SynheartCoreError.cryptoKeyUnavailable
        }
        return data
    }

    private func saveKeychainData(_ data: Data, account: String) throws {
        URK.deleteKeychainData(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: URK.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SynheartCoreError.cryptoKeyUnavailable
        }
    }

    private static func deleteKeychainData(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
