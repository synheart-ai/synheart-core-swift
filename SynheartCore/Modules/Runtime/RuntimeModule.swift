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

    private let bridge: RuntimeBridge?
    private let wearSamplePublisher: AnyPublisher<WearSample, Never>?
    private let behaviorEventPublisher: AnyPublisher<BehaviorEvent, Never>?

    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?

    private let hsiSubject = PassthroughSubject<String, Never>()

    /// Stream of raw HSI JSON frames produced by the runtime engine.
    public var hsiStream: AnyPublisher<String, Never> {
        hsiSubject.eraseToAnyPublisher()
    }

    public init(
        bridge: RuntimeBridge?,
        wearSamplePublisher: AnyPublisher<WearSample, Never>? = nil,
        behaviorEventPublisher: AnyPublisher<BehaviorEvent, Never>? = nil
    ) {
        self.bridge = bridge
        self.wearSamplePublisher = wearSamplePublisher
        self.behaviorEventPublisher = behaviorEventPublisher
        super.init(moduleId: "runtime")
    }

    // MARK: - SynheartModule Lifecycle

    override public func onStart() async throws {
        print("[RuntimeModule] Starting...")

        // Subscribe to wear samples
        if let wearPub = wearSamplePublisher {
            wearPub
                .sink { [weak self] sample in
                    guard let self = self, let bridge = self.bridge else { return }
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
                    guard let self = self, let bridge = self.bridge else { return }
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
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, let bridge = self.bridge else { return }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            if let hsiJson = bridge.tick(nowMs: nowMs) {
                self.hsiSubject.send(hsiJson)
            }
        }

        print("[RuntimeModule] Started")
    }

    public override func onStop() async throws {
        print("[RuntimeModule] Stopping...")

        tickTimer?.invalidate()
        tickTimer = nil
        cancellables.removeAll()

        print("[RuntimeModule] Stopped")
    }

    public override func onDispose() async throws {
        print("[RuntimeModule] Disposing...")
        hsiSubject.send(completion: .finished)
    }
}
