import Foundation

/// Module for custom platform session and metadata ingestion.
///
/// Wraps ``LabIngestClient`` with consent gating via ``ConsentModule``.
/// Uploads are on-demand (not streaming), so ``onStart()``/``onStop()`` are no-ops.
public class LabIngestModule: BaseSynheartModule {
    private let consentModule: ConsentModule
    private let config: LabIngestConfig

    private var _client: LabIngestClient!

    /// The underlying client — exposed for standalone/background usage.
    public var client: LabIngestClient {
        _client
    }

    public init(
        consentModule: ConsentModule,
        config: LabIngestConfig
    ) {
        self.consentModule = consentModule
        self.config = config
        super.init(moduleId: "lab_ingest")
    }

    public override func onInitialize() async throws {
        _client = LabIngestClient(
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
    public func ingestSession(_ payload: [String: Any]) async -> LabIngestResponse {
        let consent = consentModule.current()
        guard consent.behavior else {
            return LabIngestResponse(
                success: false,
                statusCode: 0,
                errorMessage: "Behavior consent not granted"
            )
        }

        return await _client.ingestSession(
            payload: payload,
            hmacSecret: config.hmacSecret ?? "",
            apiKey: config.apiKey ?? ""
        )
    }

    /// Ingest a metadata payload. Requires `biosignals` consent.
    public func ingestMetadata(_ payload: [String: Any]) async -> LabIngestResponse {
        let consent = consentModule.current()
        guard consent.biosignals else {
            return LabIngestResponse(
                success: false,
                statusCode: 0,
                errorMessage: "Biosignals consent not granted"
            )
        }

        return await _client.ingestMetadata(
            payload: payload,
            hmacSecret: config.hmacSecret ?? "",
            apiKey: config.apiKey ?? ""
        )
    }
}
