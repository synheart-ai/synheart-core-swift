import Foundation

/// A handle to an active or completed session.
///
/// Returned by `Synheart.startSession()` and `Synheart.currentSession`.
/// See RFC-CORE-0007 Section 5.2.
public struct SessionHandle {
    public let sessionId: String
    public let startedAtMs: Int64
    public let mode: SynheartMode

    public init(sessionId: String, startedAtMs: Int64, mode: SynheartMode) {
        self.sessionId = sessionId
        self.startedAtMs = startedAtMs
        self.mode = mode
    }
}
