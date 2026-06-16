import Foundation
import CryptoKit
import Combine

/// Transport-independent, opt-in phone-side consumer of the watch→phone edge
/// wire contract (`docs/EDGE-WIRE-CONTRACT.md` in `synheart-edge`).
///
/// This is the canonical phone-side counterpart to the watch producer
/// (`synheart-core-swift-edge` / `PhoneRelay`). Every app used to re-implement
/// watch→phone ingest; `EdgeIngest` gives the SDK one consumer.
///
/// It deliberately holds **no** `WatchConnectivity` import so it compiles and
/// unit-tests on any platform (`swift test` runs on macOS, where `WCSession`
/// is unavailable) — mirroring the `PhoneCommandRouter` testable-core pattern
/// on the watch side. A thin `WCSession` adapter
/// (``EdgeIngestSessionAdapter``) feeds raw `[String: Any]` bodies in and
/// sends the produced ACK back; all parsing/validation/dedupe lives here.
///
/// The Kotlin phone SDK uses the same `EdgeIngest` concept with the same
/// callback semantics for cross-platform parity.
///
/// ## Contract mapping
/// - `hr_sample`   → ``Delegate/edgeIngestDidReceiveHrSample(_:)``     (contract §3.1)
/// - `bio_sample`  → ``Delegate/edgeIngestDidReceiveBioSample(_:)``    (contract §3.2)
/// - `hsi_artifact`→ ``Delegate/edgeIngestDidAcceptArtifact(_:)``      (contract §3.3, §5)
/// - session events→ ``Delegate/edgeIngestDidReceiveSessionEvent(type:body:)`` (contract §3.4)
///
/// All keys/types match the contract exactly: epoch-ms `*_ms` keys, `bpm`
/// double, `rr_intervals_ms` array of doubles, `accel` `{x,y,z}` in g, and the
/// artifact envelope keys of §3.3.
public final class EdgeIngest {

    // MARK: - Supported versions

    /// Supported inner HSI payload versions for consumers in this generation
    /// (contract §0). A payload outside this set is flagged/logged as a
    /// producer-drift signal and surfaced — never silently rejected on the
    /// version alone.
    public static let supportedHsiVersions: Set<String> = ["1.1", "1.2", "1.3"]

    // MARK: - Wire `type` discriminators (contract §1)

    /// The body `type` values this consumer recognises. iOS routes a single
    /// `WCSession` channel by this field (the contract's iOS column).
    public enum MessageType: String {
        case hrSample = "hr_sample"
        case bioSample = "bio_sample"
        case hsiArtifact = "hsi_artifact"
    }

    // MARK: - Typed payloads

    /// Parsed `hr_sample` body (contract §3.1).
    public struct HrSample: Equatable {
        public let bpm: Double
        public let timestampMs: Int64
        public let source: String?
        public init(bpm: Double, timestampMs: Int64, source: String?) {
            self.bpm = bpm
            self.timestampMs = timestampMs
            self.source = source
        }
    }

    /// Three-axis acceleration in g (contract §2 / §3.2 `accel`).
    public struct Accel: Equatable {
        public let x: Double
        public let y: Double
        public let z: Double
        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    /// Parsed `bio_sample` body (contract §3.2). `rrIntervalsMs` is empty when
    /// omitted; `accel`/`source` are nil when omitted (never fabricated, §2).
    public struct BioSample: Equatable {
        public let bpm: Double
        public let timestampMs: Int64
        public let rrIntervalsMs: [Double]
        public let accel: Accel?
        public let source: String?
        public init(bpm: Double, timestampMs: Int64, rrIntervalsMs: [Double], accel: Accel?, source: String?) {
            self.bpm = bpm
            self.timestampMs = timestampMs
            self.rrIntervalsMs = rrIntervalsMs
            self.accel = accel
            self.source = source
        }
    }

    /// A validated, accepted `hsi_artifact` envelope (contract §3.3). The
    /// `payloadJson` is the opaque HSI JSON; `hsiVersionSupported` reflects the
    /// §0 version check (the artifact is still surfaced when `false` — drift is
    /// flagged, not dropped).
    public struct Artifact: Equatable {
        public let artifactId: String
        public let sessionId: String?
        public let seq: Int?
        public let createdAtMs: Int64?
        public let schemaVersion: String?
        public let hsiVersion: String?
        public let hsiVersionSupported: Bool
        public let payloadHashSha256: String
        public let payloadJson: String
        public let deliveryMode: String?
        public let sessionOrigin: String?
        public let sessionKind: String?
    }

    // MARK: - Reactive event family

    /// Sealed family of typed edge events emitted on ``events``. Mirrors the
    /// Dart role model's `EdgeEvent` (`HrEvent | BioEvent | ArtifactEvent |
    /// SessionEventWrap`) and the Kotlin `EdgeEvent` sealed class, so all three
    /// SDKs expose the same reactive surface. Each case fires in lock-step with
    /// the corresponding ``Delegate`` callback (additive — the delegate is
    /// unchanged).
    public enum EdgeEvent {
        /// §3.1 — an HR sample was parsed.
        case hr(HrSample)
        /// §3.2 — a biosignal sample was parsed.
        case bio(BioSample)
        /// §3.3 — an artifact was accepted (verified + non-duplicate).
        case artifact(Artifact)
        /// §3.4 — a non-sample/-artifact session event (raw body passed through).
        case sessionEvent(type: String, body: [String: Any])
    }

    // MARK: - Delegate

    /// Typed consumer callbacks. All optional so apps wire only what they need.
    public protocol Delegate: AnyObject {
        func edgeIngestDidReceiveHrSample(_ sample: HrSample)
        func edgeIngestDidReceiveBioSample(_ sample: BioSample)
        /// Called once per **accepted** artifact (after hash verification and
        /// dedupe). The id is recorded for the next ACK.
        func edgeIngestDidAcceptArtifact(_ artifact: Artifact)
        /// A body whose `type` is none of the sample/artifact discriminators
        /// (e.g. a session event, contract §3.4). The raw body is passed
        /// through unparsed.
        func edgeIngestDidReceiveSessionEvent(type: String, body: [String: Any])
        /// §5 — a deterministically-corrupt artifact: the same `artifact_id`
        /// mismatched its hash ``EdgeIngest/poisonPillThreshold`` times. It is
        /// dead-lettered — surfaced here as a hard error AND ack-to-discarded so
        /// it stops blocking the watch's delete-on-ACK outbox. Optional.
        func edgeIngestDidDeadLetterArtifact(artifactId: String, expected: String, actual: String, attempts: Int)
    }

    // MARK: - Default no-op delegate conformance

    public weak var delegate: Delegate?

    /// After this many hash mismatches for the SAME `artifact_id`,
    /// the artifact is dead-lettered (hard error + ack-to-discard) so a
    /// deterministically-corrupt artifact stops resending forever (contract §5).
    public static let poisonPillThreshold = 3

    /// Cap of the seen-artifact LRU. Re-acking a long-evicted
    /// stray is harmless per contract §5, so eviction is safe.
    public static let seenLruCapacity = 4096

    // MARK: - State

    /// In-memory LRU of artifact ids already accepted, for dedupe (contract §5),
    /// bounded to ``seenLruCapacity`` entries: `seenOrder` is the
    /// recency queue (front = eldest), `seenArtifactIds` the O(1) membership set.
    /// Re-acking a long-evicted stray is harmless per contract §5, so a bounded
    /// LRU keeps memory flat over a long-lived process.
    private var seenArtifactIds: Set<String> = []
    private var seenOrder: [String] = []
    /// Per-id hash-mismatch counter for poison-pill detection.
    private var mismatchCounts: [String: Int] = [:]
    /// Accepted (or dead-lettered, or re-acked-duplicate) ids not yet drained
    /// into an ACK. Idempotent — an id is never queued twice.
    private var pendingAckArtifactIds: [String] = []
    private let lock = NSLock()

    /// Backing subject for the broadcast ``events`` publisher.
    private let eventsSubject = PassthroughSubject<EdgeEvent, Never>()

    /// Broadcast publisher of typed edge events (Combine ergonomics, parity
    /// with the Dart role model's broadcast `Stream<EdgeEvent>` and the Kotlin
    /// `SharedFlow<EdgeEvent>`). Emits in lock-step with the ``Delegate``
    /// callbacks; supports multiple subscribers. Additive — does not alter any
    /// existing delegate/`Outcome` behaviour.
    ///
    /// NOT AUTHORITATIVE: the synchronous ``Delegate`` is the source of truth for
    /// "received"; `acked + seen` state is updated independently of whether any
    /// reactive subscriber observed the event. This publisher
    /// is an additive, best-effort convenience.
    public var events: AnyPublisher<EdgeEvent, Never> {
        eventsSubject.eraseToAnyPublisher()
    }

    /// Queue [id] for ACK exactly once (idempotent set semantics over the
    /// `[String]` buffer). Caller MUST hold ``lock``.
    private func enqueueAckLocked(_ id: String) {
        if !pendingAckArtifactIds.contains(id) {
            pendingAckArtifactIds.append(id)
        }
    }

    /// Record [id] as seen in the bounded LRU, refreshing recency and evicting
    /// the eldest while over ``seenLruCapacity``. Caller MUST hold ``lock``.
    private func recordSeenLocked(_ id: String) {
        if let existing = seenOrder.firstIndex(of: id) {
            seenOrder.remove(at: existing)
        }
        seenOrder.append(id)
        seenArtifactIds.insert(id)
        while seenOrder.count > EdgeIngest.seenLruCapacity {
            let evicted = seenOrder.removeFirst()
            seenArtifactIds.remove(evicted)
        }
    }

    public init(delegate: Delegate? = nil) {
        self.delegate = delegate
    }

    // MARK: - Ingest

    /// The outcome of consuming one body. Returned (in addition to firing the
    /// delegate) so the WCSession adapter and tests can branch without state.
    public enum Outcome: Equatable {
        case hrSample(HrSample)
        case bioSample(BioSample)
        /// Artifact accepted (verified + not a duplicate).
        case artifactAccepted(Artifact)
        /// Artifact ignored because its `artifact_id` was already seen (§5).
        case artifactDuplicate(artifactId: String)
        /// Artifact rejected because `payload_hash_sha256` ≠ sha256(payload_json)
        /// (first/normal mismatch — NOT surfaced, NOT acked).
        case artifactHashMismatch(artifactId: String)
        /// Artifact dead-lettered after ``EdgeIngest/poisonPillThreshold``
        /// hash mismatches for the same id: surfaced as a hard error
        /// AND ack-to-discarded so it stops blocking the outbox.
        case artifactDeadLettered(artifactId: String)
        /// Body recognised as a non-sample event `type` (contract §3.4).
        case sessionEvent(type: String)
        /// Body dropped: missing/invalid `type`, missing required fields, or
        /// otherwise malformed. Never crashes.
        case dropped(reason: String)
    }

    /// Consume one incoming wire body. Safe for any malformed input — returns
    /// ``Outcome/dropped(reason:)`` and logs rather than crashing. Thread-safe.
    @discardableResult
    public func ingest(_ body: [String: Any]) -> Outcome {
        guard let typeRaw = body["type"] as? String else {
            return drop("missing `type` field")
        }
        // Contract §1: every body MUST carry `type`, so an empty `type` is
        // malformed → drop (parity with Kotlin/Dart, which both drop it; Swift
        // previously mis-routed an empty type as a session event).
        guard !typeRaw.isEmpty else {
            return drop("empty `type` field")
        }

        switch MessageType(rawValue: typeRaw) {
        case .hrSample:
            return ingestHrSample(body)
        case .bioSample:
            return ingestBioSample(body)
        case .hsiArtifact:
            return ingestArtifact(body)
        case .none:
            // Not a sample/artifact discriminator → treat as a session event
            // (contract §3.4 uses event-specific `type` values on iOS) and
            // pass through to the delegate unparsed.
            delegate?.edgeIngestDidReceiveSessionEvent(type: typeRaw, body: body)
            eventsSubject.send(.sessionEvent(type: typeRaw, body: body))
            return .sessionEvent(type: typeRaw)
        }
    }

    // MARK: - ACK (contract §5)

    /// Build (but do not send) the `artifact_ack` command body for all
    /// currently-pending accepted ids, and clear the pending buffer. Shape per
    /// contract §4/§5: `{ "command": "artifact_ack", "artifact_ids": [...] }`.
    /// Returns `nil` when there is nothing to acknowledge.
    public func drainAck() -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard !pendingAckArtifactIds.isEmpty else { return nil }
        let ids = pendingAckArtifactIds
        pendingAckArtifactIds.removeAll(keepingCapacity: true)
        return EdgeIngest.makeAckBody(artifactIds: ids)
    }

    /// Pure constructor for the ACK body, exposed for the adapter and tests.
    public static func makeAckBody(artifactIds: [String]) -> [String: Any] {
        return [
            "command": "artifact_ack",
            "artifact_ids": artifactIds
        ]
    }

    /// Ids accepted but not yet drained into an ACK (read-only snapshot).
    public var pendingAckIds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return pendingAckArtifactIds
    }

    // MARK: - Hashing (mirrors producer: SHA256 over UTF-8 of payload_json)

    /// Lowercase hex SHA-256 of the UTF-8 bytes of `payloadJson` — identical to
    /// the producer's `HsiArtifactEnvelope.wrap` (`synheart-core-swift-edge`).
    public static func sha256Hex(of payloadJson: String) -> String {
        let digest = SHA256.hash(data: Data(payloadJson.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Parsers

    private func ingestHrSample(_ body: [String: Any]) -> Outcome {
        guard let bpm = EdgeIngest.double(body["bpm"]) else {
            return drop("hr_sample missing/invalid `bpm`")
        }
        guard let ts = EdgeIngest.int64(body["timestamp_ms"]) else {
            return drop("hr_sample missing/invalid `timestamp_ms`")
        }
        let sample = HrSample(bpm: bpm, timestampMs: ts, source: body["source"] as? String)
        delegate?.edgeIngestDidReceiveHrSample(sample)
        eventsSubject.send(.hr(sample))
        return .hrSample(sample)
    }

    private func ingestBioSample(_ body: [String: Any]) -> Outcome {
        guard let bpm = EdgeIngest.double(body["bpm"]) else {
            return drop("bio_sample missing/invalid `bpm`")
        }
        guard let ts = EdgeIngest.int64(body["timestamp_ms"]) else {
            return drop("bio_sample missing/invalid `timestamp_ms`")
        }
        // §2: omitted/empty when unavailable — coerce numbers tolerantly.
        let rr: [Double] = (body["rr_intervals_ms"] as? [Any])?.compactMap(EdgeIngest.double) ?? []
        let accel = EdgeIngest.parseAccel(body["accel"])
        let sample = BioSample(
            bpm: bpm,
            timestampMs: ts,
            rrIntervalsMs: rr,
            accel: accel,
            source: body["source"] as? String
        )
        delegate?.edgeIngestDidReceiveBioSample(sample)
        eventsSubject.send(.bio(sample))
        return .bioSample(sample)
    }

    private func ingestArtifact(_ body: [String: Any]) -> Outcome {
        guard let artifactId = body["artifact_id"] as? String, !artifactId.isEmpty else {
            return drop("hsi_artifact missing/invalid `artifact_id`")
        }
        guard let payloadJson = body["payload_json"] as? String else {
            return drop("hsi_artifact missing `payload_json` (id=\(artifactId))")
        }
        guard let declaredHash = body["payload_hash_sha256"] as? String else {
            return drop("hsi_artifact missing `payload_hash_sha256` (id=\(artifactId))")
        }

        // Hash verification (contract §3.3 / §5): reject + log on mismatch.
        let computed = EdgeIngest.sha256Hex(of: payloadJson)
        guard computed.caseInsensitiveCompare(declaredHash) == .orderedSame else {
            // Poison-pill handling: a deterministically-corrupt artifact would
            // otherwise be rejected-without-ack forever and starve the
            // delete-on-ACK outbox.
            // Count per-id mismatches; after the threshold, dead-letter it (hard
            // error + ack-to-discard). The first/normal mismatch keeps the old
            // behaviour: reject, don't surface, don't ack.
            lock.lock()
            let attempts = (mismatchCounts[artifactId] ?? 0) + 1
            mismatchCounts[artifactId] = attempts
            let deadLetter = attempts >= EdgeIngest.poisonPillThreshold
            if deadLetter {
                mismatchCounts.removeValue(forKey: artifactId)
                recordSeenLocked(artifactId)
                enqueueAckLocked(artifactId)
            }
            lock.unlock()

            if deadLetter {
                log("[EdgeIngest] artifact \(artifactId) hash mismatch x\(attempts) "
                    + "(declared=\(declaredHash) computed=\(computed)) — dead-lettering: "
                    + "ack-to-discard so it stops blocking the outbox")
                delegate?.edgeIngestDidDeadLetterArtifact(
                    artifactId: artifactId, expected: declaredHash, actual: computed, attempts: attempts)
                return .artifactDeadLettered(artifactId: artifactId)
            }
            log("[EdgeIngest] artifact \(artifactId) rejected (attempt \(attempts)): payload_hash_sha256 mismatch "
                + "(declared=\(declaredHash) computed=\(computed))")
            return .artifactHashMismatch(artifactId: artifactId)
        }

        // Dedupe by artifact_id (contract §5) — record under lock. On a
        // duplicate, DO NOT re-surface, but STILL queue the id for ACK
        // (idempotent) and return: the watch outbox is delete-on-ACK, so
        // a lost ACK makes it resend forever; re-acking duplicates is the point.
        lock.lock()
        let isDuplicate = seenArtifactIds.contains(artifactId)
        if isDuplicate {
            enqueueAckLocked(artifactId)
            recordSeenLocked(artifactId) // refresh LRU recency
        } else {
            recordSeenLocked(artifactId)
            enqueueAckLocked(artifactId)
        }
        lock.unlock()

        if isDuplicate {
            log("[EdgeIngest] artifact \(artifactId) duplicate — re-acking, not re-surfacing")
            return .artifactDuplicate(artifactId: artifactId)
        }

        // Version check (contract §0): prefer the envelope `hsi_version`, fall
        // back to the payload_json's own `hsi_version` (parity with the Dart
        // role model and Kotlin's `extractHsiVersionFromPayload`). Flag/log
        // drift (out-of-set OR absent) but still surface.
        let envelopeVersion = (body["hsi_version"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let hsiVersion = envelopeVersion ?? EdgeIngest.extractHsiVersionFromPayload(payloadJson)
        let versionSupported: Bool
        if let v = hsiVersion {
            versionSupported = EdgeIngest.supportedHsiVersions.contains(v)
            if !versionSupported {
                log("[EdgeIngest] artifact \(artifactId) hsi_version \"\(v)\" outside supported "
                    + "set \(EdgeIngest.supportedHsiVersions.sorted()) — producer drift, surfacing anyway")
            }
        } else {
            // No version present (neither envelope nor payload) — flag, surface.
            versionSupported = false
            log("[EdgeIngest] artifact \(artifactId) carries no `hsi_version` — flagging")
        }

        let artifact = Artifact(
            artifactId: artifactId,
            sessionId: body["session_id"] as? String,
            seq: EdgeIngest.int(body["seq"]),
            createdAtMs: EdgeIngest.int64(body["created_at_ms"]),
            schemaVersion: body["schema_version"] as? String,
            hsiVersion: hsiVersion,
            hsiVersionSupported: versionSupported,
            payloadHashSha256: declaredHash,
            payloadJson: payloadJson,
            deliveryMode: body["delivery_mode"] as? String,
            sessionOrigin: body["session_origin"] as? String,
            sessionKind: body["session_kind"] as? String
        )
        delegate?.edgeIngestDidAcceptArtifact(artifact)
        eventsSubject.send(.artifact(artifact))
        return .artifactAccepted(artifact)
    }

    // MARK: - Helpers (no force-unwraps anywhere)

    private func drop(_ reason: String) -> Outcome {
        log("[EdgeIngest] dropped body: \(reason)")
        return .dropped(reason: reason)
    }

    private func log(_ message: String) {
        SynheartLogger.log(message)
    }

    /// Tolerant numeric coercion — `NSNumber`/`Double`/`Int`/`String` → Double.
    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func int64(_ value: Any?) -> Int64? {
        switch value {
        case let i as Int64: return i
        case let i as Int: return Int64(i)
        case let n as NSNumber: return n.int64Value
        case let d as Double: return Int64(d)
        case let s as String: return Int64(s)
        default: return nil
        }
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let n as NSNumber: return n.intValue
        case let d as Double: return Int(d)
        case let s as String: return Int(s)
        default: return nil
        }
    }

    /// Parity with the Dart/Kotlin `extractHsiVersionFromPayload`: read
    /// `hsi_version` from the opaque payload when the envelope omits it. Returns
    /// nil on any parse failure or absence (the payload may not be JSON).
    private static func extractHsiVersionFromPayload(_ payloadJson: String) -> String? {
        guard let data = payloadJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = obj["hsi_version"] as? String,
              !v.isEmpty else {
            return nil
        }
        return v
    }

    private static func parseAccel(_ value: Any?) -> Accel? {
        guard let obj = value as? [String: Any],
              let x = double(obj["x"]),
              let y = double(obj["y"]),
              let z = double(obj["z"]) else {
            return nil
        }
        return Accel(x: x, y: y, z: z)
    }
}

// MARK: - Delegate default implementations (keeps the protocol additive)

public extension EdgeIngest.Delegate {
    /// Default no-op so existing conformers compile without implementing the
    /// poison-pill hook. Apps override only what they need.
    func edgeIngestDidDeadLetterArtifact(
        artifactId: String, expected: String, actual: String, attempts: Int
    ) {}
}
