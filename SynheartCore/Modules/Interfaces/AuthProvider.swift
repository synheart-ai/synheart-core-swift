import Foundation

/// Protocol for pluggable request authentication.
///
/// Implementations sign outgoing HTTP requests with custom auth schemes
/// (e.g., ECDSA device-identity signing from synheart-auth).
///
/// The SDK ships with HMAC-SHA256 as the default. When an ``AuthProvider``
/// is set on ``CloudConfig``, it takes precedence over the HMAC path.
public protocol AuthProvider: AnyObject {
    /// Sign an outgoing request and return headers to attach.
    ///
    /// The returned dictionary is merged into the HTTP request headers.
    /// Typical headers: `Authorization`, `X-Device-Signature`, etc.
    ///
    /// - Parameters:
    ///   - method: HTTP method (e.g., "POST")
    ///   - path: Request path (e.g., "/ingest/v1/hsi")
    ///   - bodyBytes: Serialized request body
    /// - Returns: Header name-value pairs to attach to the request
    /// - Throws: If signing fails (e.g., keychain unavailable)
    func signRequest(method: String, path: String, bodyBytes: Data) throws -> [String: String]

    /// Called when the server returns a 401 for a request signed by this provider.
    ///
    /// Return `true` if the error was handled (e.g., key rotation completed)
    /// and the request should be retried. Return `false` to propagate the error.
    ///
    /// - Parameters:
    ///   - statusCode: HTTP status code (always 401)
    ///   - responseHeaders: Response headers from the server
    /// - Returns: Whether the error was handled and the request should be retried
    func onAuthError(statusCode: Int, responseHeaders: [String: String]) -> Bool
}
