import XCTest
import CryptoKit
@testable import SynheartCore

final class ArtifactCryptoTests: XCTestCase {

    private func makeTestSMK() -> SMK {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 { bytes[i] = UInt8(i) }
        return SMK.fromBytes(Data(bytes))
    }

    func testEncryptDecryptRoundTrip() throws {
        let smk = makeTestSMK()
        let original: [String: Any] = [
            "type": "hsi_window",
            "value": 42,
            "nested": ["a": 1, "b": "hello"]
        ]

        let encrypted = try ArtifactCrypto.encrypt(smk: smk, json: original)
        XCTAssertEqual(encrypted.encAlg, "chacha20poly1305")
        XCTAssertFalse(encrypted.sha256.isEmpty)
        XCTAssertTrue(encrypted.ciphertext.count > 0)

        let decrypted = try ArtifactCrypto.decrypt(smk: smk, combined: encrypted.ciphertext)
        XCTAssertEqual(decrypted["type"] as? String, "hsi_window")
        XCTAssertEqual(decrypted["value"] as? Int, 42)

        let nested = decrypted["nested"] as? [String: Any]
        XCTAssertEqual(nested?["a"] as? Int, 1)
        XCTAssertEqual(nested?["b"] as? String, "hello")
    }

    func testWrongKeyFailsDecryption() throws {
        let smk1 = makeTestSMK()
        var otherBytes = [UInt8](repeating: 0xFF, count: 32)
        otherBytes[0] = 0xAA
        let smk2 = SMK.fromBytes(Data(otherBytes))

        let encrypted = try ArtifactCrypto.encrypt(smk: smk1, json: ["key": "value"])
        XCTAssertThrowsError(try ArtifactCrypto.decrypt(smk: smk2, combined: encrypted.ciphertext))
    }

    func testSHA256ConsistentForSameInput() throws {
        let smk = makeTestSMK()
        let json: [String: Any] = ["stable": true]

        let enc1 = try ArtifactCrypto.encrypt(smk: smk, json: json)
        let enc2 = try ArtifactCrypto.encrypt(smk: smk, json: json)

        // SHA-256 is of plaintext, so same input → same hash
        XCTAssertEqual(enc1.sha256, enc2.sha256)

        // Ciphertext differs due to random nonce
        XCTAssertNotEqual(enc1.ciphertext, enc2.ciphertext)
    }

    func testTruncatedCiphertextFails() {
        let smk = makeTestSMK()
        let tooShort = Data([0x00, 0x01, 0x02])
        XCTAssertThrowsError(try ArtifactCrypto.decrypt(smk: smk, combined: tooShort))
    }
}
