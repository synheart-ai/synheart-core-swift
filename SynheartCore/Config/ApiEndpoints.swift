import Foundation

/// Central registry of all Synheart API endpoints and default base URLs.
///
/// API paths are constants — they follow the server's versioned routes.
/// Base URLs have sensible production defaults but can be overridden
/// via ``CloudConfig``.
public enum ApiEndpoints {
    // MARK: - Base URLs (defaults)
    public static let defaultCloudBaseUrl = "https://api.synheart.ai"

    // MARK: - Cloud Ingest
    public static let ingestPath = "/v1/ingest/hsi"

    // MARK: - Platform Ingest
    public static let defaultPlatformIngestBaseUrl = "https://api.synheart.ai"
    public static let platformSessionIngestPath = "/v1/platform/session/ingest"
    public static let platformMetadataIngestPath = "/v1/platform/metadata/ingest"

    // MARK: - Consent Service
    public static let defaultConsentBaseUrl = "https://api.synheart.ai"

    public static func consentProfilesPath(appId: String) -> String {
        "/api/v1/apps/\(appId)/consent-profiles"
    }
    public static let consentTokenPath = "/api/v1/sdk/consent-token"
    public static let consentRevokePath = "/api/v1/sdk/consent-revoke"
}
