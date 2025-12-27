import Foundation
import Combine

/// Behavior Module
///
/// Captures user-device interaction patterns.
/// Provides window-based behavioral features to HSI Runtime.
public class BehaviorModule: BaseSynheartModule, BehaviorFeatureProvider {
    private let eventStream = BehaviorEventStream()
    private let aggregator = WindowAggregator()
    private let extractor = BehaviorFeatureExtractor()
    
    private let capabilities: CapabilityProvider
    private let consent: ConsentProvider
    
    private var eventSubscription: AnyCancellable?
    private var cleanupTimer: Timer?
    
    public init(
        capabilities: CapabilityProvider,
        consent: ConsentProvider
    ) {
        self.capabilities = capabilities
        self.consent = consent
        super.init(moduleId: "behavior")
    }
    
    /// Get the event stream for recording events
    public var eventStreamInstance: BehaviorEventStream {
        return eventStream
    }
    
    // MARK: - BehaviorFeatureProvider
    
    public func features(_ window: WindowType) -> BehaviorWindowFeatures? {
        // Check consent
        guard consent.current().behavior else {
            return nil // Return nil if consent denied
        }
        
        let events = aggregator.getEvents(window)
        let features = extractor.extract(events)
        
        // Filter based on capability level
        return filterByCapability(features)
    }
    
    /// Filter features based on capability level
    private func filterByCapability(_ features: BehaviorWindowFeatures) -> BehaviorWindowFeatures? {
        let level = capabilities.capability(.behavior)
        
        switch level {
        case .none:
            return nil
            
        case .core:
            // Core: Only basic metrics
            return BehaviorWindowFeatures(
                tapRateNorm: features.tapRateNorm,
                keystrokeRateNorm: features.keystrokeRateNorm,
                scrollVelocityNorm: features.scrollVelocityNorm,
                idleRatio: features.idleRatio,
                switchRateNorm: features.switchRateNorm,
                burstiness: 0.0, // Not available at core
                sessionFragmentation: 0.0, // Not available at core
                notificationLoad: 0.0, // Not available at core
                distractionScore: features.distractionScore,
                focusHint: features.focusHint
            )
            
        case .extended, .research:
            // Extended/Research: Full access
            return features
        }
    }
    
    // MARK: - SynheartModule
    
    public override func initialize() async throws {
        print("[BehaviorModule] Initializing behavior tracking...")
        // Nothing to initialize
    }
    
    public override func start() async throws {
        print("[BehaviorModule] Starting behavior tracking...")
        
        // Subscribe to event stream
        eventSubscription = eventStream.events
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("[BehaviorModule] Event stream error: \(error)")
                    }
                },
                receiveValue: { [weak self] event in
                    // Check consent before adding event
                    if self?.consent.current().behavior == true {
                        self?.aggregator.addEvent(event)
                    }
                }
            )
        
        // Start cleanup timer (every minute)
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.aggregator.cleanOldWindows()
        }
        
        print("[BehaviorModule] Behavior tracking started")
    }
    
    public override func stop() async throws {
        print("[BehaviorModule] Stopping behavior tracking...")
        
        eventSubscription?.cancel()
        eventSubscription = nil
        
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }
    
    public override func dispose() async throws {
        print("[BehaviorModule] Disposing behavior module...")
        try await eventStream.dispose()
    }
}

