import Foundation
import Combine
import SynheartSession

/// Thin adapter around `SessionEngine` for core session management.
///
/// Follows the `WatchSessionModule` pattern from the Dart integration:
/// - Wraps a `SessionEngine` composed with `BiosignalProvider` + `BehaviorProvider`
/// - Bridges the engine's callback-based events into a Combine publisher
/// - Provides `startSession` / `stopSession` / `ingestHsiMetrics`
///
/// The underlying `SessionEngine` is composed, not merged — the session SDK
/// remains standalone and can be used independently.
class SessionModule {

    private let engine: SessionEngine
    private var activeSessionId: String?
    private var eventSubject: PassthroughSubject<SessionEvent, Never>?

    /// Stream of session events from the active session.
    /// Returns a publisher that emits typed `SessionEvent` values.
    var events: AnyPublisher<SessionEvent, Never> {
        guard let subject = eventSubject else {
            return Empty<SessionEvent, Never>().eraseToAnyPublisher()
        }
        return subject.eraseToAnyPublisher()
    }

    /// Whether a session is currently active.
    var isActive: Bool { activeSessionId != nil }

    /// The active session ID, if any.
    var currentSessionId: String? { activeSessionId }

    /// Create a `SessionModule` with adapted providers.
    ///
    /// - Parameters:
    ///   - biosignalProvider: Adapted wear module provider (or mock).
    ///   - behaviorProvider: Adapted behavior module provider (optional).
    init(biosignalProvider: BiosignalProvider, behaviorProvider: BehaviorProvider? = nil) {
        self.engine = SessionEngine(provider: biosignalProvider, behaviorProvider: behaviorProvider)
    }

    /// Start a session with the given configuration.
    ///
    /// Returns a publisher of typed `SessionEvent`s. The same events are also
    /// emitted on the `events` property.
    ///
    /// - Parameter config: Session configuration.
    /// - Returns: `AnyPublisher<SessionEvent, Never>` that completes when the session ends.
    func startSession(config: SessionConfig) -> AnyPublisher<SessionEvent, Never> {
        if activeSessionId != nil {
            SynheartLogger.log("[SessionModule] Session already active (\(activeSessionId!)), ignoring start")
            return events
        }

        activeSessionId = config.sessionId
        let subject = PassthroughSubject<SessionEvent, Never>()
        eventSubject = subject

        SynheartLogger.log(
            "[SessionModule] Starting session \(config.sessionId) "
            + "(mode: \(config.mode.rawValue), duration: \(config.durationSec)s)"
        )

        do {
            try engine.start(config: config) { [weak self] eventMap in
                guard let self = self else { return }
                guard let typed = sessionEventFromMap(eventMap) else { return }

                subject.send(typed)

                // Auto-cleanup on terminal events
                if typed is SessionSummary || typed is SessionErrorEvent {
                    SynheartLogger.log(
                        "[SessionModule] Session \(typed.sessionId) ended "
                        + "(\(String(describing: type(of: typed))))"
                    )
                    self.cleanup()
                    subject.send(completion: .finished)
                }
            }
        } catch {
            SynheartLogger.log("[SessionModule] Failed to start session: \(error)")
            // Emit error event and complete
            let errorEvent = SessionErrorEvent(
                sessionId: config.sessionId,
                errorCode: "start_failed",
                message: error.localizedDescription
            )
            subject.send(errorEvent)
            cleanup()
            subject.send(completion: .finished)
        }

        return subject.eraseToAnyPublisher()
    }

    /// Stop the active session.
    ///
    /// The engine will emit a `SessionSummary` event before completion.
    /// No-op if no session is active.
    func stopSession(sessionId: String) {
        guard let activeId = activeSessionId else { return }
        guard activeId == sessionId else {
            SynheartLogger.log(
                "[SessionModule] Stop requested for \(sessionId) but active is \(activeId)"
            )
            return
        }

        SynheartLogger.log("[SessionModule] Stopping session \(sessionId)")
        do {
            try engine.stop(sessionId: sessionId)
        } catch {
            SynheartLogger.log("[SessionModule] Error stopping session: \(error)")
            cleanup()
        }
    }

    /// Forward pre-computed HRV metrics from the native runtime into the session engine.
    ///
    /// HRV metrics (SDNN, RMSSD, pNN50) come from the Synheart Runtime, which applies
    /// artifact filtering — the session SDK only computes mean HR locally.
    func ingestHsiMetrics(_ hsiMetrics: [String: Any]) {
        engine.ingestHsiMetrics(hsiMetrics)
    }

    /// Get the status of the current session.
    func getStatus() -> [String: Any]? {
        engine.getStatus()
    }

    /// Dispose all resources. After this call the module cannot be reused.
    func dispose() {
        if let id = activeSessionId {
            try? engine.stop(sessionId: id)
        }
        cleanup()
        eventSubject?.send(completion: .finished)
        eventSubject = nil
        SynheartLogger.log("[SessionModule] Disposed")
    }

    private func cleanup() {
        activeSessionId = nil
    }
}
