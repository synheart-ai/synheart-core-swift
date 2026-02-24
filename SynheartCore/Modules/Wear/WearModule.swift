import Foundation
import Combine

/// Wear Module
///
/// Collects and buffers raw biosignals from wearables.
/// RFC-CORE-0007 compliant: no feature computation in Core.
public class WearModule: BaseSynheartModule, WearFeatureProvider, RawWearDataProvider {
    private let sources: [WearSourceHandler]
    private let cache = WearCache()
    private let capabilities: CapabilityProvider
    private let consent: ConsentProvider

    private var cancellables = Set<AnyCancellable>()

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

    // MARK: - WearFeatureProvider

    public func features(_ window: WindowType) -> WearWindowFeatures? {
        // Feature computation removed per RFC-CORE-0007.
        // Features will be computed by synheart-runtime when wired.
        return nil
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
