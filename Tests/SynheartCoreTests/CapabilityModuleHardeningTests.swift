import XCTest
@testable import SynheartCore

final class CapabilityModuleHardeningTests: XCTestCase {
    private final class Verifier: CapabilityTokenVerifying {
        var shouldAccept = true
        private(set) var calls = 0

        func loadCapabilityToken(tokenJson: String, secret: String) -> Bool {
            calls += 1
            return shouldAccept
        }
    }

    private func token(
        issuedAt: Date = Date().addingTimeInterval(-60),
        expiresAt: Date = Date().addingTimeInterval(3_600)
    ) -> CapabilityToken {
        CapabilityToken(
            orgId: "org",
            projectId: "project",
            environment: "test",
            capabilities: ["wear": "core"],
            signature: "signature",
            expiresAt: expiresAt,
            issuedAt: issuedAt
        )
    }

    func testExpiredTokenIsRejectedBeforeSignatureVerification() {
        let verifier = Verifier()
        let module = CapabilityModule(tokenVerifier: verifier)

        XCTAssertThrowsError(try module.loadVerifiedToken(
            token(expiresAt: Date().addingTimeInterval(-1)),
            secret: "secret"
        ))
        XCTAssertEqual(verifier.calls, 0)
        XCTAssertEqual(module.capability(.wear), .none)
    }

    func testTokenIsRejectedWhenSignatureVerifierIsUnavailable() {
        let module = CapabilityModule()

        XCTAssertThrowsError(try module.loadVerifiedToken(token(), secret: "secret"))
        XCTAssertEqual(module.capability(.wear), .none)
    }

    func testForgedTokenIsRejected() {
        let verifier = Verifier()
        verifier.shouldAccept = false
        let module = CapabilityModule(tokenVerifier: verifier)

        XCTAssertThrowsError(try module.loadVerifiedToken(token(), secret: "secret"))
        XCTAssertEqual(verifier.calls, 1)
        XCTAssertEqual(module.capability(.wear), .none)
    }

    func testVerifiedTokenLoadsCapabilities() throws {
        let verifier = Verifier()
        let module = CapabilityModule(tokenVerifier: verifier)

        try module.loadVerifiedToken(token(), secret: "secret")

        XCTAssertEqual(verifier.calls, 1)
        XCTAssertEqual(module.capability(.wear), .core)
    }
}
