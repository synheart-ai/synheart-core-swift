import XCTest
import Combine
@testable import SynheartCore

/// Pure, transport-independent tests for ``EdgeIngest`` — no `WatchConnectivity`
/// import, so they run under `swift test` on macOS. They assert the parsed keys
/// match the Synheart edge wire contract (sections cited per test).
final class EdgeIngestTests: XCTestCase {

    /// Collecting delegate to assert callback semantics.
    final class Recorder: EdgeIngest.Delegate {
        var hr: [EdgeIngest.HrSample] = []
        var bio: [EdgeIngest.BioSample] = []
        var artifacts: [EdgeIngest.Artifact] = []
        var events: [(type: String, body: [String: Any])] = []
        var deadLetters: [(artifactId: String, attempts: Int)] = []

        func edgeIngestDidReceiveHrSample(_ sample: EdgeIngest.HrSample) { hr.append(sample) }
        func edgeIngestDidReceiveBioSample(_ sample: EdgeIngest.BioSample) { bio.append(sample) }
        func edgeIngestDidAcceptArtifact(_ artifact: EdgeIngest.Artifact) { artifacts.append(artifact) }
        func edgeIngestDidReceiveSessionEvent(type: String, body: [String: Any]) { events.append((type, body)) }
        func edgeIngestDidDeadLetterArtifact(artifactId: String, expected: String, actual: String, attempts: Int) {
            deadLetters.append((artifactId, attempts))
        }
    }

    private func makeArtifactBody(
        id: String = "hsi_abcdef012345_0",
        payloadJson: String,
        hash: String? = nil,
        hsiVersion: String? = "1.3"
    ) -> [String: Any] {
        // contract §3.3 keys
        var body: [String: Any] = [
            "type": "hsi_artifact",
            "artifact_id": id,
            "session_id": "sess-1",
            "seq": 0,
            "created_at_ms": Int64(1_718_900_000_000),
            "schema_version": "1.1",
            "payload_hash_sha256": hash ?? EdgeIngest.sha256Hex(of: payloadJson),
            "payload_json": payloadJson,
            "delivery_mode": "REALTIME",
            "session_origin": "PHONE",
            "session_kind": "FOCUS"
        ]
        if let v = hsiVersion { body["hsi_version"] = v }
        return body
    }

    // MARK: hr_sample (contract §3.1)

    func testHrSampleParsesWithSource() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        // §3.1: { type, bpm, timestamp_ms, source }
        let outcome = ingest.ingest([
            "type": "hr_sample",
            "bpm": 72.0,
            "timestamp_ms": Int64(1_718_900_000_000),
            "source": "healthkit"
        ])
        XCTAssertEqual(outcome, .hrSample(EdgeIngest.HrSample(bpm: 72.0, timestampMs: 1_718_900_000_000, source: "healthkit")))
        XCTAssertEqual(r.hr.count, 1)
        XCTAssertEqual(r.hr.first?.bpm, 72.0)
        XCTAssertEqual(r.hr.first?.timestampMs, 1_718_900_000_000)
        XCTAssertEqual(r.hr.first?.source, "healthkit")
    }

    func testHrSampleOmittedSourceIsNil() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        _ = ingest.ingest(["type": "hr_sample", "bpm": 60.0, "timestamp_ms": 1])
        XCTAssertNil(r.hr.first?.source)
    }

    func testHrSampleMissingBpmDropped() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        let outcome = ingest.ingest(["type": "hr_sample", "timestamp_ms": 1])
        if case .dropped = outcome {} else { XCTFail("expected dropped") }
        XCTAssertTrue(r.hr.isEmpty)
    }

    // MARK: bio_sample (contract §3.2)

    func testBioSampleFullParse() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        // §3.2 keys: bpm, timestamp_ms, rr_intervals_ms[], accel{x,y,z}, source
        _ = ingest.ingest([
            "type": "bio_sample",
            "bpm": 72.0,
            "timestamp_ms": Int64(1_718_900_000_000),
            "rr_intervals_ms": [820.0, 835.0],
            "accel": ["x": 0.01, "y": -0.02, "z": 0.98],
            "source": "healthkit"
        ])
        let s = try? XCTUnwrap(r.bio.first)
        XCTAssertEqual(s?.bpm, 72.0)
        XCTAssertEqual(s?.timestampMs, 1_718_900_000_000)
        XCTAssertEqual(s?.rrIntervalsMs, [820.0, 835.0])
        XCTAssertEqual(s?.accel, EdgeIngest.Accel(x: 0.01, y: -0.02, z: 0.98))
        XCTAssertEqual(s?.source, "healthkit")
    }

    func testBioSampleOmittedOptionals() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        // §2: rr/accel/source omitted → empty/nil, never fabricated.
        _ = ingest.ingest(["type": "bio_sample", "bpm": 80.0, "timestamp_ms": 5])
        let s = r.bio.first
        XCTAssertEqual(s?.rrIntervalsMs, [])
        XCTAssertNil(s?.accel)
        XCTAssertNil(s?.source)
    }

    // MARK: hsi_artifact — accept, dedupe, hash, version (§3.3, §5, §0)

    func testArtifactAcceptedSurfacesTypedCallback() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        let payload = #"{"hsi_version":"1.3","foo":1}"#
        let outcome = ingest.ingest(makeArtifactBody(payloadJson: payload))
        guard case .artifactAccepted(let a) = outcome else { return XCTFail("expected accepted") }
        XCTAssertEqual(a.artifactId, "hsi_abcdef012345_0")
        XCTAssertEqual(a.sessionId, "sess-1")
        XCTAssertEqual(a.seq, 0)
        XCTAssertEqual(a.createdAtMs, 1_718_900_000_000)
        XCTAssertEqual(a.schemaVersion, "1.1")
        XCTAssertEqual(a.hsiVersion, "1.3")
        XCTAssertTrue(a.hsiVersionSupported)
        XCTAssertEqual(a.payloadJson, payload)
        XCTAssertEqual(a.deliveryMode, "REALTIME")
        XCTAssertEqual(a.sessionOrigin, "PHONE")
        XCTAssertEqual(a.sessionKind, "FOCUS")
        XCTAssertEqual(r.artifacts.count, 1)
    }

    func testArtifactDedupeSameIdAcceptedOnce() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        let body = makeArtifactBody(payloadJson: #"{"hsi_version":"1.3"}"#)
        let first = ingest.ingest(body)
        let second = ingest.ingest(body)
        guard case .artifactAccepted = first else { return XCTFail("first should accept") }
        XCTAssertEqual(second, .artifactDuplicate(artifactId: "hsi_abcdef012345_0"))
        XCTAssertEqual(r.artifacts.count, 1, "duplicate artifact_id must not re-surface")
        XCTAssertEqual(ingest.pendingAckIds, ["hsi_abcdef012345_0"], "dedupe must not double-queue the ack")
    }

    func testArtifactHashMismatchRejected() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        // §3.3/§5: payload_hash_sha256 must equal sha256(payload_json).
        let body = makeArtifactBody(payloadJson: #"{"hsi_version":"1.3"}"#, hash: "deadbeef")
        let outcome = ingest.ingest(body)
        XCTAssertEqual(outcome, .artifactHashMismatch(artifactId: "hsi_abcdef012345_0"))
        XCTAssertTrue(r.artifacts.isEmpty, "mismatched artifact must not surface")
        XCTAssertNil(ingest.drainAck(), "rejected artifact must not be acked")
    }

    func testUnsupportedHsiVersionFlaggedButSurfaced() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        // §0: version outside ["1.1","1.2","1.3"] is flagged, not silently dropped.
        let body = makeArtifactBody(payloadJson: #"{"hsi_version":"2.0"}"#, hsiVersion: "2.0")
        let outcome = ingest.ingest(body)
        guard case .artifactAccepted(let a) = outcome else { return XCTFail("expected accepted (flagged)") }
        XCTAssertEqual(a.hsiVersion, "2.0")
        XCTAssertFalse(a.hsiVersionSupported, "out-of-range version must be flagged")
        XCTAssertEqual(r.artifacts.count, 1, "drift is surfaced, not dropped")
    }

    func testSupportedHsiVersionsMatchContract() {
        // contract §0: ["1.1","1.2","1.3"]
        XCTAssertEqual(EdgeIngest.supportedHsiVersions, ["1.1", "1.2", "1.3"])
    }

    func testArtifactMissingPayloadDropped() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        let outcome = ingest.ingest([
            "type": "hsi_artifact",
            "artifact_id": "x",
            "payload_hash_sha256": "abc"
        ])
        if case .dropped = outcome {} else { XCTFail("expected dropped") }
    }

    // MARK: ACK body shape (contract §4/§5)

    func testAckBodyShape() {
        let body = EdgeIngest.makeAckBody(artifactIds: ["a", "b"])
        XCTAssertEqual(body["command"] as? String, "artifact_ack")
        XCTAssertEqual(body["artifact_ids"] as? [String], ["a", "b"])
        XCTAssertEqual(body.count, 2, "ack body carries exactly command + artifact_ids")
    }

    func testDrainAckCollectsThenClears() {
        let ingest = EdgeIngest()
        _ = ingest.ingest(makeArtifactBody(id: "hsi_a_0", payloadJson: "{}"))
        _ = ingest.ingest(makeArtifactBody(id: "hsi_b_1", payloadJson: "{}"))
        let ack = ingest.drainAck()
        XCTAssertEqual(ack?["command"] as? String, "artifact_ack")
        XCTAssertEqual(ack?["artifact_ids"] as? [String], ["hsi_a_0", "hsi_b_1"])
        XCTAssertNil(ingest.drainAck(), "drain must clear pending ids")
    }

    // MARK: Malformed / unknown bodies (never crash)

    func testMissingTypeDropped() {
        let ingest = EdgeIngest()
        let outcome = ingest.ingest(["bpm": 70.0])
        if case .dropped = outcome {} else { XCTFail("expected dropped") }
    }

    func testUnknownTypeRoutedAsSessionEvent() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        // §3.4: non-sample/artifact `type` values are session events.
        let outcome = ingest.ingest(["type": "session_started", "session_id": "s1"])
        XCTAssertEqual(outcome, .sessionEvent(type: "session_started"))
        XCTAssertEqual(r.events.first?.type, "session_started")
    }

    func testGarbageBodyDoesNotCrash() {
        let ingest = EdgeIngest()
        // Wrong-typed values everywhere — must not crash, no force-unwraps.
        _ = ingest.ingest(["type": 42])
        _ = ingest.ingest(["type": "hr_sample", "bpm": "not-a-number", "timestamp_ms": [1, 2]])
        _ = ingest.ingest(["type": "bio_sample", "bpm": NSNull(), "timestamp_ms": NSNull()])
        _ = ingest.ingest(["type": "hsi_artifact"])
        _ = ingest.ingest([:])
        // Reaching here without a crash is the assertion.
        XCTAssertTrue(true)
    }

    // MARK: Numeric tolerance (WCSession may box numbers as NSNumber)

    func testNumericCoercionTolerant() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        _ = ingest.ingest([
            "type": "hr_sample",
            "bpm": NSNumber(value: 65),
            "timestamp_ms": NSNumber(value: 1_718_900_000_000 as Int64)
        ])
        XCTAssertEqual(r.hr.first?.bpm, 65.0)
        XCTAssertEqual(r.hr.first?.timestampMs, 1_718_900_000_000)
    }

    func testSha256HexMatchesKnownVector() {
        // sha256("") = e3b0c442...855 — confirms producer-parity hashing.
        XCTAssertEqual(
            EdgeIngest.sha256Hex(of: ""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    // MARK: - Reactive `events` publisher (parity with Dart `Stream<EdgeEvent>`)

    func testEventsStreamEmitsTypedEvents() {
        let ingest = EdgeIngest()
        var received: [EdgeIngest.EdgeEvent] = []
        let cancellable = ingest.events.sink { received.append($0) }
        defer { cancellable.cancel() }

        let payload = #"{"hsi_version":"1.3","foo":1}"#
        _ = ingest.ingest(["type": "hr_sample", "bpm": 72.0, "timestamp_ms": Int64(10)])
        _ = ingest.ingest(["type": "bio_sample", "bpm": 80.0, "timestamp_ms": Int64(20)])
        _ = ingest.ingest(makeArtifactBody(payloadJson: payload))
        _ = ingest.ingest(["type": "session_started", "session_id": "s1"])

        XCTAssertEqual(received.count, 4)
        guard case .hr(let hr) = received[0] else { return XCTFail("expected .hr") }
        XCTAssertEqual(hr.bpm, 72.0)
        guard case .bio(let bio) = received[1] else { return XCTFail("expected .bio") }
        XCTAssertEqual(bio.bpm, 80.0)
        guard case .artifact(let a) = received[2] else { return XCTFail("expected .artifact") }
        XCTAssertEqual(a.artifactId, "hsi_abcdef012345_0")
        XCTAssertTrue(a.hsiVersionSupported)
        guard case .sessionEvent(let type, _) = received[3] else { return XCTFail("expected .sessionEvent") }
        XCTAssertEqual(type, "session_started")
    }

    func testEventsStreamFiresInLockStepWithDelegate() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        var received: [EdgeIngest.EdgeEvent] = []
        let cancellable = ingest.events.sink { received.append($0) }
        defer { cancellable.cancel() }

        _ = ingest.ingest(["type": "hr_sample", "bpm": 60.0, "timestamp_ms": Int64(1)])
        // Delegate and stream both fired exactly once, additively.
        XCTAssertEqual(r.hr.count, 1)
        XCTAssertEqual(received.count, 1)
    }

    func testEventsStreamSupportsMultipleSubscribers() {
        let ingest = EdgeIngest()
        var a: [EdgeIngest.EdgeEvent] = []
        var b: [EdgeIngest.EdgeEvent] = []
        let ca = ingest.events.sink { a.append($0) }
        let cb = ingest.events.sink { b.append($0) }
        defer { ca.cancel(); cb.cancel() }

        _ = ingest.ingest(["type": "hr_sample", "bpm": 60.0, "timestamp_ms": Int64(1)])
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 1, "broadcast: both subscribers receive the event")
    }

    func testDuplicateArtifactDoesNotReEmit() {
        let ingest = EdgeIngest()
        var received: [EdgeIngest.EdgeEvent] = []
        let cancellable = ingest.events.sink { received.append($0) }
        defer { cancellable.cancel() }

        let body = makeArtifactBody(payloadJson: #"{"hsi_version":"1.3"}"#)
        _ = ingest.ingest(body)
        _ = ingest.ingest(body)
        XCTAssertEqual(received.count, 1, "duplicate artifact_id must not re-emit on the stream")
    }

    // MARK: - hsi_version payload fallback (parity with Dart/Kotlin)

    func testHsiVersionFallsBackToPayloadWhenEnvelopeOmitted() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        // §0: envelope omits hsi_version; the payload carries "1.2".
        let body = makeArtifactBody(payloadJson: #"{"hsi_version":"1.2"}"#, hsiVersion: nil)
        let outcome = ingest.ingest(body)
        guard case .artifactAccepted(let a) = outcome else { return XCTFail("expected accepted") }
        XCTAssertEqual(a.hsiVersion, "1.2", "must fall back to payload hsi_version")
        XCTAssertTrue(a.hsiVersionSupported, "1.2 is in the supported set")
        XCTAssertEqual(r.artifacts.count, 1)
    }

    func testHsiVersionEnvelopePreferredOverPayload() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        // Envelope "1.1" must win over payload "1.3".
        let body = makeArtifactBody(payloadJson: #"{"hsi_version":"1.3"}"#, hsiVersion: "1.1")
        guard case .artifactAccepted(let a) = ingest.ingest(body) else { return XCTFail("expected accepted") }
        XCTAssertEqual(a.hsiVersion, "1.1", "envelope hsi_version is preferred over payload")
    }

    func testHsiVersionAbsentBothEnvelopeAndPayloadFlaggedButSurfaced() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        // Neither envelope nor payload carries hsi_version → flagged, still surfaced.
        let body = makeArtifactBody(payloadJson: #"{"foo":1}"#, hsiVersion: nil)
        guard case .artifactAccepted(let a) = ingest.ingest(body) else { return XCTFail("expected accepted") }
        XCTAssertNil(a.hsiVersion)
        XCTAssertFalse(a.hsiVersionSupported)
        XCTAssertEqual(r.artifacts.count, 1, "absent version is surfaced, not dropped")
    }

    // MARK: - Duplicate handling — a duplicate must still be re-acked (delete-on-ACK outbox)

    func testDuplicateArtifactIsReAcked() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        let body = makeArtifactBody(payloadJson: #"{"hsi_version":"1.3"}"#)

        // First accept → drain (simulates a sent ACK that the watch never saw).
        guard case .artifactAccepted = ingest.ingest(body) else { return XCTFail("first should accept") }
        XCTAssertEqual(ingest.drainAck()?["artifact_ids"] as? [String], ["hsi_abcdef012345_0"])

        // Watch resends the same artifact (its outbox still has it). The
        // duplicate must NOT re-surface, but MUST re-populate the ACK buffer so
        // the adapter sends the ACK again.
        let second = ingest.ingest(body)
        XCTAssertEqual(second, .artifactDuplicate(artifactId: "hsi_abcdef012345_0"))
        XCTAssertEqual(r.artifacts.count, 1, "duplicate must not re-surface to the delegate")
        XCTAssertEqual(ingest.pendingAckIds, ["hsi_abcdef012345_0"], "duplicate must be re-queued for ACK")
        XCTAssertEqual(ingest.drainAck()?["artifact_ids"] as? [String], ["hsi_abcdef012345_0"])
    }

    func testDuplicateAckIsIdempotentNotDoubleQueued() {
        let ingest = EdgeIngest()
        let body = makeArtifactBody(payloadJson: "{}")
        _ = ingest.ingest(body) // accept → pending = [id]
        _ = ingest.ingest(body) // dup → still pending = [id], not [id, id]
        XCTAssertEqual(ingest.pendingAckIds, ["hsi_abcdef012345_0"])
    }

    // MARK: - Poison pill — dead-letter a deterministically-corrupt artifact after K=3

    func testPoisonPillDeadLetteredAfterThreeMismatches() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        let bad = makeArtifactBody(payloadJson: #"{"hsi_version":"1.3"}"#, hash: "deadbeef")

        // Attempts 1 and 2: normal rejection — not surfaced, not acked, no dead-letter.
        XCTAssertEqual(ingest.ingest(bad), .artifactHashMismatch(artifactId: "hsi_abcdef012345_0"))
        XCTAssertEqual(ingest.ingest(bad), .artifactHashMismatch(artifactId: "hsi_abcdef012345_0"))
        XCTAssertTrue(r.deadLetters.isEmpty)
        XCTAssertNil(ingest.drainAck(), "sub-threshold mismatches must not be acked")

        // Attempt 3: dead-letter — hard error + ack-to-discard.
        XCTAssertEqual(ingest.ingest(bad), .artifactDeadLettered(artifactId: "hsi_abcdef012345_0"))
        XCTAssertEqual(r.deadLetters.count, 1)
        XCTAssertEqual(r.deadLetters.first?.attempts, 3)
        XCTAssertTrue(r.artifacts.isEmpty, "poison pill must never surface as a valid artifact")
        XCTAssertEqual(ingest.drainAck()?["artifact_ids"] as? [String], ["hsi_abcdef012345_0"],
                       "dead-lettered id must be ack-to-discarded so it stops blocking the outbox")
    }

    func testPoisonPillThresholdIsThree() {
        XCTAssertEqual(EdgeIngest.poisonPillThreshold, 3)
    }

    // MARK: - Dedupe bound — the seen set is bounded (LRU eviction)

    func testDedupeSetIsBoundedAndEvictsOldest() {
        let ingest = EdgeIngest()
        let cap = EdgeIngest.seenLruCapacity
        // Fill past the cap with unique ids.
        for i in 0..<(cap + 100) {
            _ = ingest.ingest(makeArtifactBody(id: "hsi_\(i)", payloadJson: "{}"))
        }
        // The eldest id ("hsi_0") was evicted, so re-sending it accepts again
        // (a long-evicted stray re-accept is harmless per contract §5).
        let outcome = ingest.ingest(makeArtifactBody(id: "hsi_0", payloadJson: "{}"))
        guard case .artifactAccepted = outcome else {
            return XCTFail("evicted id should accept again, proving the set is bounded")
        }
        // A recently-seen id is still deduped.
        let recent = ingest.ingest(makeArtifactBody(id: "hsi_\(cap + 99)", payloadJson: "{}"))
        XCTAssertEqual(recent, .artifactDuplicate(artifactId: "hsi_\(cap + 99)"))
    }

    // MARK: - empty-`type` parity — Swift now DROPS empty type (matches Kotlin/Dart)

    func testEmptyTypeIsDropped() {
        let r = Recorder()
        let ingest = EdgeIngest(delegate: r)
        let outcome = ingest.ingest(["type": "", "session_id": "s1"])
        if case .dropped = outcome {} else { XCTFail("empty type must be dropped, not routed as a session event") }
        XCTAssertTrue(r.events.isEmpty, "empty type must not surface as a session event")
    }
}
