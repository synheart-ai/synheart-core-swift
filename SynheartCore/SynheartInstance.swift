import Foundation

/// An independent native runtime handle for advanced multi-profile or research use.
///
/// Each instance must have a unique subject ID and data directory. The regular
/// `Synheart` facade remains the recommended single-instance API.
public final class SynheartInstance {
    public let config: SynheartConfig
    public let dataDirectory: URL

    private static let registryLock = NSLock()
    private static var activeDirectories = Set<String>()

    private let stateLock = NSLock()
    private var shim: SynheartCoreShim?

    public init(config: SynheartConfig, dataDirectory: URL) throws {
        try config.validate()
        let directory = dataDirectory.standardizedFileURL
        guard directory.isFileURL, !directory.path.isEmpty else {
            throw SynheartCoreError.notConfigured("SynheartInstance requires a local data directory")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let key = directory.resolvingSymlinksInPath().path
        let claimed = Self.registryLock.synchronized { Self.activeDirectories.insert(key).inserted }
        guard claimed else {
            throw SynheartCoreError.notConfigured("Another SynheartInstance already uses this data directory")
        }

        do {
            let runtime = try SynheartCoreShim(config: config, dataDir: directory.path)
            if let bridge = runtime.bridge {
                _ = bridge.setStorageCallbacks()
                if config.deviceAuthConfig != nil { _ = bridge.setSdkCryptoCallbacks() }
                bridge.onNativeHandleReleased = {
                    _ = Self.registryLock.synchronized { Self.activeDirectories.remove(key) }
                }
            }
            self.config = config
            self.dataDirectory = directory
            self.shim = runtime
        } catch {
            _ = Self.registryLock.synchronized { Self.activeDirectories.remove(key) }
            throw error
        }
    }

    deinit { dispose() }

    public var isDisposed: Bool { stateLock.synchronized { shim == nil } }
    public var isSessionRunning: Bool { withShim { $0.isRunning } ?? false }
    public var subjectId: String? {
        guard let bridge = stateLock.synchronized({ shim?.bridge }) else { return nil }
        return bridge.runtimeSubjectId()
    }
    public var isLabAvailable: Bool { withBridge { $0.isLabAvailable() } ?? false }

    @discardableResult
    public func registerDevice(clientId: String) async -> [String: Any]? {
        guard let bridge = withBridge({ $0 }) else { return nil }
        return await bridge.performAsync { bridge in
            guard let raw = bridge.registerDevice(clientId: clientId) else { return nil }
            return Self.decodeMap(raw)
        }
    }

    public func deviceAuthStatus() -> [String: Any]? {
        withBridge { bridge in bridge.deviceAuthStatus().flatMap(Self.decodeMap) } ?? nil
    }

    /// Refresh attestation without rotating this instance's installed identity.
    public func reattestDevice() async throws -> [String: Any] {
        guard let bridge = withBridge({ $0 }) else { throw SynheartError.notInitialized }
        guard bridge.isDeviceReattestAvailable else {
            throw NativeOperationFailure(code: "DEVICE_REATTEST_UNSUPPORTED", reason: .unsupported,
                                         message: "Device re-attestation requires Core v0.24")
        }
        let result: Result<[String: Any], Error> = await bridge.performAsync { bridge in
            Result { try DeviceIdentityResponse.decode(bridge.reattestDevice(), operation: "Re-attestation") }
        }
        return try result.get()
    }

    /// Clear this instance's installed device identity and sync membership.
    public func logoutDevice() async throws -> [String: Any] {
        guard let bridge = withBridge({ $0 }) else { throw SynheartError.notInitialized }
        guard bridge.isDeviceLogoutAvailable else {
            throw NativeOperationFailure(code: "DEVICE_LOGOUT_UNSUPPORTED", reason: .unsupported,
                                         message: "Device logout requires Core v0.24")
        }
        let result: Result<[String: Any], Error> = await bridge.performAsync { bridge in
            Result { try DeviceIdentityResponse.decode(bridge.logoutDevice(), operation: "Device logout") }
        }
        return try result.get()
    }

    @discardableResult
    public func startSession() -> SessionHandle? { withShim { $0.startSession() } ?? nil }

    public func stopSession() -> RuntimeSessionStopReport {
        withShim { $0.stopSessionDetailed() } ?? .unavailable(sessionId: nil)
    }

    public func pushRr(timestampMs: Int64, intervalMs: Double, provider: String = "default_sensor") {
        withShim { $0.pushRr(tsMs: timestampMs, rrMs: intervalMs, provider: provider) }
    }

    public func pushRrBatch(
        anchorTimestampMs: Int64,
        intervalsMs: [Double],
        newestFirst: Bool = false,
        provider: String = "default_sensor"
    ) {
        withBridge {
            $0.pushRrBatch(
                anchorTimestampMs: anchorTimestampMs,
                intervalsMs: intervalsMs,
                newestFirst: newestFirst,
                provider: provider
            )
        }
    }

    public func pushHeartRate(timestampMs: Int64, bpm: Double) {
        withShim { $0.pushHr(tsMs: timestampMs, bpm: bpm) }
    }

    public func pushAcceleration(timestampMs: Int64, x: Double, y: Double, z: Double) {
        withShim { $0.pushAccel(tsMs: timestampMs, x: x, y: y, z: z) }
    }

    /// One wrist-worn accelerometer sample in g. See `Synheart.pushWristAccel`.
    public func pushWristAccel(timestampMs: Int64, x: Double, y: Double, z: Double) {
        withShim { $0.pushWristAccel(tsMs: timestampMs, x: x, y: y, z: z) }
    }

    /// One body-worn accelerometer sample in g with its placement. See `Synheart.pushWornAccel`.
    public func pushWornAccel(timestampMs: Int64, x: Double, y: Double, z: Double, placement: AccelPlacement) {
        withShim { $0.pushWornAccel(tsMs: timestampMs, x: x, y: y, z: z, placementCode: placement.code) }
    }

    public func pushBehavior(timestampMs: Int64, eventType: Int32, value: Double) {
        withShim { $0.pushBehavior(tsMs: timestampMs, eventType: eventType, value: value) }
    }

    public func ingestBatch(json: String, timestampMs: Int64) -> HSIState? {
        withShim { $0.ingestBatch(batchJson: json, nowMs: timestampMs) } ?? nil
    }

    // MARK: - Mobile host surface (per-instance)

    /// Whether the linked runtime takes rich behavior events on this instance.
    /// Same probe as `Synheart.mobileHostAbiSupport["pushBehaviorEvent"]` for
    /// the personal runtime. Both instances link one native library, but a
    /// host feeding two handles should ask the handle it is about to feed.
    public var supportsRichBehaviorEvents: Bool {
        withShim { $0.mobileHostAbiSupport["pushBehaviorEvent"] == true } ?? false
    }

    /// Push one typed behavior event into this instance — most importantly a
    /// windowed typing summary, which the legacy int-coded path cannot express.
    /// Returns the runtime status (`0` = accepted), or `nil` when this instance
    /// is disposed, the symbol is absent, or the event could not be encoded.
    /// Do not also push the raw keystrokes behind a typing summary: the engine
    /// counts both and every rate feature roughly doubles.
    @discardableResult
    public func pushBehaviorEvent(_ event: BehaviorEventInput) -> Int32? {
        guard let json = event.toJSONString() else { return nil }
        return withShim { $0.pushBehaviorEventJson(json) } ?? nil
    }

    // Context fan-in (app identity + keystroke context during a lab window).
    //
    // The static `Synheart.pushContextEvent` and app-foreground events reach
    // the PERSONAL runtime only. A host running a second, research instance
    // had no way to give it an app identity or context evidence, so every
    // research window resolved to the `Unknown` app category (an all-zero
    // interpretation-mask row) and carried `context_label: UK` with no
    // evidence behind it. These are the per-instance equivalents.

    /// Declare which application is in the foreground for THIS instance.
    ///
    /// Send at session start, on every foreground change, and on a slow
    /// heartbeat — repeats are steady-state observations, not switches.
    /// `app` is the bundle identifier. Returns the runtime status (`0` =
    /// accepted), or `nil` when this instance is disposed or the runtime lacks
    /// `push_behavior_event`.
    @discardableResult
    public func pushAppForeground(
        _ app: String,
        tsMs: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> Int32? {
        pushBehaviorEvent(.appForeground(tsMs, app: app))
    }

    /// Push one privacy-preserving context event into this instance — the only
    /// source of `context.deviation.*`, and therefore of CFI. Mirrors the
    /// static `Synheart.pushContextEvent`; keyboard events must come from the
    /// text layer via `ContextEventInput.textChange`, sent for both directions.
    ///
    /// Returns `0` on acceptance, `nil` when this instance is disposed or the
    /// symbol is absent, and a non-zero status most often when the runtime was
    /// built without the `app-context` feature.
    @discardableResult
    public func pushContextEvent(_ event: ContextEventInput) -> Int32? {
        guard let json = event.toJSONString() else { return nil }
        return withShim { $0.pushContextEventJson(json) } ?? nil
    }

    /// Raw-payload escape hatch for ``pushContextEvent(_:)``; prefer the typed
    /// call — a payload that does not parse buffers nothing, and the failure is
    /// indistinguishable from a runtime built without the context feature.
    @discardableResult
    public func pushContextEventJson(_ event: [String: Any]) -> Int32? {
        guard let json = JSONValue.encode(event) else { return nil }
        return withShim { $0.pushContextEventJson(json) } ?? nil
    }

    /// Advance the pipeline clock and return the HSI window that closed, if any.
    ///
    /// The return value is NOT every window this instance completes: once
    /// `startSession` runs, the runtime's own background tick loop closes
    /// windows on the same pipeline, and a window it closes first never comes
    /// back from here. Use ``setHsiListener(_:)`` to receive all of them.
    public func tick(at date: Date = Date()) -> String? {
        withBridge { $0.tick(timestampMs: Int64(date.timeIntervalSince1970 * 1_000)) } ?? nil
    }

    // MARK: - HSI delivery (per-instance)
    //
    // The per-instance equivalent of the static `Synheart.onHSIUpdate`, which
    // reaches the PERSONAL runtime only. Without it a host reading this
    // instance's output had `tick`'s return value alone, and lost every window
    // the runtime's background loop closed first — those windows were still
    // emitted (and uploaded), just unreachable from the host.

    /// Receive every HSI window this instance completes, as raw JSON — whether
    /// the host's ``tick(at:)`` or the runtime's background tick loop closed it.
    ///
    /// Buffered (pull-based) delivery on a runtime ≥ 0.31.1, so no function
    /// pointer crosses the FFI boundary; frames arrive on the next
    /// ``drainHsi()`` or on the bridge's periodic drain. Falls back to a push
    /// callback on an older runtime. A window that also came back from
    /// ``tick(at:)`` is delivered here too, so a host using both deduplicates
    /// (by `meta.ids.hsi_id` or window end). Replaces any listener already set.
    /// No-op when disposed. The listener fires on a background thread.
    public func setHsiListener(_ onHsi: @escaping (String) -> Void) {
        withBridge { $0.setHsiCallback(onHsi) }
    }

    /// Stop HSI delivery. In buffered mode, frames still pending are delivered
    /// once more before the listener is dropped. Idempotent; ``dispose()`` also
    /// clears it.
    public func clearHsiListener() {
        withBridge { $0.clearHsiCallback() }
    }

    /// Deliver pending buffered frames to the listener now, oldest first,
    /// instead of waiting for the periodic drain. Cheap when nothing is
    /// pending; no-op without a listener or outside buffered mode.
    public func drainHsi() {
        withBridge { $0.drainHsi() }
    }

    /// Whether HSI reaches the listener by polling rather than by callback.
    public var isHsiBuffered: Bool { withBridge { $0.isHsiBuffered } ?? false }

    public func syncNow() async -> SyncResult? {
        guard let runtime = withShim({ $0 }) else { return nil }
        return await RuntimeWorkExecutor.run { runtime.syncNow() }
    }

    public func researchStudyStatus() async -> [String: Any]? {
        guard let bridge = withBridge({ $0 }) else { return nil }
        return await RuntimeWorkExecutor.run { bridge.researchStudyStatus() }
    }

    public func enrolResearchStudy(accessCode: String, studyCode: String) async -> [String: Any]? {
        guard let runtime = withShim({ $0 }) else { return nil }
        return await RuntimeWorkExecutor.run {
            runtime.enrolResearchStudy(accessCode: accessCode, studyCode: studyCode)
        }
    }

    public func withdrawResearchStudy() async -> [String: Any]? {
        guard let runtime = withShim({ $0 }) else { return nil }
        return await RuntimeWorkExecutor.run { runtime.withdrawResearchStudy() }
    }

    @discardableResult
    public func startLab(protocolJson: String, startedAtMs: Int64) -> Bool {
        withBridge { $0.labStart(protocolJson: protocolJson, startedAtMs: startedAtMs) } ?? false
    }

    public func openLabWindow(
        parentId: String = "",
        type: String,
        label: String = "",
        startedAtMs: Int64
    ) -> String? {
        withBridge {
            $0.labOpenWindow(parentId: parentId, windowType: type, label: label, startedAtMs: startedAtMs)
        } ?? nil
    }

    @discardableResult
    public func closeLabWindow(id: String, endedAtMs: Int64) -> Bool {
        withBridge { $0.labCloseWindow(windowId: id, endedAtMs: endedAtMs) } ?? false
    }

    public func finalizeLab(endedAtMs: Int64) -> String? {
        withBridge { $0.labFinalize(endedAtMs: endedAtMs) } ?? nil
    }

    @discardableResult
    public func wipeLocalData() -> Bool { withShim { $0.wipeLocalData() } ?? false }

    /// Idempotently frees this instance's native handle.
    public func dispose() {
        stateLock.synchronized { shim = nil }
    }

    private func withShim<T>(_ body: (SynheartCoreShim) -> T) -> T? {
        guard let runtime = stateLock.synchronized({ shim }) else { return nil }
        return body(runtime)
    }

    private func withBridge<T>(_ body: (CoreRuntimeBridge) -> T) -> T? {
        guard let bridge = stateLock.synchronized({ shim?.bridge }) else { return nil }
        return body(bridge)
    }

    private static func decodeMap(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

private extension NSLock {
    func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
