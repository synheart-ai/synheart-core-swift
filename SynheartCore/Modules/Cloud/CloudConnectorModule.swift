import Foundation
import Combine

/// Cloud Connector Module
///
/// Securely uploads HSV snapshots (as HSI 1.1 format) to Synheart Platform.
///
/// Features:
/// - HMAC-SHA256 authentication
/// - Offline queue with persistence (max 100 snapshots, FIFO)
/// - Client-side rate limiting per window type
/// - Exponential backoff retry (3 attempts max)
/// - Network monitoring with auto-flush
/// - Consent and capability enforcement
///
/// Architecture:
/// ```
/// RuntimeModule → CloudConnector → [Queue] → UploadClient → Platform
///                    ↓
///              RateLimiter
///              NetworkMonitor
/// ```
public class CloudConnectorModule: BaseSynheartModule {
    private let capabilities: CapabilityProvider
    private let consent: ConsentModule
    private let runtimeModule: RuntimeModule
    private let config: CloudConfig

    // Components
    private var hmacSigner: HMACSigner?
    private var uploadClient: UploadClient!
    private var uploadQueue: UploadQueue!
    private var rateLimiter: RateLimiter!
    private var networkMonitor: NetworkMonitor!
    private var schemaTransformer: HsiSchemaTransformer!

    // Subscriptions
    private var cancellables = Set<AnyCancellable>()

    public init(
        capabilities: CapabilityProvider,
        consent: ConsentModule,
        runtimeModule: RuntimeModule,
        config: CloudConfig
    ) {
        self.capabilities = capabilities
        self.consent = consent
        self.runtimeModule = runtimeModule
        self.config = config
        super.init(moduleId: "cloud")
    }

    public override func onInitialize() async throws {
        SynheartLogger.log("[CloudConnector] Initializing...")

        if let secret = config.hmacSecret {
            hmacSigner = HMACSigner(hmacSecret: secret)
        }
        uploadClient = UploadClient(baseUrl: config.baseUrl)
        uploadQueue = UploadQueue(maxSize: config.maxQueueSize)
        rateLimiter = RateLimiter(capabilityProvider: capabilities)
        networkMonitor = NetworkMonitor()
        schemaTransformer = HsiSchemaTransformer()

        await uploadQueue.loadFromStorage()

        SynheartLogger.log("[CloudConnector] Initialized")
    }

    public override func onStart() async throws {
        SynheartLogger.log("[CloudConnector] Starting...")

        runtimeModule.hsiStream
            .sink { [weak self] hsiJson in
                guard let self = self else { return }
                Task {
                    await self.handleHSIUpdate(hsiJson)
                }
            }
            .store(in: &cancellables)

        networkMonitor.connectivityPublisher
            .sink { [weak self] isOnline in
                guard let self = self else { return }
                Task {
                    await self.handleNetworkChange(isOnline)
                }
            }
            .store(in: &cancellables)

        if networkMonitor.isOnline {
            Task {
                await flushQueue()
            }
        }

        SynheartLogger.log("[CloudConnector] Started")
    }

    public override func onStop() async throws {
        SynheartLogger.log("[CloudConnector] Stopping...")

        cancellables.removeAll()

        SynheartLogger.log("[CloudConnector] Stopped")
    }

    public override func onDispose() async throws {
        SynheartLogger.log("[CloudConnector] Disposing...")

        // Persist queue before disposal
        await uploadQueue.persistToStorage()

        // Cleanup resources
        networkMonitor.dispose()

        SynheartLogger.log("[CloudConnector] Disposed")
    }

    /// Handle HSI JSON update from runtime
    private func handleHSIUpdate(_ hsiJson: String) async {
        // Check consent
        let currentConsent = await consent.current()
        guard currentConsent.cloudUpload else {
            return // Silent return - no upload
        }

        // Check rate limit (based on window type, defaulting to "micro")
        let windowType = "micro"
        guard await rateLimiter.canUpload(windowType) else {
            return // Silent return - rate limited
        }

        // Enqueue for upload
        await uploadQueue.enqueue(hsiJson)

        // Try immediate upload if online
        if networkMonitor.isOnline {
            await attemptUpload()
        }
    }

    /// Handle network connectivity change
    private func handleNetworkChange(_ isOnline: Bool) async {
        if isOnline {
            SynheartLogger.log("[CloudConnector] Network available, flushing queue...")
            await flushQueue()
        }
    }

    /// Attempt to upload a batch from the queue
    private func attemptUpload() async {
        // Get batch from queue
        let batchSize = await rateLimiter.batchSize
        let batch = await uploadQueue.dequeueBatch(batchSize)
        guard !batch.isEmpty else { return }

        do {
            // HSI JSON comes directly from synheart-runtime
            // Apply schema transformer to ensure conformance with hsi-1.1.schema.json
            let snapshots = batch.compactMap { json -> [String: AnyCodable]? in
                guard let data = json.data(using: .utf8),
                      var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                schemaTransformer.patch(&dict)
                return dict.mapValues { AnyCodable($0) }
            }

            let payload = UploadRequest(
                subject: Subject(
                    subjectType: config.subjectType,
                    subjectId: config.subjectId
                ),
                snapshots: snapshots
            )

            // Sign and upload
            let response = try await uploadClient.upload(
                payload: payload,
                signer: hmacSigner,
                tenantId: config.tenantId,
                authProvider: config.authProvider
            )

            // Success - remove from queue
            await uploadQueue.confirmBatch(batch)

            // Update rate limiter
            let windowType = "micro"
            await rateLimiter.recordUpload(windowType, batchSize: batch.count)

            SynheartLogger.log("[CloudConnector] Uploaded \(batch.count) snapshots (\(response.status))")

        } catch {
            // Re-enqueue batch on failure
            await uploadQueue.requeueBatch(batch)

            // Log error (but don't throw - this is background operation)
            SynheartLogger.log("[CloudConnector] Upload failed: \(error)")
        }
    }

    /// Force upload of queued snapshots now
    ///
    /// - Throws: CloudConnectorError if cloudUpload consent not granted
    public func uploadNow() async throws {
        let currentConsent = await consent.current()
        guard currentConsent.cloudUpload else {
            throw CloudConnectorError.consentRequired("cloudUpload consent required")
        }
        await attemptUpload()
    }

    /// Flush entire upload queue
    ///
    /// Attempts to upload all queued snapshots while online.
    public func flushQueue() async {
        while await uploadQueue.hasItems && networkMonitor.isOnline {
            await attemptUpload()
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms throttle
        }
    }

    /// Get queue status
    public func getQueueStatus() async -> QueueStatus {
        let currentConsent = await consent.current()
        return QueueStatus(
            queueLength: await uploadQueue.length,
            isOnline: networkMonitor.isOnline,
            hasConsent: currentConsent.cloudUpload
        )
    }
}

/// Queue status information
public struct QueueStatus {
    public let queueLength: Int
    public let isOnline: Bool
    public let hasConsent: Bool
}
