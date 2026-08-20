import XCTest
@testable import SynheartCore

final class SessionStopCoordinatorTests: XCTestCase {
    private final class Runtime: NativeSessionStopping {
        var running = true
        var currentSession: SessionHandle?
        var stopReport = RuntimeSessionStopReport(
            status: "stopped",
            sessionId: "sess-test",
            collectionStopped: true,
            finalized: true,
            catalogClosed: true,
            failures: []
        )
        var abortReport = RuntimeSessionStopReport(
            status: "aborted",
            sessionId: "sess-test",
            collectionStopped: true,
            finalized: false,
            catalogClosed: true,
            failures: []
        )
        var runningAfterStop = false
        var runningAfterAbort = false
        var abortCalls = 0

        var isRunning: Bool { running }

        func stopSessionDetailed() -> RuntimeSessionStopReport {
            running = runningAfterStop
            return stopReport
        }

        func abortSession(sessionId _: String?) -> RuntimeSessionStopReport {
            abortCalls += 1
            running = runningAfterAbort
            return abortReport
        }
    }

    func testCleanStopDoesNotAbort() {
        let runtime = Runtime()

        let result = SessionStopCoordinator.stop(runtime)

        XCTAssertTrue(result.mayClearLocalState)
        XCTAssertNil(result.abortReport)
        XCTAssertEqual(result.effectiveReport.status, "stopped")
        XCTAssertEqual(runtime.abortCalls, 0)
    }

    func testFinalizationFailureRetriesCatalogClosureThroughAbort() {
        let runtime = Runtime()
        runtime.stopReport = RuntimeSessionStopReport(
            status: "stopped_with_finalize_error",
            sessionId: "sess-active",
            collectionStopped: true,
            finalized: false,
            catalogClosed: false,
            failures: [
                RuntimeSessionStopFailure(stage: "catalog_close", error: "database busy")
            ]
        )

        let result = SessionStopCoordinator.stop(runtime)

        XCTAssertTrue(result.mayClearLocalState)
        XCTAssertEqual(result.stopReport.status, "stopped_with_finalize_error")
        XCTAssertEqual(result.effectiveReport.status, "aborted")
        XCTAssertEqual(runtime.abortCalls, 1)
    }

    func testCollectionFailureUsesNativeAbortInsteadOfResettingHandle() {
        let runtime = Runtime()
        runtime.currentSession = SessionHandle(
            sessionId: "sess-active",
            startedAtMs: 123,
            mode: .personal
        )
        runtime.runningAfterStop = true
        runtime.stopReport = RuntimeSessionStopReport(
            status: "failed",
            sessionId: "sess-active",
            collectionStopped: false,
            finalized: false,
            catalogClosed: false,
            failures: [
                RuntimeSessionStopFailure(stage: "shutdown", error: "failed")
            ]
        )

        let result = SessionStopCoordinator.stop(runtime)

        XCTAssertTrue(result.mayClearLocalState)
        XCTAssertEqual(result.effectiveReport.status, "aborted")
        XCTAssertEqual(runtime.abortCalls, 1)
    }

    func testFailedAbortDoesNotClaimNativeShutdownSucceeded() {
        let runtime = Runtime()
        runtime.runningAfterStop = true
        runtime.runningAfterAbort = true
        runtime.stopReport = RuntimeSessionStopReport(
            status: "failed",
            sessionId: "sess-active",
            collectionStopped: false,
            finalized: false,
            catalogClosed: false,
            failures: []
        )
        runtime.abortReport = .unavailable(sessionId: "sess-active")

        let result = SessionStopCoordinator.stop(runtime)

        XCTAssertFalse(result.mayClearLocalState)
        XCTAssertEqual(runtime.abortCalls, 1)
    }
}
