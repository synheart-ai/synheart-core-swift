import Foundation
import Combine

/// Wear Module
///
/// Collects and buffers raw biosignals from wearables.
public class WearModule: BaseSynheartModule, RawWearDataProvider {
    private let sources: [WearSourceHandler]
    private let cache = WearCache()
    private let capabilities: CapabilityProvider
    private let consent: ConsentProvider

    private var eventProcessor: WearableEventProcessor?

    private let rawSampleSubject = PassthroughSubject<WearSample, Never>()
    private let vendorSyncSubject = CurrentValueSubject<Bool, Never>(false)
    private var cancellables = Set<AnyCancellable>()

    /// Publisher of raw wear samples (mirrors Dart rawSampleStream / Kotlin sampleFlow).
    public var rawSamplePublisher: AnyPublisher<WearSample, Never> {
        rawSampleSubject.eraseToAnyPublisher()
    }

    /// Publisher of vendor sync consent state changes.
    public var vendorSyncState: AnyPublisher<Bool, Never> {
        vendorSyncSubject.eraseToAnyPublisher()
    }

    public init(
        capabilities: CapabilityProvider,
        consent: ConsentProvider,
        sources: [WearSourceHandler]? = nil
    ) {
        self.capabilities = capabilities
        self.consent = consent
        self.sources = sources ?? [MockWearSourceHandler()]
        super.init(moduleId: "wear")
    }

    // MARK: - Event Processor

    /// Set the wearable event processor for RAMEN event bridging.
    ///
    /// Called by the Synheart entry point after configure() when storage and
    /// runtime bridge are available.
    public func setEventProcessor(_ processor: WearableEventProcessor) {
        self.eventProcessor = processor
        SynheartLogger.log("[WearModule] Event processor attached")
    }

    /// Process a vendor event received from RAMEN.
    ///
    /// Delegates to the attached `WearableEventProcessor` which normalizes the
    /// event into a `CanonicalWearableEvent`, stores it, and pushes to the SRM.
    ///
    /// - Parameters:
    ///   - provider: Vendor name, e.g. "whoop", "garmin"
    ///   - eventType: Event type, e.g. "sleep.updated", "recovery.updated"
    ///   - payload: Decoded JSON payload from the RAMEN EventEnvelope
    ///   - eventId: RAMEN event ID (for dedup)
    ///   - seq: RAMEN sequence number
    /// - Returns: The canonical event if processed, nil if skipped or no processor.
    @discardableResult
    public func processVendorEvent(
        provider: String,
        eventType: String,
        payload: [String: Any],
        eventId: String,
        seq: Int
    ) -> CanonicalWearableEvent? {
        guard vendorSyncSubject.value else {
            SynheartLogger.log("[WearModule] Vendor sync consent not granted — dropping \(provider)/\(eventType)")
            return nil
        }
        guard let processor = eventProcessor else {
            SynheartLogger.log("[WearModule] No event processor attached -- dropping \(provider)/\(eventType)")
            return nil
        }
        return processor.processRamenEvent(
            provider: provider,
            eventType: eventType,
            payload: payload,
            eventId: eventId,
            seq: seq
        )
    }

    // MARK: - RawWearDataProvider

    public func rawSamples(_ window: WindowType) -> [WearSample] {
        guard consent.current().biosignals else { return [] }
        return cache.getSamples(window)
    }

    // MARK: - SynheartModule

    public override func initialize() async throws {
        SynheartLogger.log("[WearModule] Initializing wear sources...")

        for source in sources {
            guard source.isAvailable else { continue }

            do {
                try await source.initialize()
                SynheartLogger.log("[WearModule] Initialized \(source.sourceType) source")
            } catch {
                SynheartLogger.log("[WearModule] Failed to initialize \(source.sourceType): \(error)")
            }
        }
    }

    public override func start() async throws {
        SynheartLogger.log("[WearModule] Starting wear data collection...")

        // Track vendor sync consent changes
        consent.observe()
            .map(\.vendorSync)
            .removeDuplicates()
            .sink { [weak self] allowed in
                self?.vendorSyncSubject.send(allowed)
                SynheartLogger.log("[WearModule] vendorSync consent changed: \(allowed)")
            }
            .store(in: &cancellables)

        for source in sources {
            guard source.isAvailable else { continue }

            source.sampleStream
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            SynheartLogger.log("[WearModule] Error from \(source.sourceType): \(error)")
                        }
                    },
                    receiveValue: { [weak self] sample in
                        self?.cache.addSample(sample)
                        self?.rawSampleSubject.send(sample)
                    }
                )
                .store(in: &cancellables)

            if let mockSource = source as? MockWearSourceHandler {
                mockSource.startGenerating()
            }
        }

        SynheartLogger.log("[WearModule] Started \(cancellables.count) wear sources")
    }

    public override func stop() async throws {
        SynheartLogger.log("[WearModule] Stopping wear data collection...")
        cancellables.removeAll()
    }

    public override func dispose() async throws {
        SynheartLogger.log("[WearModule] Disposing wear module...")
        for source in sources {
            do {
                try await source.dispose()
            } catch {
                SynheartLogger.log("[WearModule] Error disposing \(source.sourceType): \(error)")
            }
        }
    }
}
