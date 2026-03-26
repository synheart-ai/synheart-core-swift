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
    public static let ingestPath = "/ingest/v1/hsi"

    // MARK: - Platform Ingest
    public static let defaultPlatformIngestBaseUrl = "https://api.synheart.ai"
    public static let platformSessionIngestPath = "/platform/v1/session/ingest"
    public static let platformMetadataIngestPath = "/platform/v1/metadata/ingest"

    // MARK: - Consent Service
    public static let defaultConsentBaseUrl = "https://api.synheart.ai"

    public static func consentProfilesPath(appId: String) -> String {
        "/consent/v1/apps/\(appId)/consent-profiles"
    }
    public static let consentTokenPath = "/consent/v1/sdk/consent-token"
    public static let consentRevokePath = "/consent/v1/sdk/consent-revoke"
}
