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
    private var directoryRegistration: String?

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
            }
            self.config = config
            self.dataDirectory = directory
            self.shim = runtime
            self.directoryRegistration = key
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
        return await RuntimeWorkExecutor.run {
            guard let raw = bridge.registerDevice(clientId: clientId) else { return nil }
            return Self.decodeMap(raw)
        }
    }

    public func deviceAuthStatus() -> [String: Any]? {
        withBridge { bridge in bridge.deviceAuthStatus().flatMap(Self.decodeMap) } ?? nil
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

    public func pushBehavior(timestampMs: Int64, eventType: Int32, value: Double) {
        withShim { $0.pushBehavior(tsMs: timestampMs, eventType: eventType, value: value) }
    }

    public func ingestBatch(json: String, timestampMs: Int64) -> HSIState? {
        withShim { $0.ingestBatch(batchJson: json, nowMs: timestampMs) } ?? nil
    }

    public func tick(at date: Date = Date()) -> String? {
        withBridge { $0.tick(timestampMs: Int64(date.timeIntervalSince1970 * 1_000)) } ?? nil
    }

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
        let registration = stateLock.synchronized { () -> String? in
            shim = nil
            defer { directoryRegistration = nil }
            return directoryRegistration
        }
        if let registration {
            _ = Self.registryLock.synchronized { Self.activeDirectories.remove(registration) }
        }
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
