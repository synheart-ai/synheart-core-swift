import XCTest
@testable import SynheartCore

final class ConsentModelsTests: XCTestCase {
    func testConsentFormParsesRuntimeShapeAndEmitsCanonicalKeys() throws {
        let json = """
        {
          "profile_id":"offline-default",
          "biosignals":true,
          "phone_context":false,
          "behavior":true,
          "consent_tier":"cloud",
          "allow_cloud":true,
          "allow_research":false,
          "allow_vendor_sync":true,
          "syni":true
        }
        """
        let form = try JSONDecoder().decode(ConsentForm.self, from: Data(json.utf8))

        XCTAssertEqual(form.profileId, "offline-default")
        XCTAssertTrue(form.biosignals)
        XCTAssertFalse(form.phoneContext)
        XCTAssertTrue(form.behavior)
        XCTAssertEqual(form.consentTier, .cloud)
        XCTAssertTrue(form.allowCloud)
        XCTAssertTrue(form.allowVendorSync)
        XCTAssertTrue(form.syni)

        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(form)) as! [String: Any]
        XCTAssertEqual(Set(encoded.keys), [
            "profile_id", "biosignals", "phone_context", "behavior",
            "consent_tier", "allow_cloud", "allow_research",
            "allow_vendor_sync", "syni",
        ])
    }

    func testConsentFormMissingFieldsFailClosedAndCopyWithPreservesValues() throws {
        let form = try JSONDecoder().decode(
            ConsentForm.self,
            from: Data(#"{"profile_id":"offline-default"}"#.utf8)
        )
        XCTAssertFalse(form.biosignals)
        XCTAssertFalse(form.allowCloud)
        XCTAssertEqual(form.consentTier, .local)

        let edited = form.copyWith(behavior: true)
        XCTAssertTrue(edited.behavior)
        XCTAssertEqual(edited.profileId, form.profileId)
        XCTAssertFalse(edited.biosignals)
    }

    func testEffectiveStateParsesRuntimeShapeAndBuildsSnapshot() throws {
        let json = """
        {
          "biosignals":true,
          "phone_context":false,
          "behavior":true,
          "cloud_upload":true,
          "syni":false,
          "vendor_sync":true,
          "research":false,
          "timestamp_ms":1776000000000,
          "version":"1.0.0"
        }
        """
        let state = try JSONDecoder().decode(ConsentEffectiveState.self, from: Data(json.utf8))

        XCTAssertTrue(state.hasAnyGrant)
        XCTAssertTrue(state.allows(.biosignals))
        XCTAssertFalse(state.allows(.phoneContext))
        XCTAssertTrue(state.snapshot.cloudUpload)
        XCTAssertEqual(state.snapshot.tier, .cloud)
        XCTAssertEqual(state.snapshot.vendorSync, true)
    }

    func testEffectiveStateMissingFieldsFailsClosed() throws {
        let state = try JSONDecoder().decode(ConsentEffectiveState.self, from: Data("{}".utf8))
        XCTAssertFalse(state.hasAnyGrant)
        XCTAssertEqual(state.timestampMs, 0)
        XCTAssertEqual(state.version, "")
    }

    func testSubmissionResultDistinguishesLocalSaveFromIssuedToken() throws {
        let local = try ConsentSubmissionResult(json: #"{"synced":false,"token":null}"#)
        XCTAssertTrue(local.succeeded)
        XCTAssertFalse(local.synced)
        XCTAssertFalse(local.tokenIssued)

        let cloud = try ConsentSubmissionResult(json: #"{"synced":true,"token":{"jwt":"redacted"}}"#)
        XCTAssertTrue(cloud.synced)
        XCTAssertTrue(cloud.tokenIssued)
    }
}
