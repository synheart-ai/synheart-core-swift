import Foundation
import Combine

/// Phone Module
///
/// Captures device-level motion and context signals.
/// Provides window-based features to HSI Runtime.
public class PhoneModule: BaseSynheartModule, PhoneFeatureProvider {
    private let motionCollector = MotionCollector()
    private let screenTracker = ScreenStateTracker()
    private let appTracker = AppFocusTracker()
    private let notificationTracker = NotificationTracker()
    private let cache = PhoneCache()
    
    private let capabilities: CapabilityProvider
    private let consent: ConsentProvider
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        capabilities: CapabilityProvider,
        consent: ConsentProvider
    ) {
        self.capabilities = capabilities
        self.consent = consent
        super.init(moduleId: "phone")
    }
    
    // MARK: - PhoneFeatureProvider
    
    public func features(_ window: WindowType) -> PhoneWindowFeatures? {
        // Check consent
        guard consent.current().motion else {
            return nil // Return nil if consent denied
        }
        
        guard let features = cache.getFeatures(window) else {
            return nil
        }
        
        // Filter based on capability level
        return filterByCapability(features)
    }
    
    /// Filter features based on capability level
    private func filterByCapability(_ features: PhoneWindowFeatures) -> PhoneWindowFeatures? {
        let level = capabilities.capability(.phone)
        
        switch level {
        case .none:
            return nil
            
        case .core:
            // Core: Motion and screen only
            return PhoneWindowFeatures(
                motionLevel: features.motionLevel,
                screenOnRatio: features.screenOnRatio,
                appSwitchRate: 0.0, // No app switching at core level
                notificationRate: 0.0 // No notifications at core level
            )
            
        case .extended, .research:
            // Extended/Research: Full access
            return features
        }
    }
    
    // MARK: - SynheartModule
    
    public override func initialize() async throws {
        print("[PhoneModule] Initializing phone collectors...")
        // Nothing to initialize for mock collectors
    }
    
    public override func start() async throws {
        print("[PhoneModule] Starting phone data collection...")
        
        // Start motion collection
        try await motionCollector.start()
        motionCollector.motionStream
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("[PhoneModule] Motion error: \(error)")
                    }
                },
                receiveValue: { [weak self] motion in
                    self?.cache.addMotionData(motion)
                }
            )
            .store(in: &cancellables)
        
        // Start screen state tracking
        try await screenTracker.start()
        screenTracker.screenStream
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("[PhoneModule] Screen state error: \(error)")
                    }
                },
                receiveValue: { [weak self] state in
                    self?.cache.addScreenState(state, timestamp: Date())
                }
            )
            .store(in: &cancellables)
        
        // Start app tracking (if capability allows)
        if capabilities.capability(.phone) != .none {
            try await appTracker.start()
            appTracker.appSwitchStream
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("[PhoneModule] App tracking error: \(error)")
                        }
                    },
                    receiveValue: { [weak self] _ in
                        self?.cache.addAppSwitch(timestamp: Date())
                    }
                )
                .store(in: &cancellables)
        }
        
        // Start notification tracking (if capability allows)
        if capabilities.capability(.phone) != .none {
            try await notificationTracker.start()
            notificationTracker.notificationStream
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("[PhoneModule] Notification error: \(error)")
                        }
                    },
                    receiveValue: { [weak self] event in
                        self?.cache.addNotification(event)
                    }
                )
                .store(in: &cancellables)
        }
        
        print("[PhoneModule] Started \(cancellables.count) collectors")
    }
    
    public override func stop() async throws {
        print("[PhoneModule] Stopping phone data collection...")
        
        cancellables.removeAll()
        
        // Stop all collectors
        try await motionCollector.stop()
        try await screenTracker.stop()
        try await appTracker.stop()
        try await notificationTracker.stop()
    }
    
    public override func dispose() async throws {
        print("[PhoneModule] Disposing phone module...")
        
        try await motionCollector.dispose()
        try await screenTracker.dispose()
        try await appTracker.dispose()
        try await notificationTracker.dispose()
    }
}

