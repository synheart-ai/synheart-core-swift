import Foundation
import Combine

/// Cloud Connector Module
///
/// Securely uploads HSV snapshots (as HSI 1.0 format) to Synheart Platform.
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
/// HSVRuntime → CloudConnector → [Queue] → UploadClient → Platform
///                    ↓
///              RateLimiter
///              NetworkMonitor
/// ```
public class CloudConnectorModule: BaseSynheartModule {
    private let capabilities: CapabilityProvider
    private let consent: ConsentModule
    private let hsvRuntime: HSVRuntimeModule
    private let config: CloudConfig

    // Components
    private var hmacSigner: HMACSigner!
    private var uploadClient: UploadClient!
    private var uploadQueue: UploadQueue!
    private var rateLimiter: RateLimiter!
    private var networkMonitor: NetworkMonitor!

    // Subscriptions
    private var cancellables = Set<AnyCancellable>()

    public init(
        capabilities: CapabilityProvider,
        consent: ConsentModule,
        hsvRuntime: HSVRuntimeModule,
        config: CloudConfig
    ) {
        self.capabilities = capabilities
        self.consent = consent
        self.hsvRuntime = hsvRuntime
        self.config = config
        super.init(moduleId: "cloud")
    }

    public override func onInitialize() async throws {
        print("[CloudConnector] Initializing...")

        // 1. Initialize components
        hmacSigner = HMACSigner(hmacSecret: config.hmacSecret)
        uploadClient = UploadClient(baseUrl: config.baseUrl)
        uploadQueue = UploadQueue(maxSize: config.maxQueueSize)
        rateLimiter = RateLimiter(capabilityProvider: capabilities)
        networkMonitor = NetworkMonitor()

        // 2. Load persisted queue
        await uploadQueue.loadFromStorage()

        print("[CloudConnector] Initialized")
    }

    public override func onStart() async throws {
        print("[CloudConnector] Starting...")

        // 1. Subscribe to HSV stream (final stream includes emotion/focus if enabled)
        hsvRuntime.finalHsvStream
            .sink { [weak self] hsv in
                guard let self = self else { return }
                Task {
                    await self.handleHSVUpdate(hsv)
                }
            }
            .store(in: &cancellables)

        // 2. Subscribe to network changes
        networkMonitor.connectivityPublisher
            .sink { [weak self] isOnline in
                guard let self = self else { return }
                Task {
                    await self.handleNetworkChange(isOnline)
                }
            }
            .store(in: &cancellables)

        // 3. Attempt to flush queue if online
        if networkMonitor.isOnline {
            Task {
                await flushQueue()
            }
        }

        print("[CloudConnector] Started")
    }

    public override func onStop() async throws {
        print("[CloudConnector] Stopping...")

        cancellables.removeAll()

        print("[CloudConnector] Stopped")
    }

    public override func onDispose() async throws {
        print("[CloudConnector] Disposing...")

        // Persist queue before disposal
        await uploadQueue.persistToStorage()

        // Cleanup resources
        networkMonitor.dispose()

        print("[CloudConnector] Disposed")
    }

    /// Handle HSV update from runtime
    private func handleHSVUpdate(_ hsv: HSV) async {
        // Check consent
        let currentConsent = await consent.current()
        guard currentConsent.cloudUpload else {
            return // Silent return - no upload
        }

        // Check rate limit (based on window type, defaulting to "micro")
        let windowType = "micro" // TODO: Extract from HSV when available
        guard await rateLimiter.canUpload(windowType) else {
            return // Silent return - rate limited
        }

        // Enqueue for upload
        await uploadQueue.enqueue(hsv)

        // Try immediate upload if online
        if networkMonitor.isOnline {
            await attemptUpload()
        }
    }

    /// Handle network connectivity change
    private func handleNetworkChange(_ isOnline: Bool) async {
        if isOnline {
            print("[CloudConnector] Network available, flushing queue...")
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
            // Convert HSV → HSI 1.0
            let hsi10Snapshots = batch.map { hsv in
                hsv.toHSI10(
                    producerName: "Synheart Core SDK",
                    producerVersion: "1.0.0",
                    instanceId: config.instanceId
                )
            }

            // Create upload payload
            let snapshots = hsi10Snapshots.map { dict in
                dict.mapValues { AnyCodable($0) }
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
                tenantId: config.tenantId
            )

            // Success - remove from queue
            await uploadQueue.confirmBatch(batch)

            // Update rate limiter
            let windowType = "micro" // TODO: Extract from batch
            await rateLimiter.recordUpload(windowType, batchSize: batch.count)

            print("[CloudConnector] Uploaded \(batch.count) snapshots (\(response.status))")

        } catch {
            // Re-enqueue batch on failure
            await uploadQueue.requeueBatch(batch)

            // Log error (but don't throw - this is background operation)
            print("[CloudConnector] Upload failed: \(error)")
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
