import Foundation
import Combine

/// Runtime Module
///
/// Streams raw wear samples and behavior events
/// into the synheart-runtime Rust engine via `RuntimeBridge`, ticks the
/// engine on a 5-second timer, and publishes HSI JSON frames.
///
/// When the native library is not linked, `bridge` is nil and the module
/// stays gracefully inert (no HSI output is produced).
public class RuntimeModule: BaseSynheartModule {

    private let _bridge: RuntimeBridge?
    private let wearSamplePublisher: AnyPublisher<WearSample, Never>?
    private let behaviorEventPublisher: AnyPublisher<BehaviorEvent, Never>?

    /// Access to the native runtime bridge (nil if native library is not linked).
    public var bridge: RuntimeBridge? { _bridge }

    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?

    private let hsiSubject = PassthroughSubject<String, Never>()

    /// Stream of raw HSI JSON frames produced by the runtime engine.
    public var hsiStream: AnyPublisher<String, Never> {
        hsiSubject.eraseToAnyPublisher()
    }

    /// Key used to persist the SRM baseline snapshot in UserDefaults.
    /// Set to nil to disable auto-persistence. Defaults to "synheart.srm_snapshot".
    /// For multi-subject apps, include the subject ID in the key.
    private let srmSnapshotKey: String?

    public init(
        bridge: RuntimeBridge?,
        wearSamplePublisher: AnyPublisher<WearSample, Never>? = nil,
        behaviorEventPublisher: AnyPublisher<BehaviorEvent, Never>? = nil,
        srmSnapshotKey: String? = "synheart.srm_snapshot"
    ) {
        self._bridge = bridge
        self.wearSamplePublisher = wearSamplePublisher
        self.behaviorEventPublisher = behaviorEventPublisher
        self.srmSnapshotKey = srmSnapshotKey
        super.init(moduleId: "runtime")
    }

    // MARK: - SynheartModule Lifecycle

    override public func onStart() async throws {
        SynheartLogger.log("[RuntimeModule] Starting...")

        // Restore SRM baselines from previous session
        if let bridge = _bridge, let key = srmSnapshotKey {
            if let saved = UserDefaults.standard.string(forKey: key) {
                let rc = bridge.loadSrmSnapshot(json: saved)
                if rc == 0 {
                    SynheartLogger.log("[RuntimeModule] Restored SRM baselines from snapshot")
                } else {
                    SynheartLogger.log("[RuntimeModule] SRM snapshot load failed (code \(rc)), starting fresh")
                }
            }
        }

        // Subscribe to wear samples
        if let wearPub = wearSamplePublisher {
            wearPub
                .sink { [weak self] sample in
                    guard let self = self, let bridge = self._bridge else { return }
                    let tsMs = Int64(sample.timestamp.timeIntervalSince1970 * 1000)

                    // Push each RR interval
                    if let rrIntervals = sample.rrIntervals {
                        for rr in rrIntervals {
                            bridge.pushRr(tsMs: tsMs, rrMs: rr)
                        }
                    }

                    // Push heart rate
                    if let hr = sample.hr {
                        bridge.pushHr(tsMs: tsMs, bpm: hr)
                    }
                }
                .store(in: &cancellables)
        }

        // Subscribe to behavior events
        if let behaviorPub = behaviorEventPublisher {
            behaviorPub
                .sink { [weak self] event in
                    guard let self = self, let bridge = self._bridge else { return }
                    let tsMs = Int64(event.timestamp.timeIntervalSince1970 * 1000)

                    switch event.type {
                    case .tap, .scroll, .keyDown, .keyUp:
                        // Touch / input => event type 2
                        bridge.pushBehavior(tsMs: tsMs, eventType: 2, value: 1.0)
                    case .appSwitch:
                        // AppSwitch => event type 3
                        bridge.pushBehavior(tsMs: tsMs, eventType: 3, value: 1.0)
                    case .notificationReceived, .notificationOpened:
                        // Notification => event type 4
                        bridge.pushBehavior(tsMs: tsMs, eventType: 4, value: 1.0)
                    }
                }
                .store(in: &cancellables)
        }

        // Start tick timer (every 5 seconds)
        tickTimer = Timer.scheduledTimer(withTimeInterval: SynheartDefaults.runtimeTickIntervalSeconds, repeats: true) { [weak self] _ in
            guard let self = self, let bridge = self._bridge else { return }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            if let hsiJson = bridge.tick(nowMs: nowMs) {
                self.hsiSubject.send(hsiJson)
            }
        }

        SynheartLogger.log("[RuntimeModule] Started")
    }

    public override func onStop() async throws {
        SynheartLogger.log("[RuntimeModule] Stopping...")

        // Persist SRM baselines for next session
        if let bridge = _bridge, let key = srmSnapshotKey {
            if let snapshot = bridge.exportSrmSnapshot() {
                UserDefaults.standard.set(snapshot, forKey: key)
                SynheartLogger.log("[RuntimeModule] Saved SRM baselines snapshot")
            }
        }

        tickTimer?.invalidate()
        tickTimer = nil
        cancellables.removeAll()

        SynheartLogger.log("[RuntimeModule] Stopped")
    }

    public override func onDispose() async throws {
        SynheartLogger.log("[RuntimeModule] Disposing...")
        hsiSubject.send(completion: .finished)
    }
}
