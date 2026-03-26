import Foundation

/// Protocol for SynheartAuth device-identity signing
///
/// Wraps the native SynheartAuth library. Consumers provide an implementation
/// that bridges to the actual SynheartAuth SDK.
public protocol SynheartAuthProvider: AnyObject {
    /// Sign a request with device identity
    func signRequest(
        appId: String,
        method: String,
        path: String,
        bodyBytes: Data
    ) async throws -> [String: String]

    /// Correct clock skew based on server timestamp
    func correctClockSkew(_ serverTimestamp: Double) async throws

    /// Rotate signing key for the given app
    func rotateKey(_ appId: String) async throws -> KeyRotationResult
}

/// Result of a key rotation attempt
public enum KeyRotationResult {
    case success
    case failure
}

/// AuthProvider backed by SynheartAuth device-identity signing.
///
/// Wraps SynheartAuth.signRequest to produce the signed header set
/// (X-App-ID, X-Device-ID, X-Synheart-Signature, etc.) for every
/// outgoing request to cloud and platform ingest services.
public class DeviceAuthProvider: AuthProvider {
    private let auth: SynheartAuthProvider
    private let appId: String

    public init(appId: String, auth: SynheartAuthProvider) {
        self.appId = appId
        self.auth = auth
    }

    public func signRequest(method: String, path: String, bodyBytes: Data) throws -> [String: String] {
        // Bridge async SynheartAuth to sync AuthProvider protocol
        // Use a semaphore since AuthProvider.signRequest is synchronous in Swift
        var result: [String: String]?
        var signError: Error?

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                result = try await auth.signRequest(
                    appId: appId,
                    method: method,
                    path: path,
                    bodyBytes: bodyBytes
                )
            } catch {
                signError = error
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let signError = signError {
            throw signError
        }

        return result ?? [:]
    }

    public func onAuthError(statusCode: Int, responseHeaders: [String: String]) -> Bool {
        // Handle clock skew -- server sends its timestamp so we can correct drift.
        if let serverTs = responseHeaders["x-server-timestamp"],
           let ts = Double(serverTs) {
            let semaphore = DispatchSemaphore(value: 0)
            var handled = false
            Task {
                do {
                    try await auth.correctClockSkew(ts)
                    SynheartLogger.log("[DeviceAuth] Clock skew corrected, retrying")
                    handled = true
                } catch {
                    SynheartLogger.log("[DeviceAuth] Clock skew correction failed: \(error)")
                }
                semaphore.signal()
            }
            semaphore.wait()
            if handled { return true }
        }

        // Handle key invalidation -- rotate and retry.
        if responseHeaders["x-synheart-error"] == "KEY_INVALIDATED" {
            let semaphore = DispatchSemaphore(value: 0)
            var handled = false
            Task {
                do {
                    let rotationResult = try await auth.rotateKey(appId)
                    if rotationResult == .success {
                        SynheartLogger.log("[DeviceAuth] Key rotated, retrying")
                        handled = true
                    }
                } catch {
                    SynheartLogger.log("[DeviceAuth] Key rotation failed: \(error)")
                }
                semaphore.signal()
            }
            semaphore.wait()
            if handled { return true }
        }

        return false
    }
}
