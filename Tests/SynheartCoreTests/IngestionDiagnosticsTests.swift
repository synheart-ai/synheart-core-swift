import XCTest
@testable import SynheartCore

final class IngestionDiagnosticsTests: XCTestCase {
    func testFlushResultParsesCountsAndBatch() {
        let result = UploadFlushResult(runtimeMap: [
            "uploaded": 3,
            "failed": 1,
            "requeued": 1,
            "batch_id": "batch_1",
        ])

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.uploaded, 3)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.requeued, 1)
        XCTAssertEqual(result.batchId, "batch_1")
    }

    func testNativeFailureParsesActionableEnvelope() {
        let result = UploadFlushResult(runtimeMap: [
            "error": [
                "reason": "timeout",
                "message": "Attestation timed out",
                "retry_after_ms": 15_000,
                "detail": ["stage": "verdict"],
            ],
        ])

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.failure?.reason, .timeout)
        XCTAssertEqual(result.failure?.retryAfterMs, 15_000)
        XCTAssertTrue(result.failure?.retryable == true)
        XCTAssertEqual(result.failure?.detail, #"{"stage":"verdict"}"#)
    }

    func testDeviceAuthStatusKeepsAttestationClaimSeparate() {
        let status = DeviceAuthStatus(runtimeMap: [
            "status": "registered",
            "device_id": "dev_1",
            "attestation": "unattested",
        ])

        XCTAssertTrue(status.isRegistered)
        XCTAssertEqual(status.deviceId, "dev_1")
        XCTAssertEqual(status.attestation, "unattested")
    }
}
