import Foundation
import Combine

/// Behavior Module
///
/// Captures user-device interaction patterns.
public class BehaviorModule: BaseSynheartModule, RawBehaviorDataProvider {
    private let eventStream = BehaviorEventStream()
    private let aggregator = WindowAggregator()

    private let capabilities: CapabilityProvider
    private let consent: ConsentProvider
    private weak var runtimeSink: (any BehaviorRuntimeSinking)?
    private let collector: (any BehaviorCollecting)?
    private let sessionIdProvider: () -> String?

    private var eventSubscription: AnyCancellable?
    private var cleanupTimer: AnyCancellable?
    private let capturedEventSubject = PassthroughSubject<BehaviorEvent, Never>()

    /// Consent-filtered interaction events that were accepted for native ingest.
    public var capturedEvents: AnyPublisher<BehaviorEvent, Never> {
        capturedEventSubject.eraseToAnyPublisher()
    }

    public init(
        capabilities: CapabilityProvider,
        consent: ConsentProvider
    ) {
        self.capabilities = capabilities
        self.consent = consent
        self.runtimeSink = nil
        self.collector = makeProductionBehaviorCollector()
        self.sessionIdProvider = { nil }
        super.init(moduleId: "behavior")
    }

    init(
        capabilities: CapabilityProvider,
        consent: ConsentProvider,
        runtimeSink: (any BehaviorRuntimeSinking)?,
        collector: (any BehaviorCollecting)? = makeProductionBehaviorCollector(),
        sessionIdProvider: @escaping () -> String? = { nil }
    ) {
        self.capabilities = capabilities
        self.consent = consent
        self.runtimeSink = runtimeSink
        self.collector = collector
        self.sessionIdProvider = sessionIdProvider
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

    public override func onInitialize() async throws {
        SynheartLogger.log("[BehaviorModule] Initializing behavior tracking...")
    }

    public override func onStart() async throws {
        SynheartLogger.log("[BehaviorModule] Starting behavior tracking...")
        guard consent.current().behavior else {
            SynheartLogger.log("[BehaviorModule] Behavior consent is not granted; collection remains stopped")
            return
        }

        eventSubscription = eventStream.events
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        SynheartLogger.log("[BehaviorModule] Event stream error: \(error)")
                    }
                },
                receiveValue: { [weak self] event in
                    self?.accept(event)
                }
            )

        collector?.onEvent = { [weak self] event in
            self?.eventStream.record(event)
        }
        try collector?.start(sessionId: sessionIdProvider())

        cleanupTimer = Timer.publish(every: 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.aggregator.cleanOldWindows() }

        SynheartLogger.log("[BehaviorModule] Behavior tracking started")
    }

    public override func onStop() async throws {
        SynheartLogger.log("[BehaviorModule] Stopping behavior tracking...")

        eventSubscription?.cancel()
        eventSubscription = nil

        cleanupTimer?.cancel()
        cleanupTimer = nil

        collector?.onEvent = nil
        collector?.stop()
    }

    public override func onDispose() async throws {
        SynheartLogger.log("[BehaviorModule] Disposing behavior module...")
        try await eventStream.dispose()
    }

    private func accept(_ event: BehaviorEvent) {
        guard consent.current().behavior else { return }
        aggregator.addEvent(event)
        guard let mapped = BehaviorRuntimeMapping.map(event) else { return }
        runtimeSink?.pushBehavior(
            tsMs: Int64(event.timestamp.timeIntervalSince1970 * 1_000),
            eventType: mapped.0.rawValue,
            value: mapped.1
        )
        capturedEventSubject.send(event)
    }
}
