import Foundation
import CryptoKit

/// Verifies capability tokens
class CapabilityVerifier {
    /// Verify the HMAC signature of a capability token
    func verifySignature(_ token: CapabilityToken, secret: String) -> Bool {
        let message = buildSignatureMessage(token)
        let key = SymmetricKey(data: Data(secret.utf8))

        let hmac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let expectedSignature = Data(hmac).base64EncodedString()

        return expectedSignature == token.signature
    }

    /// Check if token is expired
    func isExpired(_ token: CapabilityToken) -> Bool {
        return token.isExpired
    }

    /// Verify token validity (signature + expiration)
    func isValid(_ token: CapabilityToken, secret: String) -> Bool {
        return !isExpired(token) && verifySignature(token, secret: secret)
    }

    /// Parse capabilities from token
    func parse(_ token: CapabilityToken) throws -> SDKCapabilities {
        if isExpired(token) {
            throw CapabilityException("Capability token is expired")
        }

        return SDKCapabilities.fromToken(token)
    }

    /// Build the message for HMAC signature
    private func buildSignatureMessage(_ token: CapabilityToken) -> String {
        // Message format: orgId:projectId:environment:capabilities:issuedAt:expiresAt
        let jsonEncoder = JSONEncoder()
        let capabilitiesData = try? jsonEncoder.encode(token.capabilities)
        let capabilitiesStr = capabilitiesData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let issuedAtMs = Int64(token.issuedAt.timeIntervalSince1970 * 1000)
        let expiresAtMs = Int64(token.expiresAt.timeIntervalSince1970 * 1000)

        return "\(token.orgId):\(token.projectId):\(token.environment):\(capabilitiesStr):\(issuedAtMs):\(expiresAtMs)"
    }
}

/// Exception thrown when capability verification fails
public struct CapabilityException: Error, LocalizedError {
    public let message: String
    public let code: String?

    public init(_ message: String, code: String? = nil) {
        self.message = message
        self.code = code
    }

    public var errorDescription: String? {
        return "CapabilityException: \(message)"
    }
}
