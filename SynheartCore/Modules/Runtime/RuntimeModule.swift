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

    /// When true, buffer events and run batch ingest only on stop.
    public var batchIngestOnStop: Bool

    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?

    private let hsiSubject = PassthroughSubject<String, Never>()

    private var batchEventBuffer: [[String: Any]] = []

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
        srmSnapshotKey: String? = "synheart.srm_snapshot",
        batchIngestOnStop: Bool = false
    ) {
        self._bridge = bridge
        self.wearSamplePublisher = wearSamplePublisher
        self.behaviorEventPublisher = behaviorEventPublisher
        self.srmSnapshotKey = srmSnapshotKey
        self.batchIngestOnStop = batchIngestOnStop
        super.init(moduleId: "runtime")
    }

    // MARK: - SynheartModule Lifecycle

    override public func onStart() async throws {
        SynheartLogger.log("[RuntimeModule] Initialized (native bridge \(_bridge != nil ? "available" : "unavailable"))")

        if _bridge == nil {
            SynheartLogger.log("[RuntimeModule] No native bridge — pipeline inert until synheart_runtime is linked")
            return
        }

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

                    if self.batchIngestOnStop {
                        self.appendWearToBatch(sample: sample, tsMs: tsMs)
                        return
                    }

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

                    if self.batchIngestOnStop {
                        self.batchEventBuffer.append(self.behaviorEventToBatchMap(tsMs: tsMs, event: event))
                        return
                    }

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

        if _bridge != nil && batchIngestOnStop && !batchEventBuffer.isEmpty {
            flushBatchOnStop()
        }

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

    // MARK: - Batch Ingest Helpers

    private func appendWearToBatch(sample: WearSample, tsMs: Int64) {
        if let rrs = sample.rrIntervals, !rrs.isEmpty {
            let totalRrMs = rrs.reduce(0, +)
            var rrTs = tsMs - Int64(totalRrMs)
            for rr in rrs {
                batchEventBuffer.append(["type": "rr", "ts_ms": rrTs, "rr_ms": rr])
                rrTs += Int64(rr)
            }
        } else if let hr = sample.hr, hr > 0 {
            batchEventBuffer.append(["type": "hr", "ts_ms": tsMs, "bpm": hr])
        }
    }

    private func behaviorEventToBatchMap(tsMs: Int64, event: BehaviorEvent) -> [String: Any] {
        let eventName: String
        var options: [String: Any] = [:]
        let meta = event.metadata

        switch event.type {
        case .tap, .keyDown, .keyUp:
            eventName = "touch"
            if let meta = meta {
                if let x = meta["x"] as? Double { options["x"] = x }
                if let y = meta["y"] as? Double { options["y"] = y }
            }
        case .appSwitch:
            eventName = "app_switch"
            if let meta = meta {
                if let fromApp = meta["from_app_id"] { options["from_app_id"] = fromApp }
                if let toApp = meta["to_app_id"] { options["to_app_id"] = toApp }
            }
        case .notificationReceived, .notificationOpened:
            eventName = "notification"
            if let meta = meta {
                if let action = meta["action"] { options["action"] = action }
                if let sourceApp = meta["source_app_id"] { options["source_app_id"] = sourceApp }
            }
        case .scroll:
            eventName = "scroll"
            if let meta = meta {
                if let delta = meta["delta"] as? Double { options["delta"] = delta }
                if let velocity = meta["velocity"] { options["velocity"] = velocity }
                if let direction = meta["direction"] { options["direction"] = direction }
            }
        }

        var result: [String: Any] = [
            "type": "behavior",
            "ts_ms": tsMs,
            "event": eventName,
            "provider": "behavior_app"
        ]
        if !options.isEmpty {
            result["options"] = options
        }
        return result
    }

    private func flushBatchOnStop() {
        guard let bridge = _bridge, !batchEventBuffer.isEmpty else { return }

        batchEventBuffer.sort { ($0["ts_ms"] as? Int64 ?? 0) < ($1["ts_ms"] as? Int64 ?? 0) }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard let batchData = try? JSONSerialization.data(withJSONObject: batchEventBuffer),
              let batchJson = String(data: batchData, encoding: .utf8) else {
            SynheartLogger.log("[RuntimeModule] Failed to serialize batch buffer")
            batchEventBuffer.removeAll()
            return
        }

        guard let resultJson = bridge.ingestBatch(batchJson: batchJson, nowMs: nowMs) else {
            SynheartLogger.log(
                "[RuntimeModule] Batch ingest not available (synheart_runtime_ingest_batch_json missing). " +
                "HSI will not be produced for this session."
            )
            batchEventBuffer.removeAll()
            return
        }

        do {
            guard let resultData = resultJson.data(using: .utf8),
                  let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] else {
                throw NSError(domain: "RuntimeModule", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
            }

            if let ok = result["ok"] as? Bool, ok,
               let frames = result["frames"] as? [[String: Any]], !frames.isEmpty {
                for frame in frames {
                    if let hsi = frame["hsi"] {
                        let hsiData = try JSONSerialization.data(withJSONObject: hsi)
                        if let hsiJson = String(data: hsiData, encoding: .utf8) {
                            SynheartLogger.log("[Runtime] HSI (batch on stop, frame): \(hsiJson)")
                            hsiSubject.send(hsiJson)
                        }
                    }
                }
            } else if let ok = result["ok"] as? Bool, ok, let hsi = result["hsi"] {
                // Legacy: single top-level hsi
                let hsiData = try JSONSerialization.data(withJSONObject: hsi)
                if let hsiJson = String(data: hsiData, encoding: .utf8) {
                    SynheartLogger.log("[Runtime] HSI (batch on stop): \(hsiJson)")
                    hsiSubject.send(hsiJson)
                    // Drain remaining frames
                    let maxDrain = 256
                    var drainCount = 0
                    let drainNowMs = Int64(Date().timeIntervalSince1970 * 1000)
                    while drainCount < maxDrain {
                        guard let drainHsi = bridge.tick(nowMs: drainNowMs) else { break }
                        drainCount += 1
                        SynheartLogger.log("[Runtime] HSI (batch drain): \(drainHsi)")
                        hsiSubject.send(drainHsi)
                    }
                    if drainCount >= maxDrain {
                        SynheartLogger.log("[RuntimeModule] Batch drain hit max iterations (\(maxDrain))")
                    }
                }
            }
        } catch {
            SynheartLogger.log("[RuntimeModule] Batch result parse error: \(error)")
        }
        batchEventBuffer.removeAll()
    }
}
