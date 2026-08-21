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
                "code": "ATTESTATION_TIMEOUT",
                "reason": "timeout",
                "message": "Attestation timed out",
                "retryable": true,
                "retry_after_ms": 15_000,
                "detail": ["stage": "verdict"],
            ],
        ])

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.failure?.code, "ATTESTATION_TIMEOUT")
        XCTAssertEqual(result.failure?.reason, .timeout)
        XCTAssertEqual(result.failure?.retryAfterMs, 15_000)
        XCTAssertTrue(result.failure?.retryable == true)
        XCTAssertEqual(result.failure?.detail, #"{"stage":"verdict"}"#)
    }

    func testNativeRetryableFlagOverridesReasonFallback() {
        let permanent = UploadFlushResult(runtimeMap: [
            "ok": false,
            "error": [
                "code": "POLICY_LOCKED",
                "reason": "transient",
                "message": "Server marked this request permanent",
                "retryable": false,
            ],
        ])
        let forwardCompatible = UploadFlushResult(runtimeMap: [
            "ok": false,
            "error": [
                "code": "NEW_RECOVERABLE_FAILURE",
                "message": "A newer runtime says this can be retried",
                "retryable": true,
            ],
        ])

        XCTAssertFalse(permanent.failure?.retryable ?? true)
        XCTAssertTrue(forwardCompatible.failure?.retryable == true)
        XCTAssertEqual(forwardCompatible.failure?.reason, .unknown)
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
