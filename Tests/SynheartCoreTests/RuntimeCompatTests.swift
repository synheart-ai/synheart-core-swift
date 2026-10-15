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

    func testCheckIsOlderBetweenMinimumAndWrittenAgainstStillAcceptable() {
        let r = RuntimeCompat.check(buildInfo: ["core_runtime": "0.30.0"])
        XCTAssertEqual(r.status, .older)
        XCTAssertTrue(r.isAcceptable)
        XCTAssertTrue(r.message.contains("0.30.0"))
    }

    func testCheckRefusesTooOldBelowMinimum() {
        let r = RuntimeCompat.check(buildInfo: ["core_runtime": "0.19.2"])
        XCTAssertEqual(r.status, .tooOld)
        XCTAssertFalse(r.isAcceptable)
    }

    func testCheckIsUnknownWithoutVersionStillAcceptable() {
        XCTAssertEqual(RuntimeCompat.check(buildInfo: nil).status, .unknown)
        XCTAssertTrue(RuntimeCompat.check(buildInfo: [:]).isAcceptable)
        XCTAssertEqual(RuntimeCompat.check(buildInfo: ["core_runtime": "  "]).status, .unknown)
    }

    func testCheckRefusesAnAbiOutsideTheAcceptedRange() {
        for abi in ["0.9", "3.0"] {
            let r = RuntimeCompat.check(buildInfo: ["core_runtime": "0.38.0", "abi": abi])
            XCTAssertEqual(r.status, .incompatibleAbi, abi)
            XCTAssertFalse(r.isAcceptable)
            XCTAssertTrue(r.message.contains(RuntimeCompat.installCommand))
        }
    }

    func testCheckAcceptsAbiOneAndTwo() {
        for abi in ["1.0", "1.1", "2.0", "2.3"] {
            let r = RuntimeCompat.check(buildInfo: ["core_runtime": "0.38.0", "abi": abi])
            XCTAssertTrue(r.isAcceptable, abi)
            XCTAssertEqual(r.abi, abi)
        }
    }

    func testMalformedAbiFallsBackToVersionChecks() {
        let r = RuntimeCompat.check(buildInfo: ["core_runtime": "0.38.0", "abi": "two"])
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
        let compat = RuntimeCompat.check(buildInfo: ["core_runtime": "0.38.0", "abi": "3.0"])
        let e = SynheartRuntimeError.incompatible(compat)
        XCTAssertEqual(e.kind, .incompatible)
        XCTAssertEqual(e.runtimeVersion, "0.38.0")
        XCTAssertEqual(e.runtimeAbi, "3.0")
        XCTAssertEqual(e.installCommand, RuntimeCompat.installCommand)
        XCTAssertEqual(e.recommendedVersion, RuntimeCompat.writtenAgainst)
    }
}
