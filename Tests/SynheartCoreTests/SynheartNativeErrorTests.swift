import XCTest
@testable import SynheartCore

final class SynheartNativeErrorTests: XCTestCase {

    func testParsesEveryFieldOfAStructuredRuntimeError() {
        let e = SynheartNativeError(json: """
        {"code":"CONSENT_REQUIRED","message":"Consent needed.","retryable":false,
         "reason":"biosignals","owner":"user","recovery":"grant_consent",
         "recovery_call":"synheart_core_grant_consent","hint":"grant it first",
         "op":"synheart_core_start_session","error_id":"0a1b2c3d",
         "detail":{"argument":"type_name"},
         "report":{"runtime_version":"0.38.0","abi":"2.0"}}
        """)
        XCTAssertEqual(e.code, "CONSENT_REQUIRED")
        XCTAssertEqual(e.ownerKind, .user)
        XCTAssertEqual(e.recoveryKind, .grantConsent)
        XCTAssertEqual(e.recoveryCall, "synheart_core_grant_consent")
        XCTAssertEqual(e.op, "synheart_core_start_session")
        XCTAssertEqual(e.errorId, "0a1b2c3d")
        XCTAssertEqual(e.argument, "type_name")
        XCTAssertEqual(e.report?["abi"] as? String, "2.0")
        XCTAssertFalse(e.isRuntimeBug)
    }

    func testAnOlderRuntimesMinimalErrorParsesWithUnknownOwnerAndRecovery() {
        let e = SynheartNativeError(json: #"{"code":"NETWORK","message":"Offline.","retryable":true}"#)
        XCTAssertTrue(e.retryable)
        XCTAssertEqual(e.ownerKind, .unknown)
        XCTAssertEqual(e.recoveryKind, .unknown)
        XCTAssertNil(e.argument)
    }

    func testAMalformedPayloadFallsBackToASafeShape() {
        let e = SynheartNativeError(json: #"{"code":7,"retry_after_ms":1500.0}"#)
        XCTAssertEqual(e.code, "UNKNOWN")
        XCTAssertEqual(e.message, "An unexpected error occurred.")
        XCTAssertEqual(e.retryAfterMs, 1500)
        XCTAssertEqual(SynheartNativeError(json: "not json").code, "UNKNOWN")
    }

    func testEveryRecoveryTokenParses() {
        let tokens = [
            "retry", "wait_for_device_unlock", "fix_call", "fix_configuration", "reenter_input",
            "sign_in", "register_device", "reattest_device", "sign_out_then_register",
            "grant_consent", "generate_new_pairing_code", "rejoin_space", "start_session_first",
            "end_session_first", "use_supported_build", "report_bug", "none",
        ]
        for t in tokens {
            XCTAssertNotEqual(NativeErrorRecovery.parse(t), .unknown, t)
        }
        XCTAssertEqual(NativeErrorRecovery.parse("something_new"), .unknown)
    }
}
