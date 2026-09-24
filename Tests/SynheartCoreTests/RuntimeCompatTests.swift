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
}
