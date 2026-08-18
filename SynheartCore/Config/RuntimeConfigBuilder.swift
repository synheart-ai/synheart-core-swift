import Foundation

/// Builds the JSON object passed to `synheart_core_new`.
///
/// Keep all native-handle creation paths on this builder. In particular,
/// cloud ingest must remain disabled until an organization is configured, and
/// device authentication must remain disabled until its service configuration
/// is present.
enum RuntimeConfigBuilder {
    static func build(
        _ config: SynheartConfig,
        dataDir: String? = nil
    ) -> [String: Any] {
        let orgId = config.cloudConfig?.orgId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cloudReady = !orgId.isEmpty
        let deviceAuth = config.deviceAuthConfig
        let resolvedApiBaseUrl = config.sync.baseUrl.isEmpty
            ? ApiEndpoints.defaultAuthBaseUrl
            : config.sync.baseUrl

        var result: [String: Any] = [
            "app_id": config.appId,
            "org_id": orgId,
            "subject_id": config.subjectId,
            "client_id": config.subjectId,
            "api_base_url": resolvedApiBaseUrl,
            "mode": config.mode.rawValue,
            "device_id": config.deviceId,
            "app_version": config.appVersion,
            "platform": config.platform,
            "storage": [
                "enabled": config.storage.enabled,
            ],
            "ingest": [
                "enabled": cloudReady,
                "hsi": cloudReady,
                "lab": cloudReady,
            ],
            "device_auth": [
                "enabled": deviceAuth != nil,
                "auth_base_url": deviceAuth?.authBaseUrl ?? "",
                "package_name": deviceAuth?.packageName ?? "",
            ],
            "sync": [
                "enabled": config.sync.enabled,
                "base_url": resolvedApiBaseUrl,
            ],
            "privacy": [
                "allow_research": config.privacy.allowResearch,
            ],
        ]

        if let dataDir {
            result["data_dir"] = dataDir
        }
        return result
    }
}
