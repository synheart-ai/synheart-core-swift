import XCTest
@testable import SynheartCore

final class AuthModuleTests: XCTestCase {

    func testStartsUnauthenticated() {
        let auth = AuthModule(appId: "test_app")
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.subjectId)
        XCTAssertFalse(auth.status.syncReady)
    }

    func testAnonymousAuthGeneratesSubjectId() throws {
        let auth = AuthModule(appId: "test_app")
        let result = try auth.authenticateAnonymous()

        XCTAssertTrue(result.subjectId.hasPrefix("anon_"))
        XCTAssertNil(result.accessToken)
        XCTAssertFalse(result.syncReady)
        XCTAssertEqual(auth.status.provider, "anonymous")
        XCTAssertFalse(auth.status.authenticated)
        XCTAssertNotNil(auth.subjectId)
    }

    func testLogoutClearsState() throws {
        let auth = AuthModule(appId: "test_app")
        _ = try auth.authenticateAnonymous()
        XCTAssertNotNil(auth.subjectId)

        auth.logout()
        XCTAssertNil(auth.subjectId)
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(auth.accessToken)
    }

    func testMarkSyncReadyUpdatesStatus() throws {
        let auth = AuthModule(appId: "test_app")
        _ = try auth.authenticateAnonymous()
        XCTAssertFalse(auth.status.syncReady)

        auth.markSyncReady()
        XCTAssertTrue(auth.status.syncReady)
    }

    func testAuthStatusUnauthenticatedDefaults() {
        let status = AuthStatus.unauthenticated
        XCTAssertFalse(status.authenticated)
        XCTAssertNil(status.subjectId)
        XCTAssertNil(status.provider)
        XCTAssertFalse(status.syncReady)
    }
}
