import Foundation
import SynheartSession

/// Adapts `BehaviorModule` into the `BehaviorProvider` protocol expected by
/// `SessionEngine`.
///
/// Pull-based — the session engine calls `currentSnapshot()` at each frame
/// tick to get the latest behavioral signals.
class BehaviorModuleAdapter: BehaviorProvider {

    private weak var behaviorModule: BehaviorModule?

    var isAvailable: Bool { behaviorModule != nil }
    var name: String { "behavior_module" }

    init(behaviorModule: BehaviorModule) {
        self.behaviorModule = behaviorModule
    }

    func currentSnapshot() -> BehaviorSnapshot? {
        guard let module = behaviorModule else { return nil }

        // Pull a 30-second window of raw events to compute the snapshot.
        let events = module.rawEvents(.window30s)
        guard !events.isEmpty else { return nil }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let windowSec: Double = 30.0

        // Count app switches
        let appSwitches = events.filter { $0.type == .appSwitch }.count
        let appSwitchesPerMinute = Int(Double(appSwitches) / windowSec * 60.0)

        // Count taps
        let taps = events.filter { $0.type == .tap }
        let tapRate: Double? = taps.isEmpty ? nil : Double(taps.count) / windowSec

        // Count key events for typing cadence
        let keyDowns = events.filter { $0.type == .keyDown }
        let typingCadence: Double? = keyDowns.isEmpty ? nil : Double(keyDowns.count) / windowSec

        // Scroll events
        let scrolls = events.filter { $0.type == .scroll }
        let scrollVelocity: Double? = scrolls.isEmpty ? nil : scrolls.compactMap { event -> Double? in
            event.metadata?["delta"] as? Double
        }.reduce(0, +) / windowSec

        return BehaviorSnapshot(
            typingCadence: typingCadence,
            scrollVelocity: scrollVelocity,
            tapRate: tapRate,
            appSwitchesPerMinute: appSwitchesPerMinute,
            timestamp: nowMs
        )
    }
}
