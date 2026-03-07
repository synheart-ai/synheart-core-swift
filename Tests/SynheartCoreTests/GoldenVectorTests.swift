import XCTest
import CryptoKit
@testable import SynheartCore

/// Golden vector tests for cross-platform key derivation consistency.
///
/// These expected hex values were computed from the Kotlin HKDF implementation
/// and are shared across Kotlin, Dart, and Swift test suites via
/// encryption_vectors.json in synheart-core/test/vectors/.
final class GoldenVectorTests: XCTestCase {

    // -- Inline vectors (mirrors encryption_vectors.json) --------------------

    private let artifactUrkHex =
        "0101010101010101010101010101010101010101010101010101010101010101"
    private let artifactId = "test_artifact_001"
    private let expectedArtifactKeyHex =
        "38f4cae76ca1a4a75f8300552747adf23a4043685ff3548e98bd523897f062f4"

    private let bekSessionSecret = "test_session_secret"
    private let bekSubjectId = "usr_test123"
    private let expectedBekHex =
        "02ab906478234d2d1db18ab9fefd1d2f9c3a2548700b3c0853c685f8cba20e9b"

    // -- Helpers -------------------------------------------------------------

    private func hexToBytes(_ hex: String) -> Data {
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = hex[index..<nextIndex]
            data.append(UInt8(byteString, radix: 16)!)
            index = nextIndex
        }
        return data
    }

    private func toHex(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    // -- Tests ---------------------------------------------------------------

    func testArtifactKeyDerivationMatchesGoldenVector() {
        let urk = hexToBytes(artifactUrkHex)
        let derived = URK.deriveArtifactKey(urk: urk, artifactId: artifactId)
        XCTAssertEqual(
            toHex(derived),
            expectedArtifactKeyHex,
            "Artifact key derivation mismatch — cross-platform HKDF inconsistency"
        )
    }

    func testBEKDerivationMatchesGoldenVector() {
        let derived = URK.deriveBEK(sessionSecret: bekSessionSecret, subjectId: bekSubjectId)
        XCTAssertEqual(
            toHex(derived),
            expectedBekHex,
            "BEK derivation mismatch — cross-platform HKDF inconsistency"
        )
    }
}
