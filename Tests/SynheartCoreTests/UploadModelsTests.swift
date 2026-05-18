// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import SynheartCore

final class UploadModelsTests: XCTestCase {

    func testUploadMetadataOmitsOrgIdWhenNil() {
        let m = UploadMetadata(sdkVersion: "1.0", platform: "ios", capabilityLevel: "free")
        let json = m.toJson()
        XCTAssertNil(json["org_id"])
        XCTAssertEqual(json["sdk_version"] as? String, "1.0")
    }

    func testUploadMetadataRoundTripPreservesOrgId() {
        let orig = UploadMetadata(sdkVersion: "1.0", platform: "ios",
                                  capabilityLevel: "pro", orgId: "org_123")
        let rt = UploadMetadata.fromJson(orig.toJson())
        XCTAssertEqual(orig, rt)
    }

    func testUploadRequestPreservesNestedSnapshotStructure() {
        let req = UploadRequest(
            userId: "usr_x",
            metadata: UploadMetadata(sdkVersion: "1.0", platform: "ios", capabilityLevel: "free"),
            snapshots: [
                ["artifact_id": "abc", "nested": ["k": 1]],
                ["artifact_id": "def"],
            ]
        )
        let rt = UploadRequest.fromJson(req.toJson())
        XCTAssertEqual(rt.userId, "usr_x")
        XCTAssertEqual(rt.snapshots.count, 2)
        XCTAssertEqual(rt.snapshots[0]["artifact_id"] as? String, "abc")
        let nested = rt.snapshots[0]["nested"] as? [String: Any]
        XCTAssertEqual(nested?["k"] as? Int, 1)
    }

    func testUploadResponseOmitsAllNilFields() {
        let r = UploadResponse(batchId: "b1")
        let json = r.toJson()
        XCTAssertEqual(Set(json.keys), ["batch_id"])
    }

    func testUploadResponseFromJsonParsesArrays() throws {
        let s = #"{"success": true, "batch_id": "b1", "snapshot_ids": ["s1","s2"], "s3_keys": ["k1","k2"]}"#
        let data = s.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let r = UploadResponse.fromJson(json)
        XCTAssertEqual(r.success, true)
        XCTAssertEqual(r.batchId, "b1")
        XCTAssertEqual(r.snapshotIds, ["s1", "s2"])
        XCTAssertEqual(r.s3Keys, ["k1", "k2"])
        XCTAssertNil(r.message)
    }

    func testUploadErrorResponseDerivesDefaultCodeAndMessage() {
        let r = UploadErrorResponse.fromJson([:])
        XCTAssertEqual(r.errorCode, "unknown")
        XCTAssertEqual(r.errorMessage, "Unknown error")
        XCTAssertNil(r.retryAfter)
    }

    func testUploadErrorResponseRoundTripPreservesRetryAfterAndDetails() {
        let orig = UploadErrorResponse(
            error: UploadErrorDetail(code: "RATE_LIMITED", message: "Too many requests", details: "10 / second"),
            retryAfter: 30
        )
        let rt = UploadErrorResponse.fromJson(orig.toJson())
        XCTAssertEqual(rt.errorCode, "RATE_LIMITED")
        XCTAssertEqual(rt.errorMessage, "Too many requests")
        XCTAssertEqual(rt.error?.details, "10 / second")
        XCTAssertEqual(rt.retryAfter, 30)
    }

    func testUploadErrorDetailOmitsDetailsWhenNil() {
        let d = UploadErrorDetail(code: "X", message: "y")
        let json = d.toJson()
        XCTAssertNil(json["details"])
    }
}
