import Foundation
import Combine

/// Thin entry point that replaces `Synheart.swift`'s internal storage / crypto /
/// sync / consent / pipeline logic with FFI calls to `synheart-core-runtime`.
///
/// Platform-specific modules (WearModule, PhoneModule, BehaviorModule, SessionModule)
/// remain in their existing files -- this class only delegates the "core services"
/// layer to the native runtime.
///
/// Usage:
/// ```swift
/// let shim = try SynheartCoreShim(config: SynheartConfig(...))
/// let handle = shim.startSession()
/// shim.pushHr(tsMs: now, bpm: 72.0)
/// shim.stopSession()
/// ```
public final class SynheartCoreShim {

    /// The underlying FFI bridge. Nil only if the runtime library is not linked.
    public let bridge: CoreRuntimeBridge?

    /// Whether the native runtime was loaded successfully.
    public var isAvailable: Bool { bridge != nil }

    /// Stream of HSI state updates (parsed from the native runtime).
    public let onStateUpdate: AnyPublisher<HSIState, Never>

    private let hsiSubject = PassthroughSubject<HSIState, Never>()

    // MARK: - Init

    /// Initialize the shim from a `SynheartConfig`.
    ///
    /// Serializes the config to JSON and passes it to `synheart_core_new`.
    /// Throws `SynheartError.notInitialized` if the runtime library is not linked.
    public init(config: SynheartConfig) throws {
        self.onStateUpdate = hsiSubject.eraseToAnyPublisher()

        let configDict = Self.configToDict(config)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: configDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SynheartError.notInitialized
        }

        guard let b = CoreRuntimeBridge(configJson: jsonString) else {
            throw SynheartError.notInitialized
        }
        self.bridge = b
    }

    /// Create a shim with an externally-provided bridge (for testing).
    public init(bridge: CoreRuntimeBridge) {
        self.onStateUpdate = hsiSubject.eraseToAnyPublisher()
        self.bridge = bridge
    }

    // MARK: - Session Lifecycle

    /// Start a session. Returns a `SessionHandle`, or nil on failure.
    @discardableResult
    public func startSession() -> SessionHandle? {
        guard let json = bridge?.startSession() else { return nil }
        return parseSessionHandle(json)
    }

    /// Stop the current session. Returns true on success.
    @discardableResult
    public func stopSession() -> Bool {
        bridge?.stopSession() ?? false
    }

    /// Get the current session handle, or nil.
    public var currentSession: SessionHandle? {
        guard let json = bridge?.currentSession() else { return nil }
        return parseSessionHandle(json)
    }

    /// Whether a session is running.
    public var isRunning: Bool {
        bridge?.isRunning() ?? false
    }

    // MARK: - Sensor Push

    public func pushRr(tsMs: Int64, rrMs: Double) {
        bridge?.pushRr(tsMs: tsMs, rrMs: rrMs)
    }

    public func pushHr(tsMs: Int64, bpm: Double) {
        bridge?.pushHr(tsMs: tsMs, bpm: bpm)
    }

    public func pushAccel(tsMs: Int64, x: Double, y: Double, z: Double) {
        bridge?.pushAccel(tsMs: tsMs, x: x, y: y, z: z)
    }

    public func pushBehavior(tsMs: Int64, eventType: Int32, value: Double) {
        bridge?.pushBehavior(tsMs: tsMs, eventType: eventType, value: value)
    }

    public func pushSleepStages(json: String) {
        bridge?.pushSleepStages(json: json)
    }

    /// Batch-ingest events. Returns an `HSIState` if a window completed, or nil.
    public func ingestBatch(batchJson: String, nowMs: Int64) -> HSIState? {
        guard let json = bridge?.ingestBatch(batchJson: batchJson, nowMs: nowMs) else { return nil }
        let state = HSIState.fromJson(json)
        hsiSubject.send(state)
        return state
    }

    // MARK: - Ambient Capture

    public func setAmbientCapture(_ enabled: Bool) {
        bridge?.setAmbientCapture(enabled)
    }

    public func getAmbientCapture() -> Bool {
        bridge?.getAmbientCapture() ?? false
    }

    // MARK: - Consent

    @discardableResult
    public func grantConsent(_ type: String) -> Bool {
        bridge?.grantConsent(type: type) ?? false
    }

    @discardableResult
    public func revokeConsent(_ type: String) -> Bool {
        bridge?.revokeConsent(type: type) ?? false
    }

    public func hasConsent(_ type: String) -> Bool {
        bridge?.hasConsent(type: type) ?? false
    }

    /// Full consent snapshot as a dictionary.
    public func currentConsent() -> [String: Any]? {
        guard let json = bridge?.currentConsent() else { return nil }
        return parseJsonDict(json)
    }

    // MARK: - Capabilities

    @discardableResult
    public func loadCapabilityToken(tokenJson: String, secret: String) -> Bool {
        bridge?.loadCapabilityToken(tokenJson: tokenJson, secret: secret) ?? false
    }

    // MARK: - Queries

    /// List sessions as parsed dictionaries.
    public func listSessions() -> [[String: Any]] {
        guard let json = bridge?.listSessions() else { return [] }
        return parseJsonArray(json)
    }

    /// Get a decrypted session summary as a dictionary.
    public func getSessionSummary(_ sessionId: String) -> [String: Any]? {
        guard let json = bridge?.getSessionSummary(sessionId: sessionId) else { return nil }
        return parseJsonDict(json)
    }

    /// Enrol the device in a research study by redeeming an access + study code.
    public func enrolResearchStudy(accessCode: String, studyCode: String) -> [String: Any]? {
        guard let json = bridge?.enrolResearchStudy(accessCode: accessCode, studyCode: studyCode) else { return nil }
        return parseJsonDict(json)
    }

    /// Preview an access + study code pair without redeeming the code.
    public func validateResearchStudyCodes(accessCode: String, studyCode: String) -> [String: Any]? {
        guard let json = bridge?.validateResearchStudyCodes(accessCode: accessCode, studyCode: studyCode) else { return nil }
        return parseJsonDict(json)
    }

    /// Withdraw from the device's active research study for this app.
    public func withdrawResearchStudy() -> [String: Any]? {
        guard let json = bridge?.withdrawResearchStudy() else { return nil }
        return parseJsonDict(json)
    }

    /// Request erasure of the data the participant contributed to their study.
    /// `dryRun` returns an inventory preview without deleting; a real request is
    /// accepted asynchronously and carries a `request_id`.
    public func requestStudyDataDeletion(dryRun: Bool = false) -> [String: Any]? {
        guard let json = bridge?.requestStudyDataDeletion(dryRun: dryRun) else { return nil }
        return parseJsonDict(json)
    }

    /// Get decrypted HSI windows for a session.
    public func getHSIWindows(_ sessionId: String, range: WindowRange? = nil) -> [[String: Any]] {
        let startMs = range?.startMs ?? 0
        let endMs = range?.endMs ?? 0
        let limit = Int32(range?.limit ?? 0)
        guard let json = bridge?.getHsiWindows(
            sessionId: sessionId,
            startMs: startMs,
            endMs: endMs,
            limit: limit
        ) else { return [] }
        return parseJsonArray(json)
    }

    /// Storage usage summary.
    public func getStorageUsage() -> StorageUsage {
        guard let json = bridge?.getStorageUsage(),
              let dict = parseJsonDict(json) else {
            return StorageUsage(totalBytes: 0, bySessionBytes: [:])
        }
        let totalBytes = (dict["total_bytes"] as? NSNumber)?.int64Value ?? 0
        return StorageUsage(totalBytes: totalBytes, bySessionBytes: [:])
    }

    // MARK: - Metrics

    /// Record a metric event. Returns true on success.
    @discardableResult
    public func recordMetric(_ event: MetricEvent) -> Bool {
        var dict: [String: Any] = [
            "name": event.name,
            "timestamp_ms": event.timestampMs,
            "value": event.value,
        ]
        if let tags = event.tags { dict["tags"] = tags }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else { return false }
        return bridge?.recordMetric(json: json) ?? false
    }

    // MARK: - Deletion

    @discardableResult
    public func deleteSession(_ sessionId: String) -> Bool {
        bridge?.deleteSession(sessionId: sessionId) ?? false
    }

    @discardableResult
    public func wipeLocalData() -> Bool {
        bridge?.wipeLocalData() ?? false
    }

    /// Set retention days. Returns number of deleted artifacts, or -1 on error.
    public func setRetentionDays(_ days: Int) -> Int64 {
        bridge?.setRetentionDays(days: Int32(days)) ?? -1
    }

    // MARK: - Sync

    public func setSyncEnabled(_ enabled: Bool) {
        bridge?.setSyncEnabled(enabled: enabled)
    }

    /// Run a push/pull sync cycle. Returns a `SyncResult`.
    public func syncNow() -> SyncResult {
        guard let json = bridge?.syncNow(), let dict = parseJsonDict(json) else {
            return SyncResult()
        }
        return SyncResult(
            pushed: (dict["pushed"] as? Int) ?? 0,
            pulled: (dict["pulled"] as? Int) ?? 0,
            errors: (dict["errors"] as? [String]) ?? []
        )
    }

    // MARK: - SRM / Baselines

    public func baselinesJson() -> String? { bridge?.baselinesJson() }
    public func exportSrmSnapshot() -> String? { bridge?.exportSrmSnapshot() }

    @discardableResult
    public func loadSrmSnapshot(_ json: String) -> Bool {
        bridge?.loadSrmSnapshot(json: json) ?? false
    }

    /// Overall SRM status string: "empty", "warming", or "ready".
    public func srmOverallStatus() -> String? {
        guard let json = bridge?.srmOverallStatus(),
              let dict = parseJsonDict(json) else { return nil }
        return dict["status"] as? String
    }

    // MARK: - Cloud / Upload Queue

    public func enqueueHsi(json: String, timestampMs: Int64) {
        bridge?.enqueueHsi(json: json, timestampMs: timestampMs)
    }

    public var uploadQueueLength: Int { bridge?.uploadQueueLength() ?? 0 }

    public func flushUploads() -> [String: Any]? {
        guard let json = bridge?.flushUploads() else { return nil }
        return parseJsonDict(json)
    }

    public func uploadMetadata() -> [String: Any]? {
        guard let json = bridge?.uploadMetadata() else { return nil }
        return parseJsonDict(json)
    }

    // MARK: - Wellness Score

    /// Get the last Wellness Score as a dictionary, or nil if baselines are not ready.
    public func wellnessScore() -> [String: Any]? {
        guard let json = bridge?.wellnessJson() else { return nil }
        return parseJsonDict(json)
    }

    // MARK: - Diagnostics

    public func diagnostics() -> [String: Any]? {
        guard let json = bridge?.diagnostics() else { return nil }
        return parseJsonDict(json)
    }

    public var lastErrorCode: Int { bridge?.lastErrorCode() ?? 0 }
    public var isRuntimeAvailable: Bool { bridge?.isRuntimeAvailable() ?? false }
    public var isNetworkReachable: Bool { bridge?.isNetworkReachable() ?? false }

    // MARK: - Account Deletion

    public func requestAccountDeletion() -> DeletionRequestResult {
        let ok = bridge?.requestAccountDeletion() ?? false
        return DeletionRequestResult(
            status: ok ? "accepted" : "failed",
            message: ok ? "Account deletion requested." : "Request failed."
        )
    }

    @discardableResult
    public func cancelAccountDeletion() -> Bool {
        bridge?.cancelAccountDeletion() ?? false
    }

    // MARK: - JSON Parsing Helpers

    private func parseJsonDict(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseJsonArray(_ json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr
    }

    private func parseSessionHandle(_ json: String) -> SessionHandle? {
        guard let dict = parseJsonDict(json) else { return nil }
        guard let sessionId = dict["session_id"] as? String else { return nil }
        let startedAtMs = (dict["started_at_ms"] as? NSNumber)?.int64Value ?? 0
        let modeStr = (dict["mode"] as? String) ?? "personal"
        let mode = SynheartMode(rawValue: modeStr) ?? .personal
        return SessionHandle(sessionId: sessionId, startedAtMs: startedAtMs, mode: mode)
    }

    // MARK: - Config Serialization

    private static func configToDict(_ config: SynheartConfig) -> [String: Any] {
        var dict: [String: Any] = [
            "app_id": config.appId,
            "subject_id": config.subjectId,
            "mode": config.mode.rawValue,
            "device_id": config.deviceId,
            "app_version": config.appVersion,
            "platform": config.platform,
            "storage": [
                "enabled": config.storage.enabled,
            ],
            "sync": [
                "enabled": config.sync.enabled,
            ],
            "privacy": [
                "allow_research": config.privacy.allowResearch,
            ],
        ]
        if let token = config.capabilityToken,
           let tokenData = try? JSONEncoder().encode(token),
           let tokenStr = String(data: tokenData, encoding: .utf8) {
            dict["capability_token"] = tokenStr
        }
        if let secret = config.capabilitySecret {
            dict["capability_secret"] = secret
        }
        return dict
    }
}
