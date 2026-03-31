import Foundation

/// Central registry of all Synheart API endpoints.
///
/// Service paths are within each service (after gateway routing).
/// Base URLs resolve to: gateway (api.synheart.ai/{service}) or direct ({service}-dev.synheart.io)
public enum ApiEndpoints {
    // MARK: - Base URLs (defaults)
    public static let defaultCloudBaseUrl = "https://api.synheart.ai"

    // MARK: - Cloud / HSI Ingest
    public static let ingestPath = "/v1/hsi/ingest"

    // MARK: - Lab Ingest (lab/raw data)
    public static let defaultLabIngestBaseUrl = "https://api.synheart.ai"
    public static let labSessionIngestPath = "/v1/lab/session/ingest"
    public static let labMetadataIngestPath = "/v1/lab/metadata/ingest"

    // MARK: - Consent Service
    public static let defaultConsentBaseUrl = "https://api.synheart.ai"

    public static func consentProfilesPath(appId: String) -> String {
        "/v1/apps/\(appId)/consent-profiles"
    }
    public static let consentTokenPath = "/v1/sdk/consent-token"
    public static let consentRevokePath = "/v1/sdk/consent-revoke"
}
