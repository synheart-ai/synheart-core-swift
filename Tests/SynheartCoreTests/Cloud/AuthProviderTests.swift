import XCTest
@testable import SynheartCore

/// Mock AuthProvider for testing
class MockAuthProvider: AuthProvider {
    var headers: [String: String]
    var onAuthErrorResult: Bool
    var onAuthErrorCalled = false
    var signRequestCallCount = 0

    init(
        headers: [String: String] = ["Authorization": "ECDSA test-sig-123"],
        onAuthErrorResult: Bool = false
    ) {
        self.headers = headers
        self.onAuthErrorResult = onAuthErrorResult
    }

    func signRequest(method: String, path: String, bodyBytes: Data) throws -> [String: String] {
        signRequestCallCount += 1
        return headers
    }

    func onAuthError(statusCode: Int, responseHeaders: [String: String]) -> Bool {
        onAuthErrorCalled = true
        return onAuthErrorResult
    }
}

final class AuthProviderTests: XCTestCase {

    func testCloudConfigRequiresHmacOrAuthProvider() {
        // Valid: hmacSecret only
        let config1 = CloudConfig(
            tenantId: "test",
            hmacSecret: "secret",
            subjectId: "user"
        )
        XCTAssertNotNil(config1)

        // Valid: authProvider only
        let config2 = CloudConfig(
            tenantId: "test",
            authProvider: MockAuthProvider(),
            subjectId: "user"
        )
        XCTAssertNotNil(config2)

        // Valid: both
        let config3 = CloudConfig(
            tenantId: "test",
            hmacSecret: "secret",
            authProvider: MockAuthProvider(),
            subjectId: "user"
        )
        XCTAssertNotNil(config3)
    }

    func testCloudConfigStoresAuthProvider() {
        let provider = MockAuthProvider()
        let config = CloudConfig(
            tenantId: "test",
            authProvider: provider,
            subjectId: "user"
        )
        XCTAssertNotNil(config.authProvider)
        XCTAssertNil(config.hmacSecret)
    }

    func testCloudConfigHmacSecretIsNullable() {
        let config = CloudConfig(
            tenantId: "test",
            authProvider: MockAuthProvider(),
            subjectId: "user"
        )
        XCTAssertNil(config.hmacSecret)
    }

    func testMockAuthProviderSignRequest() throws {
        let provider = MockAuthProvider(headers: [
            "Authorization": "ECDSA sig-abc",
            "X-Device-Id": "dev-123",
        ])

        let headers = try provider.signRequest(
            method: "POST",
            path: "/v1/ingest/hsi",
            bodyBytes: Data("{}".utf8)
        )

        XCTAssertEqual(headers["Authorization"], "ECDSA sig-abc")
        XCTAssertEqual(headers["X-Device-Id"], "dev-123")
        XCTAssertEqual(provider.signRequestCallCount, 1)
    }

    func testMockAuthProviderOnAuthError() {
        let provider = MockAuthProvider(onAuthErrorResult: true)

        let handled = provider.onAuthError(statusCode: 401, responseHeaders: [:])

        XCTAssertTrue(handled)
        XCTAssertTrue(provider.onAuthErrorCalled)
    }
}
