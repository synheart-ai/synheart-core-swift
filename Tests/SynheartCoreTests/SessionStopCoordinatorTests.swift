import XCTest
@testable import SynheartCore

final class SessionStopCoordinatorTests: XCTestCase {
    private final class Runtime: NativeSessionStopping {
        var stopResult = false
        var isRunning = true
        var currentSession: SessionHandle?
        func stopSession() -> Bool { stopResult }
    }

    func testFailedStopPreservesNativeActiveSessionHandle() throws {
        let runtime = Runtime()
        runtime.currentSession = SessionHandle(
            sessionId: "sess-active",
            startedAtMs: 123,
            mode: .personal
        )

        let result = SessionStopCoordinator.stop(runtime)

        XCTAssertFalse(result.mayClearLocalState)
        XCTAssertEqual(result.activeSession?.sessionId, "sess-active")
    }

    func testFalseStopResultReconcilesWhenRuntimeIsAlreadyStopped() {
        let runtime = Runtime()
        runtime.isRunning = false

        XCTAssertTrue(SessionStopCoordinator.stop(runtime).mayClearLocalState)
    }
}
