import Foundation
import Combine

/// Behavior Module
///
/// Captures user-device interaction patterns.
/// RFC-CORE-0007 compliant: no feature computation in Core.
public class BehaviorModule: BaseSynheartModule, BehaviorFeatureProvider, RawBehaviorDataProvider {
    private let eventStream = BehaviorEventStream()
    private let aggregator = WindowAggregator()

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
        // Feature computation removed per RFC-CORE-0007.
        // Features will be computed by synheart-runtime when wired.
        return nil
    }

    // MARK: - RawBehaviorDataProvider

    public func rawEvents(_ window: WindowType) -> [BehaviorEvent] {
        guard consent.current().behavior else { return [] }
        return aggregator.getEvents(window)
    }

    // MARK: - SynheartModule

    public override func initialize() async throws {
        print("[BehaviorModule] Initializing behavior tracking...")
    }

    public override func start() async throws {
        print("[BehaviorModule] Starting behavior tracking...")

        eventSubscription = eventStream.events
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("[BehaviorModule] Event stream error: \(error)")
                    }
                },
                receiveValue: { [weak self] event in
                    if self?.consent.current().behavior == true {
                        self?.aggregator.addEvent(event)
                    }
                }
            )

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
