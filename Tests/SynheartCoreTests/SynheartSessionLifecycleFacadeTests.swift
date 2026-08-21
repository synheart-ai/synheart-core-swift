import XCTest
@testable import SynheartCore

final class SynheartSessionLifecycleFacadeTests: XCTestCase {
    private final class Runtime: NativeSessionStopping {
        var running = true
        var currentSession: SessionHandle?
        var stopReport: RuntimeSessionStopReport
        var abortReport: RuntimeSessionStopReport
        var runningAfterStop = true
        var runningAfterAbort = true
        var abortCalls = 0

        init(session: SessionHandle) {
            currentSession = session
            stopReport = RuntimeSessionStopReport(
                status: "failed",
                sessionId: session.sessionId,
                collectionStopped: false,
                finalized: false,
                catalogClosed: false,
                failures: [
                    RuntimeSessionStopFailure(stage: "shutdown", error: "engine still running")
                ]
            )
            abortReport = .unavailable(sessionId: session.sessionId)
        }

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

    func testFailedFacadeStopPreservesActiveSessionState() async {
        let handle = makeHandle()
        let runtime = Runtime(session: handle)
        Synheart._setSessionStateForTesting(handle: handle, running: true)
        defer { Synheart._resetSessionStateForTesting() }

        do {
            try await Synheart._stopSessionForTesting(using: runtime)
            XCTFail("Expected native shutdown failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("shutdown failed"))
            XCTAssertTrue(error.localizedDescription.contains("preserved"))
        }

        XCTAssertTrue(Synheart.isRunning)
        XCTAssertEqual(Synheart.currentSession?.sessionId, handle.sessionId)
        XCTAssertEqual(Synheart.lastSessionStopReport?.collectionStopped, false)
        XCTAssertEqual(Synheart.lastSessionStopPhase, "native_shutdown_failed")
        XCTAssertEqual(runtime.abortCalls, 1)

        runtime.stopReport = RuntimeSessionStopReport(
            status: "stopped",
            sessionId: handle.sessionId,
            collectionStopped: true,
            finalized: true,
            catalogClosed: true,
            failures: []
        )
        runtime.runningAfterStop = false

        do {
            try await Synheart._stopSessionForTesting(using: runtime)
        } catch {
            XCTFail("Expected retry to stop the preserved session: \(error)")
        }
        XCTAssertFalse(Synheart.isRunning)
        XCTAssertNil(Synheart.currentSession)
        XCTAssertEqual(Synheart.lastSessionStopPhase, "completed_stopped")
    }

    func testFailedStartupRollbackPreservesHandleAndReportsBothErrors() async {
        let handle = makeHandle()
        let runtime = Runtime(session: handle)
        Synheart._setSessionStateForTesting(handle: handle, running: false)
        defer { Synheart._resetSessionStateForTesting() }

        do {
            try await Synheart._failSessionStartForTesting(
                SynheartError.runtimeOperationFailed("collector startup failed"),
                runtime: runtime
            )
            XCTFail("Expected startup and rollback failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("collector startup failed"))
            XCTAssertTrue(error.localizedDescription.contains("native rollback also failed"))
        }

        XCTAssertTrue(Synheart.isRunning)
        XCTAssertEqual(Synheart.currentSession?.sessionId, handle.sessionId)
        XCTAssertEqual(Synheart.lastSessionStopReport?.collectionStopped, false)
        XCTAssertEqual(
            Synheart.lastSessionStopPhase,
            "startup_rollback_native_shutdown_failed"
        )
        XCTAssertEqual(runtime.abortCalls, 1)
    }

    private func makeHandle() -> SessionHandle {
        SessionHandle(
            sessionId: "sess-facade-failure",
            startedAtMs: 123,
            mode: .personal
        )
    }
}
