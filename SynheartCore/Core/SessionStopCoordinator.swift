import Foundation

protocol NativeSessionStopping: AnyObject {
    func stopSession() -> Bool
    var isRunning: Bool { get }
    var currentSession: SessionHandle? { get }
}

extension SynheartCoreShim: NativeSessionStopping {}

struct SessionStopResolution {
    let mayClearLocalState: Bool
    let activeSession: SessionHandle?
}

enum SessionStopCoordinator {
    static func stop(_ runtime: NativeSessionStopping) -> SessionStopResolution {
        if runtime.stopSession() || !runtime.isRunning {
            return SessionStopResolution(mayClearLocalState: true, activeSession: nil)
        }
        return SessionStopResolution(
            mayClearLocalState: false,
            activeSession: runtime.currentSession
        )
    }
}
