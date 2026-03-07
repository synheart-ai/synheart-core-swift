import Foundation

/// Configuration for the Platform Ingest module.
///
/// Used to send custom session and metadata payloads to the
/// Synheart platform ingestion service.
///
/// Example:
/// ```swift
/// let platformIngestConfig = PlatformIngestConfig(
///     apiKey: "synheart_sk_live_...",
///     hmacSecret: "synheart_whsec_..."
/// )
/// ```
public struct PlatformIngestConfig {
    /// Base URL for the platform ingestion service.
    public let baseUrl: String

    /// API key for authentication (X-API-Key header).
    public let apiKey: String

    /// HMAC secret for request signing.
    public let hmacSecret: String

    /// HTTP request timeout (default: 30 seconds).
    public let timeout: TimeInterval

    /// Maximum retry attempts for failed requests.
    public let maxRetries: Int

    /// When true, automatically ingest session data when a session stops.
    public let autoIngest: Bool

    public init(
        apiKey: String,
        hmacSecret: String,
        baseUrl: String = ApiEndpoints.defaultPlatformIngestBaseUrl,
        timeout: TimeInterval = 30,
        maxRetries: Int = 3,
        autoIngest: Bool = false
    ) {
        self.apiKey = apiKey
        self.hmacSecret = hmacSecret
        self.baseUrl = baseUrl
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.autoIngest = autoIngest
    }
}
