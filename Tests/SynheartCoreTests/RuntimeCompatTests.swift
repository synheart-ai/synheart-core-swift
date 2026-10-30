import XCTest
@testable import SynheartCore

final class RuntimeCompatTests: XCTestCase {

    func testCompareOrdersDottedNumericVersions() {
        XCTAssertGreaterThan(RuntimeCompat.compare("0.31.1", "0.31.0"), 0)
        XCTAssertLessThan(RuntimeCompat.compare("0.30.1", "0.31.0"), 0)
        XCTAssertEqual(RuntimeCompat.compare("0.31.1", "0.31.1"), 0)
        XCTAssertGreaterThan(RuntimeCompat.compare("1.0.0", "0.99.99"), 0)
    }

    func testCompareTreatsMissingComponentAsZeroAndIgnoresSuffixes() {
        XCTAssertEqual(RuntimeCompat.compare("0.31", "0.31.0"), 0)
        XCTAssertEqual(RuntimeCompat.compare("0.31.1-rc1", "0.31.1"), 0)
        XCTAssertGreaterThan(RuntimeCompat.compare("0.31.10", "0.31.9"), 0)
    }

    func testCheckIsOkAtOrAboveWrittenAgainst() {
        let r = RuntimeCompat.check(buildInfo: ["core_runtime": RuntimeCompat.writtenAgainst])
        XCTAssertEqual(r.status, .ok)
        XCTAssertTrue(r.isAcceptable)
    }

    func testCheckRefusesTooOldBelowMinimum() {
        // 0.44.0 is the last ABI 4.1 release.
        for v in ["0.42.1", "0.43.0", "0.44.0"] {
            let r = RuntimeCompat.check(buildInfo: ["core_runtime": v])
            XCTAssertEqual(r.status, .tooOld, v)
            XCTAssertFalse(r.isAcceptable, v)
        }
    }

    func testCheckIsUnknownWithoutVersionStillAcceptable() {
        XCTAssertEqual(RuntimeCompat.check(buildInfo: nil).status, .unknown)
        XCTAssertTrue(RuntimeCompat.check(buildInfo: [:]).isAcceptable)
        XCTAssertEqual(RuntimeCompat.check(buildInfo: ["core_runtime": "  "]).status, .unknown)
    }

    func testCheckRefusesAnAbiOutsideTheAcceptedRange() {
        // 1.x–3.x take the old push and daily-call signatures: refused, since
        // calling them with ABI 4 arguments would crash rather than fail.
        for abi in ["0.9", "1.0", "2.1", "3.5", "5.0"] {
            let r = RuntimeCompat.check(buildInfo: ["core_runtime": "0.45.0", "abi": abi])
            XCTAssertEqual(r.status, .incompatibleAbi, abi)
            XCTAssertFalse(r.isAcceptable)
            XCTAssertTrue(r.message.contains(RuntimeCompat.installCommand))
        }
    }

    func testCheckAcceptsAbiFourTwoAndNewerMinors() {
        for abi in ["4.2", "4.3"] {
            let r = RuntimeCompat.check(buildInfo: ["core_runtime": "0.45.0", "abi": abi])
            XCTAssertTrue(r.isAcceptable, abi)
            XCTAssertEqual(r.abi, abi)
        }
    }

    func testCheckRefusesAbiFourZeroAndFourOne() {
        // The daily score inputs changed shape in 4.2; neither parses on the other.
        for abi in ["4.0", "4.1"] {
            let r = RuntimeCompat.check(buildInfo: ["core_runtime": "0.43.0", "abi": abi])
            XCTAssertEqual(r.status, .incompatibleAbi, abi)
            XCTAssertFalse(r.isAcceptable, abi)
        }
    }

    func testMalformedAbiFallsBackToVersionChecks() {
        let r = RuntimeCompat.check(buildInfo: ["core_runtime": "0.45.0", "abi": "two"])
        XCTAssertEqual(r.status, .ok)
        XCTAssertNil(r.abi)
    }

    func testInstallCommandPinsWrittenAgainst() {
        XCTAssertEqual(
            RuntimeCompat.installCommand,
            "synheart install runtime --version \(RuntimeCompat.writtenAgainst)"
        )
    }

    func testIncompatibleErrorCarriesVersionsAndFix() {
        let compat = RuntimeCompat.check(buildInfo: ["core_runtime": "0.41.0", "abi": "3.5"])
        let e = SynheartRuntimeError.incompatible(compat)
        XCTAssertEqual(e.kind, .incompatible)
        XCTAssertEqual(e.runtimeVersion, "0.41.0")
        XCTAssertEqual(e.runtimeAbi, "3.5")
        XCTAssertEqual(e.installCommand, RuntimeCompat.installCommand)
        XCTAssertEqual(e.recommendedVersion, RuntimeCompat.writtenAgainst)
    }
}
