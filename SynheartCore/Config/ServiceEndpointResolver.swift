import Foundation

struct ServiceEndpoints: Equatable {
    let platformBaseURL: String
    let authBaseURL: String
    let consentBaseURL: String
    let syncBaseURL: String
}

/// Resolves service origins once so native ingest, authentication, consent, and
/// sync cannot silently target different environments.
enum ServiceEndpointResolver {
    static func resolve(_ config: SynheartConfig) -> ServiceEndpoints {
        let cloud = normalized(config.cloudConfig?.baseUrl)
        let configuredSync = normalized(config.sync.baseUrl)
        let syncIsDefault = configuredSync == nil
            || configuredSync == normalized(ApiEndpoints.defaultAuthBaseUrl)

        let platform = (!syncIsDefault ? configuredSync : cloud)
            ?? normalized(ApiEndpoints.defaultCloudBaseUrl)!

        return ServiceEndpoints(
            platformBaseURL: platform,
            authBaseURL: normalized(config.deviceAuthConfig?.authBaseUrl) ?? platform,
            consentBaseURL: normalized(config.consentConfig?.consentServiceUrl) ?? platform,
            syncBaseURL: platform
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }
}
