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

    /// Observer for every rich event handed to the runtime, called just before
    /// the push. Lets the facade republish them for a host that feeds a second
    /// runtime; see `Synheart.onRuntimeBehaviorEvent`.
    var onRuntimeBehaviorEvent: ((BehaviorEventInput) -> Void)?

    /// Context-channel bookkeeping, readable for diagnostics.
    private(set) var contextEventsAccepted = 0
    private(set) var contextEventsRejected = 0

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

        // Two paths, and the rich one is tried first: it carries the payload
        // the event has, where the legacy int-coded call flattens everything to
        // one double. The legacy path is the fallback for a runtime that
        // predates `synheart_core_push_behavior_event`; the two are mutually
        // exclusive per event, or every interaction would count twice.
        //
        // Arrivals only: a notification's later outcome would reach the engine
        // as a second arrival. It is still published to the host below.
        let followUp = BehaviorRuntimeMapping.isNotificationFollowUp(event)
        let rich = followUp ? nil : BehaviorRuntimeMapping.translateBehaviorEvent(event)
        if let rich { onRuntimeBehaviorEvent?(rich) }
        var richStatus: Int32?
        if let rich, let json = rich.toJSONString() {
            richStatus = runtimeSink?.pushBehaviorEventJson(json)
        }
        if richStatus == nil, !followUp, let mapped = BehaviorRuntimeMapping.map(event) {
            runtimeSink?.pushBehavior(
                tsMs: Int64(event.timestamp.timeIntervalSince1970 * 1_000),
                eventType: mapped.0.rawValue,
                value: mapped.1
            )
        }

        // The context channel, in addition to whichever behaviour path ran
        // above. Independent buffer, independent consumer: it feeds the
        // person-relative context window, the only source of
        // `context.deviation.*` and so of the friction index. Unwired, pause,
        // error and scroll deviation are structurally zero on every window.
        if let ctx = BehaviorRuntimeMapping.translateContextEvent(event), let json = ctx.toJSONString() {
            switch runtimeSink?.pushContextEventJson(json) {
            case .some(0): contextEventsAccepted += 1
            case .some: contextEventsRejected += 1
            case .none: break
            }
        }

        capturedEventSubject.send(event)
    }
}
