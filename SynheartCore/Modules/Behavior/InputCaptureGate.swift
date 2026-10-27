import Foundation

/// Decides when to tell the runtime input capture is running.
///
/// Capture counts as running only while the behaviour module collects with
/// consent **and** the app is active: the interaction this SDK sees is in-app
/// only, so reporting it running in the background would certify windows as
/// input-free while the person types elsewhere — and a window certified
/// input-free can teach the resting heart rate and HRV.
///
/// `report` fires only when the combined level changes, with the level to
/// report.
final class InputCaptureGate {
    private let report: (Bool) -> Void
    private let lock = NSLock()
    private var tracking = false
    private var foreground = false
    private var reported: Bool?

    init(report: @escaping (Bool) -> Void) {
        self.report = report
    }

    /// The level last reported, or nil before the first report.
    var lastReported: Bool? {
        lock.lock(); defer { lock.unlock() }
        return reported
    }

    func setTracking(_ running: Bool) {
        update { $0.tracking = running }
    }

    func setForeground(_ active: Bool) {
        update { $0.foreground = active }
    }

    /// Forget everything without reporting, for teardown.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        tracking = false
        foreground = false
        reported = nil
    }

    private func update(_ change: (InputCaptureGate) -> Void) {
        lock.lock()
        change(self)
        let running = tracking && foreground
        // Nothing to say until something runs: the runtime's default is
        // already "not running".
        let shouldReport = (reported == nil && running) || (reported != nil && reported != running)
        if shouldReport { reported = running }
        lock.unlock()
        if shouldReport { report(running) }
    }
}
