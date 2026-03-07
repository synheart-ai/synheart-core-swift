import Foundation
import CryptoKit
import CommonCrypto

/// Handles encryption and decryption of artifact payloads.
///
/// Uses ChaChaPoly (ChaCha20-Poly1305) from CryptoKit.
/// v1 flow: JSON bytes → SHA-256 → AEAD encrypt.
///
/// See RFC-CORE-0004 Section 8.
public struct EncryptedPayload {
    public let ciphertext: Data
    public let sha256: String
    public let encAlg: String
}

public enum ArtifactCrypto {
    public static let encAlg = "chacha20poly1305"

    /// Encrypt an artifact's JSON representation.
    public static func encrypt(smk: SMK, json: [String: Any]) throws -> EncryptedPayload {
        let plaintext = try JSONSerialization.data(withJSONObject: json)

        // SHA-256 of plaintext (pre-encryption)
        let digest = SHA256.hash(data: plaintext)
        let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()

        // AEAD encrypt
        let key = SymmetricKey(data: smk.bytes)
        let sealedBox = try ChaChaPoly.seal(plaintext, using: key)

        // sealedBox.combined = nonce (12) || ciphertext || tag (16)
        let combined = sealedBox.combined

        return EncryptedPayload(
            ciphertext: combined,
            sha256: sha256Hex,
            encAlg: encAlg
        )
    }

    /// Encrypt raw data (e.g. plaintext bytes from a pulled artifact).
    public static func encryptData(smk: SMK, data plaintext: Data) throws -> EncryptedPayload {
        let digest = SHA256.hash(data: plaintext)
        let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()

        let key = SymmetricKey(data: smk.bytes)
        let sealedBox = try ChaChaPoly.seal(plaintext, using: key)

        return EncryptedPayload(
            ciphertext: sealedBox.combined,
            sha256: sha256Hex,
            encAlg: encAlg
        )
    }

    /// Decrypt an artifact payload back to a JSON dictionary.
    public static func decrypt(smk: SMK, combined: Data) throws -> [String: Any] {
        let key = SymmetricKey(data: smk.bytes)
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        let plaintext = try ChaChaPoly.open(sealedBox, using: key)

        guard let json = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            throw NSError(domain: "ArtifactCrypto", code: -1, userInfo: [NSLocalizedDescriptionKey: "Decrypted data is not a JSON object"])
        }
        return json
    }
}
