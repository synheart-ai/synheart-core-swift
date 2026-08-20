import Foundation
import Combine

/// Phone Module
///
/// Captures device-level motion and context signals.
public class PhoneModule: BaseSynheartModule, RawPhoneDataProvider {
    private let motionCollector: any MotionCollecting
    private let screenTracker: any ScreenStateTracking
    private let appTracker: any AppFocusTracking
    private let notificationTracker: any NotificationTracking
    private let cache = PhoneCache()

    private let capabilities: CapabilityProvider
    private let consent: ConsentProvider

    private var cancellables = Set<AnyCancellable>()

    public init(
        capabilities: CapabilityProvider,
        consent: ConsentProvider,
        motionCollector: any MotionCollecting = CoreMotionCollector(),
        screenTracker: any ScreenStateTracking = IOSScreenStateTracker(),
        appTracker: any AppFocusTracking = NoOpAppFocusTracker(),
        notificationTracker: any NotificationTracking = NoOpNotificationTracker()
    ) {
        self.capabilities = capabilities
        self.consent = consent
        self.motionCollector = motionCollector
        self.screenTracker = screenTracker
        self.appTracker = appTracker
        self.notificationTracker = notificationTracker
        super.init(moduleId: "phone")
    }

    var collectorTypeNames: [String] {
        [
            String(describing: type(of: motionCollector)),
            String(describing: type(of: screenTracker)),
            String(describing: type(of: appTracker)),
            String(describing: type(of: notificationTracker)),
        ]
    }

    // MARK: - RawPhoneDataProvider

    public func rawDataPoints(_ window: WindowType) -> [PhoneDataPoint] {
        guard consent.current().phoneContext else { return [] }
        return cache.getDataPoints(window)
    }

    // MARK: - SynheartModule

    public override func onInitialize() async throws {
        SynheartLogger.log("[PhoneModule] Initializing phone collectors...")
    }

    public override func onStart() async throws {
        SynheartLogger.log("[PhoneModule] Starting phone data collection...")
        guard consent.current().phoneContext else {
            SynheartLogger.log("[PhoneModule] Phone-context consent is not granted; collection remains stopped")
            return
        }

        motionCollector.motionStream
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        SynheartLogger.log("[PhoneModule] Motion error: \(error)")
                    }
                },
                receiveValue: { [weak self] motion in
                    self?.cacheMotionIfConsented(motion)
                }
            )
            .store(in: &cancellables)
        try await motionCollector.start()

        screenTracker.screenStream
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        SynheartLogger.log("[PhoneModule] Screen state error: \(error)")
                    }
                },
                receiveValue: { [weak self] state in
                    self?.cacheScreenStateIfConsented(state, timestamp: Date())
                }
            )
            .store(in: &cancellables)
        try await screenTracker.start()

        if capabilities.capability(.phone) >= .extended {
            appTracker.appSwitchStream
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            SynheartLogger.log("[PhoneModule] App tracking error: \(error)")
                        }
                    },
                    receiveValue: { [weak self] _ in
                        self?.cacheAppSwitchIfConsented(timestamp: Date())
                    }
                )
                .store(in: &cancellables)
            try await appTracker.start()
        }

        if capabilities.capability(.phone) >= .extended {
            notificationTracker.notificationStream
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            SynheartLogger.log("[PhoneModule] Notification error: \(error)")
                        }
                    },
                    receiveValue: { [weak self] event in
                        self?.cacheNotificationIfConsented(event)
                    }
                )
                .store(in: &cancellables)
            try await notificationTracker.start()
        }

        SynheartLogger.log("[PhoneModule] Started \(cancellables.count) collectors")
    }

    func cacheMotionIfConsented(_ motion: MotionData) {
        guard consent.current().phoneContext else { return }
        cache.addMotionData(motion)
    }

    private func cacheScreenStateIfConsented(_ state: ScreenState, timestamp: Date) {
        guard consent.current().phoneContext else { return }
        cache.addScreenState(state, timestamp: timestamp)
    }

    private func cacheAppSwitchIfConsented(timestamp: Date) {
        guard consent.current().phoneContext else { return }
        cache.addAppSwitch(timestamp: timestamp)
    }

    private func cacheNotificationIfConsented(_ event: NotificationEvent) {
        guard consent.current().phoneContext else { return }
        cache.addNotification(event)
    }

    public override func onStop() async throws {
        SynheartLogger.log("[PhoneModule] Stopping phone data collection...")

        cancellables.removeAll()

        try await motionCollector.stop()
        try await screenTracker.stop()
        try await appTracker.stop()
        try await notificationTracker.stop()
    }

    public override func onDispose() async throws {
        SynheartLogger.log("[PhoneModule] Disposing phone module...")

        try await motionCollector.dispose()
        try await screenTracker.dispose()
        try await appTracker.dispose()
        try await notificationTracker.dispose()
    }
}
