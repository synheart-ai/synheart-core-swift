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
            windowMs: Int64 = 60_000,
            stepMs: Int64 = 5_000,
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

    /// Return the last quality-report JSON, or nil.
    public func lastQuality() -> String? {
        guard let h = handle else { return nil }
        guard let ptr = RuntimeFFI.lastQuality(h) else { return nil }
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
    private typealias LastQualityFn       = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?
    private typealias FrameCountFn        = @convention(c) (OpaquePointer?) -> UInt64
    private typealias ResetFn             = @convention(c) (OpaquePointer?) -> Void
    private typealias FreeStringFn        = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    private typealias VersionFn           = @convention(c) () -> UnsafeMutablePointer<CChar>?

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

    private static let _lastQuality: LastQualityFn? = {
        guard let sym = dlsym(handle, "synheart_runtime_last_quality") else { return nil }
        return unsafeBitCast(sym, to: LastQualityFn.self)
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

    static func lastQuality(_ runtime: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
        _lastQuality?(runtime)
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
}
