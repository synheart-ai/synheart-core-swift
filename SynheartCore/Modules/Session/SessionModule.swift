import Foundation
import Combine
import SynheartSession

/// Thin adapter around `SynheartSession` for core session management.
///
/// Follows the `WatchSessionModule` pattern from the Flutter integration:
/// - Wraps a `SynheartSession` composed with `BiosignalProvider` + `BehaviorProvider`
/// - Bridges the session's `AsyncStream<SessionEvent>` into a Combine publisher
///   so core consumers can stay on Combine
/// - Provides `startSession` / `stopSession` / `ingestHsiMetrics`
///
/// The underlying `SynheartSession` is composed, not merged — the session SDK
/// remains standalone and can be used independently.
class SessionModule {

    private let session: SynheartSession
    private var activeSessionId: String?
    private var eventSubject: PassthroughSubject<SessionEvent, Never>?
    private var pumpTask: Task<Void, Never>?

    /// Stream of session events from the active session.
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

    init(biosignalProvider: BiosignalProvider, behaviorProvider: BehaviorProvider? = nil) {
        self.session = SynheartSession(provider: biosignalProvider, behaviorProvider: behaviorProvider)
    }

    /// Start a session with the given configuration.
    ///
    /// Returns a publisher of typed `SessionEvent`s. The same events are also
    /// emitted on the `events` property.
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

        let stream: AsyncStream<SessionEvent>
        do {
            stream = try session.startSession(config: config)
        } catch {
            SynheartLogger.log("[SessionModule] Failed to start session: \(error)")
            let errorEvent = SessionEvent.sessionError(
                sessionId: config.sessionId,
                code: .sensorUnavailable,
                message: error.localizedDescription
            )
            subject.send(errorEvent)
            cleanup()
            subject.send(completion: .finished)
            return subject.eraseToAnyPublisher()
        }

        pumpTask = Task { [weak self] in
            for await event in stream {
                guard let self = self else { return }
                subject.send(event)

                // Auto-cleanup on terminal events
                switch event {
                case .sessionSummary, .sessionError:
                    SynheartLogger.log(
                        "[SessionModule] Session \(config.sessionId) ended"
                    )
                    self.cleanup()
                    subject.send(completion: .finished)
                default:
                    break
                }
            }
        }

        return subject.eraseToAnyPublisher()
    }

    /// Stop the active session.
    ///
    /// The session will emit a `sessionSummary` event before completion.
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
            try session.stopSession(sessionId: sessionId)
        } catch {
            SynheartLogger.log("[SessionModule] Error stopping session: \(error)")
            cleanup()
        }
    }

    /// Forward pre-computed HRV metrics from the native runtime into the session.
    ///
    /// HRV metrics (SDNN, RMSSD, pNN50) come from the Synheart Runtime, which
    /// applies artifact filtering — the session SDK does not compute HRV locally.
    /// No-op when no session is active.
    func ingestHsiMetrics(_ hsiMetrics: [String: Any]) {
        guard let sid = activeSessionId else { return }
        session.ingestHsiMetrics(sessionId: sid, hsiMetrics: hsiMetrics)
    }

    /// Status snapshot of the current session, as the on-the-wire map shape.
    /// Returns nil when no session is active.
    func getStatus() -> [String: Any]? {
        guard let s = session.getStatus() else { return nil }
        return [
            "session_id": s.sessionId,
            "active": s.active,
            "last_seq": s.lastSeq,
        ]
    }

    /// Dispose all resources. After this call the module cannot be reused.
    func dispose() {
        if let id = activeSessionId {
            try? session.stopSession(sessionId: id)
        }
        cleanup()
        eventSubject?.send(completion: .finished)
        eventSubject = nil
        SynheartLogger.log("[SessionModule] Disposed")
    }

    private func cleanup() {
        activeSessionId = nil
        pumpTask?.cancel()
        pumpTask = nil
    }
}
