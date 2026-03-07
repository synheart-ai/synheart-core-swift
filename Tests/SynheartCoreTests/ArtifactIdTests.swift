import XCTest
@testable import SynheartCore

final class ArtifactIdTests: XCTestCase {

    // MARK: - Golden vectors (must match Dart, Kotlin, and reference vectors)

    func testVector1_HSIWindow() {
        let id = computeArtifactId(
            type: "hsi_window",
            subjectId: "usr_abc123",
            sessionId: "sess_def456",
            startMs: 1709251200000,
            endMs: 1709251230000,
            schemaName: "hsi_window",
            schemaVersion: "1"
        )
        XCTAssertEqual(id, "5e9f3c5a3c3279397da3fcd9361dd87b865b84843354a97bdedf8d8925190470")
    }

    func testVector2_BaselineSnapshot_NoSession() {
        let id = computeArtifactId(
            type: "baseline_snapshot",
            subjectId: "usr_abc123",
            sessionId: nil,
            startMs: 1709164800000,
            endMs: 1709251200000,
            schemaName: "baseline_snapshot",
            schemaVersion: "1"
        )
        XCTAssertEqual(id, "3eb16bd8bfffa0314bf1c62f101ac3c1d118bdfe0080c10109db8dc2bdeeed87")
    }

    func testVector3_Tombstone() {
        let id = computeArtifactId(
            type: "tombstone",
            subjectId: "usr_abc123",
            sessionId: nil,
            startMs: 1709251230000,
            endMs: 1709251230000,
            schemaName: "tombstone",
            schemaVersion: "1"
        )
        XCTAssertEqual(id, "6cb42834a752f7cc9dd4c435a00500480754b5f271711fc34f7dc75596428807")
    }

    func testVector4_SessionSummary() {
        let id = computeArtifactId(
            type: "session_summary",
            subjectId: "usr_abc123",
            sessionId: "sess_def456",
            startMs: 1709251200000,
            endMs: 1709251260000,
            schemaName: "session_summary",
            schemaVersion: "1"
        )
        XCTAssertEqual(id, "78325014084c858ca8e38b568c68cfe011e10d5d720a0acb89fddaf1bd5d00ff")
    }

    // MARK: - Determinism

    func testSameInputProducesSameId() {
        let id1 = computeArtifactId(
            type: "hsi_window", subjectId: "usr_x", sessionId: "sess_1",
            startMs: 100, endMs: 200, schemaName: "hsi_window", schemaVersion: "1"
        )
        let id2 = computeArtifactId(
            type: "hsi_window", subjectId: "usr_x", sessionId: "sess_1",
            startMs: 100, endMs: 200, schemaName: "hsi_window", schemaVersion: "1"
        )
        XCTAssertEqual(id1, id2)
    }

    func testDifferentInputProducesDifferentId() {
        let id1 = computeArtifactId(
            type: "hsi_window", subjectId: "usr_x", sessionId: "sess_1",
            startMs: 100, endMs: 200, schemaName: "hsi_window", schemaVersion: "1"
        )
        let id2 = computeArtifactId(
            type: "hsi_window", subjectId: "usr_y", sessionId: "sess_1",
            startMs: 100, endMs: 200, schemaName: "hsi_window", schemaVersion: "1"
        )
        XCTAssertNotEqual(id1, id2)
    }

    func testNilSessionUseTilde() {
        let idWithNil = computeArtifactId(
            type: "baseline_snapshot", subjectId: "usr_x",
            sessionId: nil, startMs: 0, endMs: 1,
            schemaName: "baseline_snapshot", schemaVersion: "1"
        )
        // Manually verify the tilde is in the canonical string by checking
        // against a known different sessionId
        let idWithSession = computeArtifactId(
            type: "baseline_snapshot", subjectId: "usr_x",
            sessionId: "some_session", startMs: 0, endMs: 1,
            schemaName: "baseline_snapshot", schemaVersion: "1"
        )
        XCTAssertNotEqual(idWithNil, idWithSession)
    }
}
