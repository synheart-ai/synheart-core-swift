import XCTest
@testable import SynheartCore

/// Pure unit tests for ``CloudConsentLogic`` — the cloud-consent decision
/// logic. No native runtime or device required; runs under `swift test`.
final class CloudConsentLogicTests: XCTestCase {

    // MARK: - isTokenSubjectStale

    func testSameSubjectIsNotStale() {
        XCTAssertFalse(CloudConsentLogic.isTokenSubjectStale(tokenUserId: "sub_a", currentSubject: "sub_a"))
    }

    func testDifferentSubjectIsStale() {
        // The account-re-key case: token minted for sub_a, runtime now on sub_b.
        XCTAssertTrue(CloudConsentLogic.isTokenSubjectStale(tokenUserId: "sub_a", currentSubject: "sub_b"))
    }

    func testUnknownCurrentSubjectIsNeverStale() {
        XCTAssertFalse(CloudConsentLogic.isTokenSubjectStale(tokenUserId: "sub_a", currentSubject: nil))
        XCTAssertFalse(CloudConsentLogic.isTokenSubjectStale(tokenUserId: "sub_a", currentSubject: ""))
        XCTAssertFalse(CloudConsentLogic.isTokenSubjectStale(tokenUserId: "sub_a", currentSubject: "   "))
    }

    func testTokenWithoutSubjectIsNeverStale() {
        XCTAssertFalse(CloudConsentLogic.isTokenSubjectStale(tokenUserId: nil, currentSubject: "sub_a"))
        XCTAssertFalse(CloudConsentLogic.isTokenSubjectStale(tokenUserId: "", currentSubject: "sub_a"))
    }

    func testSubjectsAreComparedTrimmed() {
        XCTAssertFalse(CloudConsentLogic.isTokenSubjectStale(tokenUserId: " sub_a ", currentSubject: "sub_a"))
    }

    // MARK: - isReadyWithoutReissue

    func testGrantedFreshMatchingSubjectIsReady() {
        XCTAssertTrue(CloudConsentLogic.isReadyWithoutReissue(status: "granted", needsRefresh: false, subjectStale: false))
    }

    func testGrantedButStaleSubjectIsNotReady() {
        XCTAssertFalse(CloudConsentLogic.isReadyWithoutReissue(status: "granted", needsRefresh: false, subjectStale: true))
    }

    func testGrantedButNeedsRefreshIsNotReady() {
        XCTAssertFalse(CloudConsentLogic.isReadyWithoutReissue(status: "GRANTED", needsRefresh: true, subjectStale: false))
    }

    func testPendingIsNotReady() {
        XCTAssertFalse(CloudConsentLogic.isReadyWithoutReissue(status: "pending", needsRefresh: false, subjectStale: false))
        XCTAssertFalse(CloudConsentLogic.isReadyWithoutReissue(status: nil, needsRefresh: false, subjectStale: false))
    }

    // MARK: - submitIssuedToken

    func testSubmitIssuedOnlyWhenSyncedAndTokenPresent() {
        XCTAssertTrue(CloudConsentLogic.submitIssuedToken(synced: true, hasToken: true))
        XCTAssertFalse(CloudConsentLogic.submitIssuedToken(synced: true, hasToken: false))
        XCTAssertFalse(CloudConsentLogic.submitIssuedToken(synced: false, hasToken: true))
        XCTAssertFalse(CloudConsentLogic.submitIssuedToken(synced: false, hasToken: false))
    }
}
