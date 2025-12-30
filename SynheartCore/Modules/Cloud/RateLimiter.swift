import Foundation

/// Client-side rate limiter for cloud uploads
///
/// Rate limits are per window type:
/// - micro: 30 seconds
/// - short: 2 minutes
/// - medium: 10 minutes
/// - long: 1 hour
///
/// Batch sizes vary by capability level:
/// - core: 10
/// - extended: 50
/// - research: 200
public actor RateLimiter {
    private let capabilityProvider: CapabilityProvider
    private var lastUpload: [String: Date] = [:]

    // Upload frequency per window type (from CLOUD_PROTOCOL.md)
    private static let uploadIntervals: [String: TimeInterval] = [
        "micro": 30,      // 30 seconds
        "short": 120,     // 2 minutes
        "medium": 600,    // 10 minutes
        "long": 3600      // 1 hour
    ]

    public init(capabilityProvider: CapabilityProvider) {
        self.capabilityProvider = capabilityProvider
    }

    /// Get batch size based on capability level
    public var batchSize: Int {
        let level = capabilityProvider.capability(.cloud)
        switch level {
        case .core:
            return 10
        case .extended:
            return 50
        case .research:
            return 200
        default:
            return 10
        }
    }

    /// Check if upload is allowed for this window type
    ///
    /// - Parameter windowType: Window type (micro, short, medium, long)
    /// - Returns: true if upload is allowed, false if rate limited
    public func canUpload(_ windowType: String) -> Bool {
        guard let interval = Self.uploadIntervals[windowType] else {
            return true // Unknown window type - allow (fail-open)
        }

        guard let lastUploadTime = lastUpload[windowType] else {
            return true // Never uploaded before
        }

        let elapsed = Date().timeIntervalSince(lastUploadTime)
        return elapsed >= interval
    }

    /// Record an upload for rate limiting
    ///
    /// - Parameters:
    ///   - windowType: Window type that was uploaded
    ///   - batchSize: Number of items in the batch (for logging/metrics)
    public func recordUpload(_ windowType: String, batchSize: Int) {
        lastUpload[windowType] = Date()
    }
}
