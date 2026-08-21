import XCTest
@testable import SynheartCore

final class RuntimeStoragePayloadTests: XCTestCase {
    func testSessionRecordReadsCurrentRuntimeFields() throws {
        let record = try XCTUnwrap(SessionRecord(runtimeMap: [
            "session_id": "session-1",
            "subject_id": "subject-1",
            "started_at_ms": NSNumber(value: 1_000),
            "ended_at_ms": NSNumber(value: 2_000),
            "mode": "insight",
            "state": "closed",
        ]))

        XCTAssertEqual(record.startUtc, 1_000)
        XCTAssertEqual(record.endedAtUtc, 2_000)
        XCTAssertEqual(record.state, "closed")
        XCTAssertFalse(record.isActive)
    }

    func testStorageUsageReadsNativeCounters() {
        let usage = StorageUsage(runtimeMap: [
            "total_bytes": NSNumber(value: 4_096),
            "artifact_count": NSNumber(value: 12),
            "session_count": NSNumber(value: 3),
            "pending_sync": NSNumber(value: 2),
        ])

        XCTAssertEqual(usage.totalBytes, 4_096)
        XCTAssertEqual(usage.artifactCount, 12)
        XCTAssertEqual(usage.sessionCount, 3)
        XCTAssertEqual(usage.pendingSync, 2)
    }

    func testHsiWindowDecoderNormalizesObjectAndJsonStringElements() throws {
        let nested = "{\"hsi_id\":\"window-2\"}"
        let data = try JSONSerialization.data(withJSONObject: [
            ["hsi_id": "window-1"],
            nested,
        ])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        let windows = RuntimePayloadDecoder.dictionaryArray(
            json,
            acceptingJSONStringElements: true
        )

        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0]["hsi_id"] as? String, "window-1")
        XCTAssertEqual(windows[1]["hsi_id"] as? String, "window-2")
    }
}
