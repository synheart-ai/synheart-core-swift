import Foundation
import Combine

/// Behavior Module
///
/// Captures user-device interaction patterns.
/// RFC-CORE-0007 compliant: no feature computation in Core.
public class BehaviorModule: BaseSynheartModule, RawBehaviorDataProvider {
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

    // MARK: - RawBehaviorDataProvider

    public func rawEvents(_ window: WindowType) -> [BehaviorEvent] {
        guard consent.current().behavior else { return [] }
        return aggregator.getEvents(window)
    }

    // MARK: - SynheartModule

    public override func initialize() async throws {
        SynheartLogger.log("[BehaviorModule] Initializing behavior tracking...")
    }

    public override func start() async throws {
        SynheartLogger.log("[BehaviorModule] Starting behavior tracking...")

        eventSubscription = eventStream.events
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        SynheartLogger.log("[BehaviorModule] Event stream error: \(error)")
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

        SynheartLogger.log("[BehaviorModule] Behavior tracking started")
    }

    public override func stop() async throws {
        SynheartLogger.log("[BehaviorModule] Stopping behavior tracking...")

        eventSubscription?.cancel()
        eventSubscription = nil

        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    public override func dispose() async throws {
        SynheartLogger.log("[BehaviorModule] Disposing behavior module...")
        try await eventStream.dispose()
    }
}
