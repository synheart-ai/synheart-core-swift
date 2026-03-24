import Foundation

/// Bridge to the synheart-runtime Rust library via C ABI.
///
/// Uses dlsym-based dynamic loading.
/// When the native library is not linked (e.g., SwiftPM macOS builds, CI),
/// `createIfAvailable()` returns nil and the caller stays gracefully inert.
public final class RuntimeBridge {
    private var handle: OpaquePointer?

    public struct Config {
        public let windowMs: Int64
        public let stepMs: Int64
        public let subjectId: String
        public let sessionId: String
        public let behaviorEnabled: Bool

        public init(
            windowMs: Int64 = SynheartDefaults.runtimeWindowMs,
            stepMs: Int64 = SynheartDefaults.runtimeStepMs,
            subjectId: String,
            sessionId: String,
            behaviorEnabled: Bool = true
        ) {
            self.windowMs = windowMs
            self.stepMs = stepMs
            self.subjectId = subjectId
            self.sessionId = sessionId
            self.behaviorEnabled = behaviorEnabled
        }
    }

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        if let h = handle {
            RuntimeFFI.free(h)
        }
    }

    /// Create a RuntimeBridge if the native library is available, otherwise nil.
    public static func createIfAvailable(config: Config) -> RuntimeBridge? {
        guard RuntimeFFI.isAvailable else { return nil }

        let configJson: [String: Any] = [
            "window_ms": config.windowMs,
            "step_ms": config.stepMs,
            "subject_id": config.subjectId,
            "session_id": config.sessionId,
            "behavior_enabled": config.behaviorEnabled
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: configJson),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        guard let ptr = jsonString.withCString({ cStr in
            RuntimeFFI.runtimeNew(cStr)
        }) else {
            return nil
        }

        return RuntimeBridge(handle: ptr)
    }

    // MARK: - Push API

    /// Push an RR-interval sample (milliseconds).
    public func pushRr(tsMs: Int64, rrMs: Double) {
        guard let h = handle else { return }
        RuntimeFFI.pushRr(h, tsMs, rrMs)
    }

    /// Push a heart-rate sample (beats per minute).
    public func pushHr(tsMs: Int64, bpm: Double) {
        guard let h = handle else { return }
        RuntimeFFI.pushHr(h, tsMs, bpm)
    }

    /// Push a tri-axis accelerometer sample.
    public func pushAccel(tsMs: Int64, x: Double, y: Double, z: Double) {
        guard let h = handle else { return }
        RuntimeFFI.pushAccel(h, tsMs, x, y, z)
    }

    /// Push a behavior event.
    ///
    /// Event types (int32):
    ///   0 = ScreenOn, 1 = ScreenOff, 2 = Touch, 3 = AppSwitch, 4 = Notification
    public func pushBehavior(tsMs: Int64, eventType: Int32, value: Double) {
        guard let h = handle else { return }
        RuntimeFFI.pushBehavior(h, tsMs, eventType, value)
    }

    // MARK: - Query API

    /// Advance the engine clock to `nowMs` and return the latest HSI JSON frame,
    /// or nil if the engine produced no output.
    public func tick(nowMs: Int64) -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.tick(h, nowMs) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    /// Ingest a batch of events (JSON array). Returns result JSON or nil.
    ///
    /// The batch JSON is an array of event objects, each with `type`, `ts_ms`, and
    /// type-specific fields (e.g., `rr_ms` for RR events, `event` for behavior).
    ///
    /// Returns a JSON result with `ok`, `frames` array (each containing `hsi`), or
    /// legacy single `hsi` field.
    public func ingestBatch(batchJson: String, nowMs: Int64) -> String? {
        guard let h = handle else { return nil }
        guard let ptr = batchJson.withCString({ cStr in
            RuntimeFFI.ingestBatch(h, cStr, nowMs)
        }) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    /// Return the last quality-report JSON, or nil.
    public func lastQuality() -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.lastQuality(h) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    /// Return the latest HSV (Human State Vector) values as JSON, or nil
    /// if no window has completed yet.
    ///
    /// The JSON contains per-head values (emotion, focus, capacity, recovery,
    /// strain, sleep) with confidence and inference metadata. This is the
    /// canonical source for all HSV data.
    public func lastHsv() -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.lastHsv(h) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    /// Return the latest pre-processed window as JSON (internal use only), or nil
    /// if no window has completed yet.
    ///
    /// The JSON contains quality metrics, derived features (HRV, motion, artifact),
    /// behavior features, SRM baseline context with Z-score deviations, and 64D
    /// signal embeddings. Used for on-device model training, R&D, and diagnostics.
    public func lastPreprocessed() -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.lastPreprocessed(h) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    /// Number of HSI frames produced so far.
    public func frameCount() -> UInt64 {
        guard let h = handle else { return 0 }
        return RuntimeFFI.frameCount(h)
    }

    /// Reset the engine state (clears all internal buffers).
    public func reset() {
        guard let h = handle else { return }
        RuntimeFFI.reset(h)
    }

    /// Return the linked runtime library version string, or nil.
    public static func version() -> String? {
        guard RuntimeFFI.isAvailable else { return nil }
        guard let ptr = RuntimeFFI.version() else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    // MARK: - Wearable SRM

    /// Push a daily value for a longitudinal wearable dimension.
    public func pushWearableDailyValue(dimension: String, dayIndex: Int, value: Double, confidence: Double, fidelity: Int32) {
        guard let h = handle else { return }
        dimension.withCString { dimCStr in
            RuntimeFFI.pushWearableDailyValue(h, dimCStr, UInt32(dayIndex), value, confidence, fidelity)
        }
    }

    /// Trigger longitudinal recompute and pass the reference to state runtime.
    public func triggerWearableRecompute(triggerType: Int32, asOfDay: Int) {
        guard let h = handle else { return }
        RuntimeFFI.triggerWearableRecompute(h, triggerType, UInt32(asOfDay))
    }

    /// Return the current wearable reference as JSON, or nil if EMPTY.
    public func getWearableReference() -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.getWearableReference(h) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    // MARK: - SRM Baselines

    /// Return all SRM baselines as JSON, or nil.
    public func baselinesJson() -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.baselinesJson(h) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    /// Return baseline summary as JSON: `{"total":14,"ready":0,"warming":5,"empty":9}`.
    public func baselineSummary() -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.baselineSummary(h) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    /// Export the SRM snapshot as JSON for persistence, or nil.
    /// Internal: used by RuntimeModule for auto-save/load lifecycle.
    func exportSrmSnapshot() -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.exportSrmSnapshot(h) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }

    /// Load an SRM snapshot from JSON. Returns 0 on success, error code on failure.
    /// Internal: used by RuntimeModule for auto-save/load lifecycle.
    func loadSrmSnapshot(json: String) -> Int32 {
        guard let h = handle else { return 3003 }
        return json.withCString { cStr in
            RuntimeFFI.loadSrmSnapshot(h, cStr)
        }
    }

    // MARK: - Lab Session

    /// Whether the lab C ABI symbols are available in the linked runtime.
    public var isLabAvailable: Bool { RuntimeFFI.isLabAvailable }

    /// Start a lab session.
    ///
    /// `protocolJson` should contain: `namespace`, `protocol_version`, `parameters`,
    /// and optionally `app_id`, `device_id`, `user_id`, `protocol_id`.
    ///
    /// Returns nil on success, or an error string on failure.
    public func labStart(protocolJson: String, startedAtMs: Int64) -> String? {
        guard let h = handle else { return "no handle" }
        guard let ptr = protocolJson.withCString({ cStr in
            RuntimeFFI.labStart(h, cStr, startedAtMs)
        }) else {
            return nil // success
        }
        let err = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return err
    }

    /// Open a window in the active lab session. Returns the window ID, or nil on failure.
    public func labOpenWindow(
        parentId: String?,
        windowType: String,
        label: String?,
        startedAtMs: Int64
    ) -> String? {
        guard let h = handle else { return nil }

        let result: UnsafeMutablePointer<CChar>? = windowType.withCString { wtCStr in
            if let parentId = parentId {
                return parentId.withCString { pidCStr in
                    if let label = label {
                        return label.withCString { lblCStr in
                            RuntimeFFI.labOpenWindow(h, pidCStr, wtCStr, lblCStr, startedAtMs)
                        }
                    } else {
                        return RuntimeFFI.labOpenWindow(h, pidCStr, wtCStr, nil, startedAtMs)
                    }
                }
            } else {
                if let label = label {
                    return label.withCString { lblCStr in
                        RuntimeFFI.labOpenWindow(h, nil, wtCStr, lblCStr, startedAtMs)
                    }
                } else {
                    return RuntimeFFI.labOpenWindow(h, nil, wtCStr, nil, startedAtMs)
                }
            }
        }

        guard let ptr = result else { return nil }
        let windowId = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return windowId
    }

    /// Close a window in the active lab session.
    public func labCloseWindow(windowId: String, endedAtMs: Int64) {
        guard let h = handle else { return }
        windowId.withCString { wid in
            RuntimeFFI.labCloseWindow(h, wid, endedAtMs)
        }
    }

    /// Set protocol-specific values on a lab window.
    public func labSetWindowValues(windowId: String, valuesJson: String) {
        guard let h = handle else { return }
        windowId.withCString { wid in
            valuesJson.withCString { vjson in
                RuntimeFFI.labSetWindowValues(h, wid, vjson)
            }
        }
    }

    /// Finalize the lab session and return the complete payload JSON.
    /// Returns nil if no active session.
    public func labFinalize(endedAtMs: Int64) -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.labFinalize(h, endedAtMs) else { return nil }
        let result = String(cString: ptr)
        RuntimeFFI.freeString(ptr)
        return result
    }
}

// MARK: - Dynamic FFI Loading

/// Dynamically loads the synheart-runtime native library at runtime via dlsym.
/// If the library isn't linked, all function pointers are nil and `isAvailable` is false.
private enum RuntimeFFI {
    // MARK: Type aliases

    private typealias RuntimeNewFn        = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
    private typealias RuntimeFreeFn       = @convention(c) (OpaquePointer?) -> Void
    private typealias PushRrFn            = @convention(c) (OpaquePointer?, Int64, Double) -> Void
    private typealias PushHrFn            = @convention(c) (OpaquePointer?, Int64, Double) -> Void
    private typealias PushAccelFn         = @convention(c) (OpaquePointer?, Int64, Double, Double, Double) -> Void
    private typealias PushBehaviorFn      = @convention(c) (OpaquePointer?, Int64, Int32, Double) -> Void
    private typealias TickFn              = @convention(c) (OpaquePointer?, Int64) -> UnsafeMutablePointer<CChar>?
    private typealias IngestBatchFn       = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64) -> UnsafeMutablePointer<CChar>?
    private typealias LastQualityFn       = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias LastHsvFn           = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias LastPreprocessedFn  = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias FrameCountFn        = @convention(c) (OpaquePointer?) -> UInt64
    private typealias ResetFn             = @convention(c) (OpaquePointer?) -> Void
    private typealias FreeStringFn        = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    private typealias VersionFn           = @convention(c) () -> UnsafeMutablePointer<CChar>?

    // Wearable SRM
    private typealias PushWearableDailyValueFn   = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UInt32, Double, Double, Int32) -> Int32
    private typealias TriggerWearableRecomputeFn = @convention(c) (OpaquePointer?, Int32, UInt32) -> Int32
    private typealias GetWearableReferenceFn     = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    // SRM
    private typealias BaselinesJsonFn     = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias BaselineSummaryFn   = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias ExportSrmSnapshotFn = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias LoadSrmSnapshotFn   = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32

    // Lab
    private typealias LabStartFn          = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64) -> UnsafeMutablePointer<CChar>?
    private typealias LabOpenWindowFn     = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int64) -> UnsafeMutablePointer<CChar>?
    private typealias LabCloseWindowFn    = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int64) -> Void
    private typealias LabSetWindowValFn   = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
    private typealias LabFinalizeFn       = @convention(c) (OpaquePointer?, Int64) -> UnsafeMutablePointer<CChar>?

    // Try dlopen first (searches @rpath, /usr/local/lib, etc.), then RTLD_DEFAULT for already-linked images.
    private static let handle: UnsafeMutableRawPointer? = {
        #if os(macOS)
        if let h = dlopen("libsynheart_runtime.dylib", RTLD_LAZY) { return h }
        #elseif os(Linux)
        if let h = dlopen("libsynheart_runtime.so", RTLD_LAZY) { return h }
        #endif
        return UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
    }()

    // MARK: Lazy symbol resolution

    private static let _runtimeNew: RuntimeNewFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_new") else { return nil }
        return unsafeBitCast(sym, to: RuntimeNewFn.self)
    }()

    private static let _runtimeFree: RuntimeFreeFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_free") else { return nil }
        return unsafeBitCast(sym, to: RuntimeFreeFn.self)
    }()

    private static let _pushRr: PushRrFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_push_rr") else { return nil }
        return unsafeBitCast(sym, to: PushRrFn.self)
    }()

    private static let _pushHr: PushHrFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_push_hr") else { return nil }
        return unsafeBitCast(sym, to: PushHrFn.self)
    }()

    private static let _pushAccel: PushAccelFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_push_accel") else { return nil }
        return unsafeBitCast(sym, to: PushAccelFn.self)
    }()

    private static let _pushBehavior: PushBehaviorFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_push_behavior") else { return nil }
        return unsafeBitCast(sym, to: PushBehaviorFn.self)
    }()

    private static let _tick: TickFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_tick") else { return nil }
        return unsafeBitCast(sym, to: TickFn.self)
    }()

    private static let _ingestBatch: IngestBatchFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_ingest_batch_json") else { return nil }
        return unsafeBitCast(sym, to: IngestBatchFn.self)
    }()

    private static let _lastQuality: LastQualityFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_last_quality") else { return nil }
        return unsafeBitCast(sym, to: LastQualityFn.self)
    }()

    private static let _lastHsv: LastHsvFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_last_hsv") else { return nil }
        return unsafeBitCast(sym, to: LastHsvFn.self)
    }()

    private static let _lastPreprocessed: LastPreprocessedFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_last_preprocessed") else { return nil }
        return unsafeBitCast(sym, to: LastPreprocessedFn.self)
    }()

    private static let _frameCount: FrameCountFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_frame_count") else { return nil }
        return unsafeBitCast(sym, to: FrameCountFn.self)
    }()

    private static let _reset: ResetFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_reset") else { return nil }
        return unsafeBitCast(sym, to: ResetFn.self)
    }()

    private static let _freeString: FreeStringFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_free_string") else { return nil }
        return unsafeBitCast(sym, to: FreeStringFn.self)
    }()

    private static let _version: VersionFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_version") else { return nil }
        return unsafeBitCast(sym, to: VersionFn.self)
    }()

    // Wearable SRM
    private static let _pushWearableDailyValue: PushWearableDailyValueFn? = {
        guard let sym = dlsym(handle, "synheart_srm_push_wearable_daily_value") else { return nil }
        return unsafeBitCast(sym, to: PushWearableDailyValueFn.self)
    }()

    private static let _triggerWearableRecompute: TriggerWearableRecomputeFn? = {
        guard let sym = dlsym(handle, "synheart_srm_trigger_wearable_recompute") else { return nil }
        return unsafeBitCast(sym, to: TriggerWearableRecomputeFn.self)
    }()

    private static let _getWearableReference: GetWearableReferenceFn? = {
        guard let sym = dlsym(handle, "synheart_srm_get_wearable_reference") else { return nil }
        return unsafeBitCast(sym, to: GetWearableReferenceFn.self)
    }()

    // SRM
    private static let _baselinesJson: BaselinesJsonFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_baselines_json") else { return nil }
        return unsafeBitCast(sym, to: BaselinesJsonFn.self)
    }()

    private static let _baselineSummary: BaselineSummaryFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_baseline_summary") else { return nil }
        return unsafeBitCast(sym, to: BaselineSummaryFn.self)
    }()

    private static let _exportSrmSnapshot: ExportSrmSnapshotFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_export_srm_snapshot") else { return nil }
        return unsafeBitCast(sym, to: ExportSrmSnapshotFn.self)
    }()

    private static let _loadSrmSnapshot: LoadSrmSnapshotFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_load_srm_snapshot") else { return nil }
        return unsafeBitCast(sym, to: LoadSrmSnapshotFn.self)
    }()

    // Lab
    private static let _labStart: LabStartFn? = {
        guard let sym = dlsym(handle, "synheart_lab_start") else { return nil }
        return unsafeBitCast(sym, to: LabStartFn.self)
    }()

    private static let _labOpenWindow: LabOpenWindowFn? = {
        guard let sym = dlsym(handle, "synheart_lab_open_window") else { return nil }
        return unsafeBitCast(sym, to: LabOpenWindowFn.self)
    }()

    private static let _labCloseWindow: LabCloseWindowFn? = {
        guard let sym = dlsym(handle, "synheart_lab_close_window") else { return nil }
        return unsafeBitCast(sym, to: LabCloseWindowFn.self)
    }()

    private static let _labSetWindowValues: LabSetWindowValFn? = {
        guard let sym = dlsym(handle, "synheart_lab_set_window_values") else { return nil }
        return unsafeBitCast(sym, to: LabSetWindowValFn.self)
    }()

    private static let _labFinalize: LabFinalizeFn? = {
        guard let sym = dlsym(handle, "synheart_lab_finalize") else { return nil }
        return unsafeBitCast(sym, to: LabFinalizeFn.self)
    }()

    // MARK: Availability

    static var isAvailable: Bool { _runtimeNew != nil }

    // MARK: Forwarding functions

    static func runtimeNew(_ configJson: UnsafePointer<CChar>?) -> OpaquePointer? {
        _runtimeNew?(configJson)
    }

    static func free(_ runtime: OpaquePointer?) {
        _runtimeFree?(runtime)
    }

    static func pushRr(_ runtime: OpaquePointer?, _ tsMs: Int64, _ rrMs: Double) {
        _pushRr?(runtime, tsMs, rrMs)
    }

    static func pushHr(_ runtime: OpaquePointer?, _ tsMs: Int64, _ bpm: Double) {
        _pushHr?(runtime, tsMs, bpm)
    }

    static func pushAccel(_ runtime: OpaquePointer?, _ tsMs: Int64, _ x: Double, _ y: Double, _ z: Double) {
        _pushAccel?(runtime, tsMs, x, y, z)
    }

    static func pushBehavior(_ runtime: OpaquePointer?, _ tsMs: Int64, _ eventType: Int32, _ value: Double) {
        _pushBehavior?(runtime, tsMs, eventType, value)
    }

    static func tick(_ runtime: OpaquePointer?, _ nowMs: Int64) -> UnsafeMutablePointer<CChar>? {
        _tick?(runtime, nowMs)
    }

    static func ingestBatch(_ runtime: OpaquePointer?, _ batchJson: UnsafePointer<CChar>?, _ nowMs: Int64) -> UnsafeMutablePointer<CChar>? {
        _ingestBatch?(runtime, batchJson, nowMs)
    }

    static func lastQuality(_ runtime: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
        _lastQuality?(runtime)
    }

    static func lastHsv(_ runtime: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
        _lastHsv?(runtime)
    }

    static func lastPreprocessed(_ runtime: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
        _lastPreprocessed?(runtime)
    }

    static func frameCount(_ runtime: OpaquePointer?) -> UInt64 {
        _frameCount?(runtime) ?? 0
    }

    static func reset(_ runtime: OpaquePointer?) {
        _reset?(runtime)
    }

    static func freeString(_ ptr: UnsafeMutablePointer<CChar>?) {
        _freeString?(ptr)
    }

    static func version() -> UnsafeMutablePointer<CChar>? {
        _version?()
    }

    // Wearable SRM
    @discardableResult
    static func pushWearableDailyValue(_ runtime: OpaquePointer?, _ dimension: UnsafePointer<CChar>?, _ dayIndex: UInt32, _ value: Double, _ confidence: Double, _ fidelity: Int32) -> Int32 {
        _pushWearableDailyValue?(runtime, dimension, dayIndex, value, confidence, fidelity) ?? -1
    }

    @discardableResult
    static func triggerWearableRecompute(_ runtime: OpaquePointer?, _ triggerType: Int32, _ asOfDay: UInt32) -> Int32 {
        _triggerWearableRecompute?(runtime, triggerType, asOfDay) ?? -1
    }

    static func getWearableReference(_ runtime: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
        _getWearableReference?(runtime)
    }

    // SRM
    static func baselinesJson(_ runtime: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
        _baselinesJson?(runtime)
    }

    static func baselineSummary(_ runtime: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
        _baselineSummary?(runtime)
    }

    static func exportSrmSnapshot(_ runtime: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
        _exportSrmSnapshot?(runtime)
    }

    static func loadSrmSnapshot(_ runtime: OpaquePointer?, _ snapshotJson: UnsafePointer<CChar>?) -> Int32 {
        _loadSrmSnapshot?(runtime, snapshotJson) ?? 3003
    }

    // Lab
    static var isLabAvailable: Bool { _labStart != nil }

    static func labStart(_ runtime: OpaquePointer?, _ protocolJson: UnsafePointer<CChar>?, _ startedAtMs: Int64) -> UnsafeMutablePointer<CChar>? {
        _labStart?(runtime, protocolJson, startedAtMs)
    }

    static func labOpenWindow(_ runtime: OpaquePointer?, _ parentId: UnsafePointer<CChar>?, _ windowType: UnsafePointer<CChar>?, _ label: UnsafePointer<CChar>?, _ startedAtMs: Int64) -> UnsafeMutablePointer<CChar>? {
        _labOpenWindow?(runtime, parentId, windowType, label, startedAtMs)
    }

    static func labCloseWindow(_ runtime: OpaquePointer?, _ windowId: UnsafePointer<CChar>?, _ endedAtMs: Int64) {
        _labCloseWindow?(runtime, windowId, endedAtMs)
    }

    static func labSetWindowValues(_ runtime: OpaquePointer?, _ windowId: UnsafePointer<CChar>?, _ valuesJson: UnsafePointer<CChar>?) {
        _labSetWindowValues?(runtime, windowId, valuesJson)
    }

    static func labFinalize(_ runtime: OpaquePointer?, _ endedAtMs: Int64) -> UnsafeMutablePointer<CChar>? {
        _labFinalize?(runtime, endedAtMs)
    }
}
