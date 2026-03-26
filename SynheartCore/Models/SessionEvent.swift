import Foundation

// MARK: - SessionEvent Protocol & Concrete Types

/// Typed session events emitted by `SessionModule`.
///
/// The session SDK (`SessionEngine`) emits untyped `[String: Any]` maps via
/// callback. `SessionModule` bridges those into strongly-typed events exposed
/// as `AnyPublisher<SessionEvent, Never>`.
public protocol SessionEvent {
    var sessionId: String { get }
}

/// Emitted once when the session engine starts.
public struct SessionStarted: SessionEvent {
    public let sessionId: String
    public let startedAtMs: Int64

    public init(sessionId: String, startedAtMs: Int64) {
        self.sessionId = sessionId
        self.startedAtMs = startedAtMs
    }
}

/// Periodic frame with computed metrics from the session engine.
public struct SessionFrame: SessionEvent {
    public let sessionId: String
    public let seq: Int
    public let emittedAtMs: Int64
    public let metrics: [String: Any]
    public let behavior: [String: Any]?

    public init(sessionId: String, seq: Int, emittedAtMs: Int64,
                metrics: [String: Any], behavior: [String: Any]? = nil) {
        self.sessionId = sessionId
        self.seq = seq
        self.emittedAtMs = emittedAtMs
        self.metrics = metrics
        self.behavior = behavior
    }
}

/// Final summary emitted when the session ends (duration elapsed or explicit stop).
public struct SessionSummary: SessionEvent {
    public let sessionId: String
    public let durationActualSec: Int
    public let metrics: [String: Any]
    public let behavior: [String: Any]?

    public init(sessionId: String, durationActualSec: Int,
                metrics: [String: Any], behavior: [String: Any]? = nil) {
        self.sessionId = sessionId
        self.durationActualSec = durationActualSec
        self.metrics = metrics
        self.behavior = behavior
    }
}

/// Emitted when the session engine encounters a fatal error.
public struct SessionErrorEvent: SessionEvent {
    public let sessionId: String
    public let errorCode: String
    public let message: String

    public init(sessionId: String, errorCode: String, message: String) {
        self.sessionId = sessionId
        self.errorCode = errorCode
        self.message = message
    }
}

/// Raw biosignal frame (opt-in via `includeRawSamples`).
public struct BiosignalFrame: SessionEvent {
    public let sessionId: String
    public let seq: Int
    public let emittedAtMs: Int64
    public let samples: [[String: Any]]

    public init(sessionId: String, seq: Int, emittedAtMs: Int64, samples: [[String: Any]]) {
        self.sessionId = sessionId
        self.seq = seq
        self.emittedAtMs = emittedAtMs
        self.samples = samples
    }
}

// MARK: - Factory

/// Parse a `[String: Any]` event map from `SessionEngine` into a typed event.
public func sessionEventFromMap(_ map: [String: Any]) -> SessionEvent? {
    guard let type = map["type"] as? String,
          let sessionId = map["session_id"] as? String else { return nil }

    switch type {
    case "session_started":
        return SessionStarted(
            sessionId: sessionId,
            startedAtMs: map["started_at_ms"] as? Int64 ?? 0
        )

    case "session_frame":
        return SessionFrame(
            sessionId: sessionId,
            seq: map["seq"] as? Int ?? 0,
            emittedAtMs: map["emitted_at_ms"] as? Int64 ?? 0,
            metrics: map["metrics"] as? [String: Any] ?? [:],
            behavior: map["behavior"] as? [String: Any]
        )

    case "session_summary":
        return SessionSummary(
            sessionId: sessionId,
            durationActualSec: map["duration_actual_sec"] as? Int ?? 0,
            metrics: map["metrics"] as? [String: Any] ?? [:],
            behavior: map["behavior"] as? [String: Any]
        )

    case "session_error":
        return SessionErrorEvent(
            sessionId: sessionId,
            errorCode: map["error_code"] as? String ?? "unknown",
            message: map["message"] as? String ?? ""
        )

    case "biosignal_frame":
        return BiosignalFrame(
            sessionId: sessionId,
            seq: map["seq"] as? Int ?? 0,
            emittedAtMs: map["emitted_at_ms"] as? Int64 ?? 0,
            samples: map["samples"] as? [[String: Any]] ?? []
        )

    default:
        return nil
    }
}
