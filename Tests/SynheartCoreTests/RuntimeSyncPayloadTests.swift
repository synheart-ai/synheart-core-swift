import XCTest
@testable import SynheartCore

final class RuntimeSyncPayloadTests: XCTestCase {
    func testSyncResultReadsAllNativeCounters() {
        let result = SyncResult(runtimeMap: [
            "pushed": NSNumber(value: 4),
            "pulled": NSNumber(value: 3),
            "conflicts_resolved": NSNumber(value: 2),
            "errors": ["one warning"],
        ])

        XCTAssertEqual(result.pushed, 4)
        XCTAssertEqual(result.pulled, 3)
        XCTAssertEqual(result.conflictsResolved, 2)
        XCTAssertEqual(result.errors, ["one warning"])
    }

    func testSyncStatusReadsRuntimeSnapshot() {
        let status = SyncStatus(runtimeMap: [
            "enabled": true,
            "sync_space_id": "space-1",
            "device_count": NSNumber(value: 2),
        ])

        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.syncSpaceId, "space-1")
        XCTAssertEqual(status.deviceCount, 2)
    }
}
