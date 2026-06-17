import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity

/// Thin, **opt-in**, additive `WCSession` adapter that wires the watch→phone
/// edge channel into the transport-independent ``EdgeIngest`` core.
///
/// This type is **not** activated by the SDK automatically — apps construct it
/// and assign it as (or forward to) their `WCSession` delegate. All parsing,
/// validation, dedupe, and ACK construction live in ``EdgeIngest``; this layer
/// only:
///   1. forwards `didReceiveMessage` / `didReceiveUserInfo` bodies into the
///      core (iOS routes one channel by the body `type`, contract §1), and
///   2. sends the produced `artifact_ack` body back over `WCSession`
///      (contract §4/§5).
///
/// `WatchConnectivity` is gated with `#if canImport` so the pure core still
/// compiles and unit-tests on macOS, where `WCSession` is unavailable — the
/// same gating strategy the watch producer uses for `PhoneRelay`.
public final class EdgeIngestSessionAdapter: NSObject {

    /// The transport-independent consumer. Exposed so apps can read pending
    /// ACK ids or trigger ``EdgeIngest/drainAck()`` on their own cadence.
    public let ingest: EdgeIngest

    /// When `true`, an `artifact_ack` is sent automatically after any body that
    /// results in a newly-accepted artifact (default). Set `false` to ACK on a
    /// custom cadence via ``sendPendingAck()``.
    public var autoAck: Bool

    /// The session the adapter sends ACKs over. Defaults to `WCSession.default`.
    private let session: WCSession

    public init(
        ingest: EdgeIngest,
        session: WCSession = .default,
        autoAck: Bool = true
    ) {
        self.ingest = ingest
        self.session = session
        self.autoAck = autoAck
        super.init()
    }

    /// Feed one received body through the core, then auto-ACK on any outcome
    /// that queued an id for ACK: a newly-accepted artifact, a duplicate (the
    /// watch's delete-on-ACK outbox resends forever on a lost ACK, so duplicates
    /// MUST be re-acked), or a poison-pill dead-letter (ack-to-discard). Both
    /// `WCSessionDelegate` receive entry points funnel here.
    public func handleReceived(_ body: [String: Any]) {
        let outcome = ingest.ingest(body)
        guard autoAck else { return }
        switch outcome {
        case .artifactAccepted, .artifactDuplicate, .artifactDeadLettered:
            sendPendingAck()
        default:
            break
        }
    }

    /// Drain pending accepted artifact ids and send a single `artifact_ack`
    /// over `WCSession`. No-op when nothing is pending.
    public func sendPendingAck() {
        guard let ackBody = ingest.drainAck() else { return }
        guard session.activationState == .activated else {
            SynheartLogger.log("[EdgeIngestSessionAdapter] WCSession not activated; ACK deferred")
            return
        }
        if session.isReachable {
            session.sendMessage(ackBody, replyHandler: nil) { error in
                SynheartLogger.log("[EdgeIngestSessionAdapter] ACK sendMessage failed: \(error.localizedDescription)")
            }
        } else {
            // Durable fallback so the watch can clear its outbox (contract §5).
            session.transferUserInfo(ackBody)
        }
    }
}

// MARK: - WCSessionDelegate

extension EdgeIngestSessionAdapter: WCSessionDelegate {
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleReceived(message)
    }

    public func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleReceived(message)
        replyHandler([:])
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleReceived(userInfo)
    }

    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            SynheartLogger.log("[EdgeIngestSessionAdapter] activation error: \(error.localizedDescription)")
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {}
    #endif
}

#endif
