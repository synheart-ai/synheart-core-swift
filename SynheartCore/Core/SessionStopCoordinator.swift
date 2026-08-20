import Foundation

protocol NativeSessionStopping: AnyObject {
    func stopSessionDetailed() -> RuntimeSessionStopReport
    func abortSession(sessionId: String?) -> RuntimeSessionStopReport
    var isRunning: Bool { get }
    var currentSession: SessionHandle? { get }
}

extension SynheartCoreShim: NativeSessionStopping {}

struct SessionStopResolution {
    let mayClearLocalState: Bool
    let stopReport: RuntimeSessionStopReport
    let abortReport: RuntimeSessionStopReport?

    var effectiveReport: RuntimeSessionStopReport {
        abortReport ?? stopReport
    }
}

enum SessionStopCoordinator {
    static func stop(_ runtime: NativeSessionStopping) -> SessionStopResolution {
        let lastKnownSessionId = runtime.currentSession?.sessionId
        let stopReport = runtime.stopSessionDetailed()
        let needsAbort = !stopReport.collectionStopped
            || runtime.isRunning
            || !stopReport.catalogClosed

        guard needsAbort else {
            return SessionStopResolution(
                mayClearLocalState: true,
                stopReport: stopReport,
                abortReport: nil
            )
        }

        let abortReport = runtime.abortSession(
            sessionId: stopReport.sessionId ?? lastKnownSessionId
        )
        return SessionStopResolution(
            mayClearLocalState: abortReport.collectionStopped && !runtime.isRunning,
            stopReport: stopReport,
            abortReport: abortReport
        )
    }
}
