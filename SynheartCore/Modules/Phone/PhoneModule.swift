import Foundation
import Combine

/// Phone Module
///
/// Captures device-level motion and context signals.
/// RFC-CORE-0007 compliant: no feature computation in Core.
public class PhoneModule: BaseSynheartModule, PhoneFeatureProvider, RawPhoneDataProvider {
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
        // Feature computation removed per RFC-CORE-0007.
        // Features will be computed by Flux when wired.
        return nil
    }

    // MARK: - RawPhoneDataProvider

    public func rawDataPoints(_ window: WindowType) -> [PhoneDataPoint] {
        guard consent.current().phoneContext else { return [] }
        return cache.getDataPoints(window)
    }

    // MARK: - SynheartModule

    public override func initialize() async throws {
        print("[PhoneModule] Initializing phone collectors...")
    }

    public override func start() async throws {
        print("[PhoneModule] Starting phone data collection...")

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
