import XCTest
@testable import SynheartCore

final class HMACSignerTests: XCTestCase {

    var signer: HMACSigner!

    override func setUp() {
        super.setUp()
        signer = HMACSigner(hmacSecret: "test_secret")
    }

    func testGenerateNonceFormat() {
        let nonce = signer.generateNonce()

        // Nonce format: <unix_timestamp>_<random_hex>
        let regex = try! NSRegularExpression(pattern: "^\\d+_[a-f0-9]{24}$")
        let range = NSRange(nonce.startIndex..., in: nonce)
        let match = regex.firstMatch(in: nonce, range: range)

        XCTAssertNotNil(match, "Nonce should match format: timestamp_randomhex")

        // Verify timestamp is reasonable (within last minute)
        let parts = nonce.split(separator: "_")
        let timestamp = Int(parts[0])!
        let now = Int(Date().timeIntervalSince1970)
        XCTAssertTrue(abs(now - timestamp) < 60, "Timestamp should be recent")
    }

    func testGenerateNonceUniqueness() {
        let nonce1 = signer.generateNonce()
        let nonce2 = signer.generateNonce()

        XCTAssertNotEqual(nonce1, nonce2, "Nonces should be unique")
    }

    func testComputeSignatureReturnsValidHex() {
        let signature = signer.computeSignature(
            method: "POST",
            path: "/v1/ingest/hsi",
            tenantId: "test_tenant",
            timestamp: 1704067200,
            nonce: "1704067200_abc123",
            bodyJson: "{\"test\":\"data\"}"
        )

        // SHA256 hex should be 64 characters
        XCTAssertEqual(signature.count, 64, "Signature should be 64 chars (SHA256 hex)")

        // Should be valid hex
        let hexRegex = try! NSRegularExpression(pattern: "^[a-f0-9]{64}$")
        let range = NSRange(signature.startIndex..., in: signature)
        let match = hexRegex.firstMatch(in: signature, range: range)
        XCTAssertNotNil(match, "Signature should be valid hex")
    }

    func testComputeSignatureDeterministic() {
        let signature1 = signer.computeSignature(
            method: "POST",
            path: "/v1/ingest/hsi",
            tenantId: "test_tenant",
            timestamp: 1704067200,
            nonce: "1704067200_abc123",
            bodyJson: "{\"test\":\"data\"}"
        )

        let signature2 = signer.computeSignature(
            method: "POST",
            path: "/v1/ingest/hsi",
            tenantId: "test_tenant",
            timestamp: 1704067200,
            nonce: "1704067200_abc123",
            bodyJson: "{\"test\":\"data\"}"
        )

        XCTAssertEqual(signature1, signature2, "Same inputs should produce same signature")
    }

    func testComputeSignatureChangesWithDifferentInputs() {
        let baseSignature = signer.computeSignature(
            method: "POST",
            path: "/v1/ingest/hsi",
            tenantId: "test_tenant",
            timestamp: 1704067200,
            nonce: "1704067200_abc123",
            bodyJson: "{\"test\":\"data\"}"
        )

        // Different tenant
        let diffTenantSig = signer.computeSignature(
            method: "POST",
            path: "/v1/ingest/hsi",
            tenantId: "different_tenant",
            timestamp: 1704067200,
            nonce: "1704067200_abc123",
            bodyJson: "{\"test\":\"data\"}"
        )

        // Different body
        let diffBodySig = signer.computeSignature(
            method: "POST",
            path: "/v1/ingest/hsi",
            tenantId: "test_tenant",
            timestamp: 1704067200,
            nonce: "1704067200_abc123",
            bodyJson: "{\"test\":\"different\"}"
        )

        XCTAssertNotEqual(baseSignature, diffTenantSig, "Different tenant should change signature")
        XCTAssertNotEqual(baseSignature, diffBodySig, "Different body should change signature")
    }
}
