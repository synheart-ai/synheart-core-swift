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
}
