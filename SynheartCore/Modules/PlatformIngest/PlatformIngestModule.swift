import Foundation

/// Module for custom platform session and metadata ingestion.
///
/// Wraps ``PlatformIngestClient`` with consent gating via ``ConsentModule``.
/// Uploads are on-demand (not streaming), so ``onStart()``/``onStop()`` are no-ops.
public class PlatformIngestModule: BaseSynheartModule {
    private let consentModule: ConsentModule
    private let config: PlatformIngestConfig

    private var _client: PlatformIngestClient!

    /// The underlying client — exposed for standalone/background usage.
    public var client: PlatformIngestClient {
        _client
    }

    public init(
        consentModule: ConsentModule,
        config: PlatformIngestConfig
    ) {
        self.consentModule = consentModule
        self.config = config
        super.init(moduleId: "platform_ingest")
    }

    public override func onInitialize() async throws {
        _client = PlatformIngestClient(
            baseUrl: config.baseUrl,
            timeout: config.timeout,
            maxRetries: config.maxRetries
        )
    }

    public override func onStart() async throws {
        // On-demand uploads — nothing to start.
    }

    public override func onStop() async throws {
        // On-demand uploads — nothing to stop.
    }

    public override func onDispose() async throws {
        // URLSession cleanup handled by ARC.
    }

    /// Ingest a session payload. Requires `behavior` consent.
    public func ingestSession(_ payload: [String: Any]) async -> PlatformIngestResponse {
        let consent = consentModule.current()
        guard consent.behavior else {
            return PlatformIngestResponse(
                success: false,
                statusCode: 0,
                errorMessage: "Behavior consent not granted"
            )
        }

        return await _client.ingestSession(
            payload: payload,
            hmacSecret: config.hmacSecret,
            apiKey: config.apiKey
        )
    }

    /// Ingest a metadata payload. Requires `biosignals` consent.
    public func ingestMetadata(_ payload: [String: Any]) async -> PlatformIngestResponse {
        let consent = consentModule.current()
        guard consent.biosignals else {
            return PlatformIngestResponse(
                success: false,
                statusCode: 0,
                errorMessage: "Biosignals consent not granted"
            )
        }

        return await _client.ingestMetadata(
            payload: payload,
            hmacSecret: config.hmacSecret,
            apiKey: config.apiKey
        )
    }
}
