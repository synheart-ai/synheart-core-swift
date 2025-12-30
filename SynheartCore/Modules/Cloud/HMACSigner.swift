import Foundation
import CryptoKit

/// HMAC-SHA256 signature generator with time-windowed nonces
///
/// Implements the Synheart Cloud Protocol authentication scheme.
///
/// Nonce format: `<unix_timestamp>_<random_hex>`
/// Signing string format (newline-separated):
/// ```
/// METHOD
/// PATH
/// TENANT_ID
/// TIMESTAMP
/// NONCE
/// SHA256(body_json)
/// ```
public class HMACSigner {
    private let hmacSecret: String

    public init(hmacSecret: String) {
        self.hmacSecret = hmacSecret
    }

    /// Generate time-windowed nonce
    ///
    /// Format: `<unix_timestamp>_<random_hex>`
    ///
    /// Example: `1704067200_a3b5c7d9e1f2`
    public func generateNonce() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomBytes = (0..<12).map { _ in UInt8.random(in: 0...255) }
        let randomHex = randomBytes.map { String(format: "%02x", $0) }.joined()
        return "\(timestamp)_\(randomHex)"
    }

    /// Compute HMAC-SHA256 signature
    ///
    /// - Parameters:
    ///   - method: HTTP method (e.g., "POST")
    ///   - path: Request path (e.g., "/v1/ingest/hsi")
    ///   - tenantId: Tenant identifier
    ///   - timestamp: Unix timestamp (seconds)
    ///   - nonce: Time-windowed nonce
    ///   - bodyJson: JSON body as string
    /// - Returns: Hex-encoded HMAC-SHA256 signature
    public func computeSignature(
        method: String,
        path: String,
        tenantId: String,
        timestamp: Int,
        nonce: String,
        bodyJson: String
    ) -> String {
        // Compute SHA256 of body
        let bodyHash = sha256(bodyJson)

        // Construct signing string (newline-separated)
        let signingString = [
            method.uppercased(),
            path,
            tenantId,
            "\(timestamp)",
            nonce,
            bodyHash
        ].joined(separator: "\n")

        // Compute HMAC-SHA256
        let key = SymmetricKey(data: Data(hmacSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(signingString.utf8),
            using: key
        )

        return signature.map { String(format: "%02x", $0) }.joined()
    }

    /// Compute SHA256 hash of input string
    private func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
