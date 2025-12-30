import Foundation
import Combine

/// Wear Module
///
/// Collects and normalizes biosignals from wearables.
/// Provides window-based features to HSV Runtime.
public class WearModule: BaseSynheartModule, WearFeatureProvider {
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
        // Check consent first
        guard consent.current().biosignals else {
            return nil // Return nil if consent denied
        }
        
        guard let features = cache.getFeatures(window) else {
            return nil
        }
        
        // Filter based on capability level
        return filterByCapability(features)
    }
    
    /// Filter features based on capability level
    private func filterByCapability(_ features: WearWindowFeatures) -> WearWindowFeatures? {
        let level = capabilities.capability(.wear)
        
        switch level {
        case .none:
            return nil
            
        case .core:
            // Core: Only derived metrics (average HR, HRV)
            return WearWindowFeatures(
                windowDuration: features.windowDuration,
                hrAverage: features.hrAverage,
                hrvRmssd: features.hrvRmssd,
                motionIndex: features.motionIndex,
                sleepStage: features.sleepStage,
                respRate: features.respRate
                // No min/max for core level
            )
            
        case .extended, .research:
            // Extended/Research: Full access
            return features
        }
    }
    
    // MARK: - SynheartModule
    
    public override func initialize() async throws {
        print("[WearModule] Initializing wear sources...")
        
        for source in sources {
            guard source.isAvailable else { continue }
            
            do {
                try await source.initialize()
                print("[WearModule] Initialized \(source.sourceType) source")
            } catch {
                print("[WearModule] Failed to initialize \(source.sourceType): \(error)")
            }
        }
    }
    
    public override func start() async throws {
        print("[WearModule] Starting wear data collection...")
        
        // Subscribe to each source
        for source in sources {
            guard source.isAvailable else { continue }
            
            source.sampleStream
                .sink(
                    receiveCompletion: { [weak self] completion in
                        if case .failure(let error) = completion {
                            print("[WearModule] Error from \(source.sourceType): \(error)")
                        }
                    },
                    receiveValue: { [weak self] sample in
                        self?.cache.addSample(sample)
                    }
                )
                .store(in: &cancellables)
            
            // Start mock source if needed
            if let mockSource = source as? MockWearSourceHandler {
                mockSource.startGenerating()
            }
        }
        
        print("[WearModule] Started \(cancellables.count) wear sources")
    }
    
    public override func stop() async throws {
        print("[WearModule] Stopping wear data collection...")
        
        cancellables.removeAll()
    }
    
    public override func dispose() async throws {
        print("[WearModule] Disposing wear module...")
        
        // Dispose all sources
        for source in sources {
            do {
                try await source.dispose()
            } catch {
                print("[WearModule] Error disposing \(source.sourceType): \(error)")
            }
        }
    }
}

