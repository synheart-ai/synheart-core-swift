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
            "pending_count": NSNumber(value: 3),
            "last_success_ms": NSNumber(value: Int64(1_793_000_000_000)),
            "srk_ready": true,
            "account_owned": false,
        ])

        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.syncSpaceId, "space-1")
        XCTAssertTrue(status.hasActiveSpace)
        XCTAssertEqual(status.pendingCount, 3)
        XCTAssertEqual(status.lastSuccessMs, 1_793_000_000_000)
        XCTAssertEqual(status.srkReady, true)
        XCTAssertEqual(status.accountOwned, false)
    }

    func testSyncStatusFromAnOlderRuntimeLeavesNewFieldsAbsent() {
        // An older runtime sent `device_count` (always 0) and none of the new
        // fields: they stay nil, never zero.
        let status = SyncStatus(runtimeMap: [
            "enabled": true,
            "sync_space_id": "",
            "device_count": NSNumber(value: 0),
        ])

        XCTAssertTrue(status.enabled)
        XCTAssertNil(status.syncSpaceId)
        XCTAssertFalse(status.hasActiveSpace)
        XCTAssertNil(status.pendingCount)
        XCTAssertNil(status.lastSuccessMs)
        XCTAssertNil(status.srkReady)
        XCTAssertNil(status.accountOwned)
        XCTAssertFalse(SyncStatus(runtimeMap: [:]).enabled)
    }

    func testSyncPairingStateParsesUnknownValuesAsUnknown() {
        XCTAssertEqual(SyncPairingState.parse("waiting"), .waiting)
        XCTAssertEqual(SyncPairingState.parse("joined"), .joined)
        XCTAssertEqual(SyncPairingState.parse("expired"), .expired)
        XCTAssertEqual(SyncPairingState.parse("cancelled"), .unknown)
        XCTAssertEqual(SyncPairingState.parse(nil), .unknown)
        XCTAssertEqual(SyncPairingState.parse(NSNumber(value: 1)), .unknown)
        XCTAssertTrue(SyncPairingState.joined.isTerminal)
        XCTAssertTrue(SyncPairingState.expired.isTerminal)
        XCTAssertFalse(SyncPairingState.waiting.isTerminal)
        XCTAssertFalse(SyncPairingState.unknown.isTerminal)
    }

    func testSyncPairingStatusReadsAJoinedDevice() {
        let status = SyncPairingStatus(runtimeMap: [
            "status": "joined",
            "sync_space_id": "space-1",
            "joined_device": ["device_id": "dev-2", "device_name": "iPad"],
            "joined_at": "2026-10-30T12:00:05.123Z",
            "expires_at": "2026-10-30T12:10:00Z",
        ])

        XCTAssertEqual(status.state, .joined)
        XCTAssertEqual(status.syncSpaceId, "space-1")
        XCTAssertEqual(status.joinedDevice, SyncPairedDevice(deviceId: "dev-2", deviceName: "iPad"))
        XCTAssertEqual(status.joinedAt?.timeIntervalSince1970 ?? 0, 1_793_361_605.123, accuracy: 0.001)
        XCTAssertEqual(status.expiresAt?.timeIntervalSince1970, 1_793_362_200)
    }

    func testSyncPairingStatusWhileWaiting() {
        let status = SyncPairingStatus(runtimeMap: [
            "status": "waiting",
            "sync_space_id": "space-1",
            "joined_device": NSNull(),
            "joined_at": NSNull(),
            "expires_at": "2026-10-30T12:10:00+03:00",
        ])

        XCTAssertEqual(status.state, .waiting)
        XCTAssertNil(status.joinedDevice)
        XCTAssertNil(status.joinedAt)
        XCTAssertEqual(status.expiresAt?.timeIntervalSince1970, 1_793_351_400)
    }

    func testSyncPairingStatusExpiry() {
        let expiresAt = Date(timeIntervalSince1970: 1_000)
        let waiting = SyncPairingStatus(state: .waiting, expiresAt: expiresAt)
        XCTAssertFalse(waiting.isExpired(at: Date(timeIntervalSince1970: 999)))
        XCTAssertTrue(waiting.isExpired(at: expiresAt))
        XCTAssertTrue(SyncPairingStatus(state: .expired).isExpired(at: .distantPast))
        XCTAssertFalse(SyncPairingStatus(state: .unknown).isExpired(at: .distantFuture))
    }
}
