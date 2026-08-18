import XCTest
@testable import SynheartCore

final class DeletionOutcomeTests: XCTestCase {
    func testAcceptedRequiresBothServerAndLocalSuccess() {
        let result = DeletionOutcome.accountResult(
            serverAccepted: true,
            localWiped: true
        )

        XCTAssertEqual(result.status, "accepted")
        XCTAssertTrue(result.serverDeletionRequested)
        XCTAssertTrue(result.localDataWiped)
    }

    func testServerFailureIsNeverReportedAsAccepted() {
        let result = DeletionOutcome.accountResult(
            serverAccepted: false,
            localWiped: true
        )

        XCTAssertEqual(result.status, "local_only")
        XCTAssertFalse(result.serverDeletionRequested)
        XCTAssertTrue(result.localDataWiped)
    }

    func testLocalFailureProducesPartialResult() {
        let result = DeletionOutcome.accountResult(
            serverAccepted: true,
            localWiped: false
        )

        XCTAssertEqual(result.status, "partial")
        XCTAssertTrue(result.serverDeletionRequested)
        XCTAssertFalse(result.localDataWiped)
    }
}
