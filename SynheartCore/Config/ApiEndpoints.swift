import Foundation

/// Central registry of Synheart service paths.
///
/// Origins are deliberately empty by default. Applications that use cloud
/// services must provide their deployment origin through configuration. When
/// no origin is supplied, the SDK omits it from the native configuration and
/// lets the linked runtime apply its own policy.
public enum ApiEndpoints {
    // MARK: - Base URLs (defaults)
    public static let defaultCloudBaseUrl = ""
    public static let defaultAuthBaseUrl = ""

    // MARK: - Cloud / HSI Ingest
    public static let ingestPath = "/v1/hsi/ingest"

    // MARK: - Lab Ingest (lab/raw data)
    public static let defaultLabIngestBaseUrl = ""
    public static let labSessionIngestPath = "/v1/lab/session/ingest"
    public static let labMetadataIngestPath = "/v1/lab/metadata/ingest"

    // MARK: - Consent Service
    public static let defaultConsentBaseUrl = ""

    public static func consentProfilesPath(appId: String) -> String {
        "/v1/apps/\(appId)/consent-profiles"
    }
    public static let consentTokenPath = "/v1/sdk/consent-token"
    public static let consentRevokePath = "/v1/sdk/consent-revoke"
    public static let studyConsentPath = "/v1/sdk/study-consent"
}
