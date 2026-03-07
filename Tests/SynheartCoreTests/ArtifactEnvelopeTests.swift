import XCTest
@testable import SynheartCore

final class ArtifactEnvelopeTests: XCTestCase {

    func testSerializesAndDeserializes() {
        let envelope = ArtifactEnvelope(
            artifactId: "art_123",
            subjectId: "usr_456",
            sessionId: "sess_789",
            type: "hsi_window",
            startMs: 1000,
            endMs: 2000,
            seq: 1,
            schemaName: "hsi_window",
            schemaVersion: "1.0",
            nonceB64: "bm9uY2U=",
            payloadSha256: "abc123",
            ciphertextB64: "Y2lwaGVydGV4dA=="
        )

        let json = envelope.toJson()
        XCTAssertEqual(json["artifact_id"] as? String, "art_123")
        XCTAssertEqual(json["subject_id"] as? String, "usr_456")
        XCTAssertEqual(json["session_id"] as? String, "sess_789")
        XCTAssertEqual(json["type"] as? String, "hsi_window")

        let timeRange = json["time_range"] as! [String: Any]
        XCTAssertEqual(timeRange["start_ms"] as? Int64, 1000)

        let deserialized = ArtifactEnvelope.fromJson(json)
        XCTAssertEqual(deserialized.artifactId, "art_123")
        XCTAssertEqual(deserialized.subjectId, "usr_456")
        XCTAssertEqual(deserialized.sessionId, "sess_789")
        XCTAssertEqual(deserialized.startMs, 1000)
        XCTAssertEqual(deserialized.endMs, 2000)
        XCTAssertEqual(deserialized.seq, 1)
        XCTAssertEqual(deserialized.nonceB64, "bm9uY2U=")
    }

    func testHandlesNullSessionId() {
        let envelope = ArtifactEnvelope(
            artifactId: "art_123",
            subjectId: "usr_456",
            type: "baseline_snapshot",
            startMs: 1000,
            endMs: 2000,
            schemaName: "baseline",
            schemaVersion: "1.0",
            nonceB64: "bm9uY2U=",
            payloadSha256: "abc123",
            ciphertextB64: "Y2lwaGVydGV4dA=="
        )

        let json = envelope.toJson()
        XCTAssertNil(json["session_id"])

        let deserialized = ArtifactEnvelope.fromJson(json)
        XCTAssertNil(deserialized.sessionId)
    }

    func testSyncResultDefaults() {
        let result = SyncResult()
        XCTAssertEqual(result.pushed, 0)
        XCTAssertEqual(result.pulled, 0)
        XCTAssertEqual(result.conflictsResolved, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testSyncStatusFields() {
        let status = SyncStatus(
            enabled: true,
            lastSuccessMs: 1234567890,
            pendingUploadCount: 5,
            cursor: "abc"
        )
        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.lastSuccessMs, 1234567890)
        XCTAssertEqual(status.pendingUploadCount, 5)
        XCTAssertEqual(status.cursor, "abc")
    }
}
