// SPDX-License-Identifier: Apache-2.0
//
// Tests for AppleXmlBackfillSink type surface and error contract.
// Native FFI integration is exercised by the runtime's own Rust tests.

import XCTest
@testable import SynheartCore

final class AppleXmlBackfillSinkTests: XCTestCase {

    func testBatchResultHoldsCounts() {
        let r = BackfillBatchResult(inserted: 100, skippedAsDuplicate: 5)
        XCTAssertEqual(r.inserted, 100)
        XCTAssertEqual(r.skippedAsDuplicate, 5)
    }

    func testImportResultHoldsTally() {
        let r = BackfillImportResult(
            importId: "import-001",
            totalSamples: 1000,
            inserted: 950,
            skippedAsDuplicate: 50,
            durationMs: 1234
        )
        XCTAssertEqual(r.importId, "import-001")
        XCTAssertEqual(r.totalSamples, 1000)
        XCTAssertEqual(r.inserted, 950)
        XCTAssertEqual(r.skippedAsDuplicate, 50)
        XCTAssertEqual(r.durationMs, 1234)
    }

    func testErrorEqualityForSwitchExhaustiveness() {
        let cases: [BackfillSinkError] = [
            .runtimeUnavailable,
            .openFailed(message: "open"),
            .batchFailed(message: "batch"),
            .finalizeFailed(message: "finalize"),
        ]
        // Exhaustive switch must compile.
        for err in cases {
            let tag: String = {
                switch err {
                case .runtimeUnavailable: return "unavailable"
                case .openFailed: return "open"
                case .batchFailed: return "batch"
                case .finalizeFailed: return "finalize"
                }
            }()
            XCTAssertFalse(tag.isEmpty)
        }
    }

    /// In a unit-test target the runtime is not loaded, so the
    /// dlsym-based symbol resolution returns nil and `isAvailable`
    /// is `false`. Operations should throw `runtimeUnavailable`
    /// rather than crash.
    func testRuntimeUnavailableInUnitTest() {
        let sink = AppleXmlBackfillSink(dbPath: ":memory:")
        // Whether isAvailable is true depends on whether the test
        // binary happens to be linked against the runtime — accept
        // either, but verify behavior matches the report.
        if !sink.isAvailable {
            XCTAssertThrowsError(try sink.open(importId: "x")) { err in
                XCTAssertEqual(err as? BackfillSinkError, .runtimeUnavailable)
            }
        }
    }

    func testOpenRejectsEmptyImportId() {
        let sink = AppleXmlBackfillSink(dbPath: ":memory:")
        XCTAssertThrowsError(try sink.open(importId: "")) { err in
            // Either runtimeUnavailable (no lib) or openFailed
            // (empty id) — both signal "won't open".
            switch err as? BackfillSinkError {
            case .openFailed, .runtimeUnavailable:
                break
            default:
                XCTFail("unexpected error: \(err)")
            }
        }
    }

    func testFinalizeWithoutOpenThrows() {
        let sink = AppleXmlBackfillSink(dbPath: ":memory:")
        XCTAssertThrowsError(try sink.finalize()) { err in
            switch err as? BackfillSinkError {
            case .finalizeFailed, .runtimeUnavailable:
                break
            default:
                XCTFail("unexpected error: \(err)")
            }
        }
    }
}
