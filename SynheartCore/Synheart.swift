import Foundation
import Combine
import SynheartAuth
@_exported import SynheartSession // re-exports SessionEvent, SessionConfig, etc.

/**
 * Synheart Core SDK - Main Entry Point
 *
 * Orchestrates all core modules and the native core runtime bridge.
 *
 * Core modules:
 * - Capabilities Module (feature gating)
 * - Consent Module (permission management + scoped access tokens)
 * - Wear Module (biosignal collection)
 * - Phone Module (motion/context)
 * - Behavior Module (interaction patterns)
 * - Core Runtime Bridge (native FFI -- storage, crypto, sync, artifacts, HSI)
 *
 * Example usage:
 * ```swift
 * try await Synheart.initialize(config: SynheartConfig(
 *     appId: "com.example.app",
 *     subjectId: "anon_user_123",
 *     allowUnsignedCapabilities: true
 * ))
 *
 * var cancellables = Set<AnyCancellable>()
 * Synheart.onStateUpdate
 *     .sink { state in print("State: \(state)") }
 *     .store(in: &cancellables)
 *
 * try await Synheart.grantConsent("biosignals")
 * Synheart.activate(.wear)
 * try await Synheart.startSession()
 * try await Synheart.syncNow()
 * ```
 */
public class Synheart {
    public static let shared = Synheart()

    private var coreRuntime: SynheartCoreShim?
    private let moduleManager = ModuleManager()
    private let initializationGate = InitializationGate()

    private var capabilityModule: CapabilityModule?
    private var consentModule: ConsentModule?
    private var wearModule: WearModule?
    private var phoneModule: PhoneModule?
    private var behaviorModule: BehaviorModule?

    private var _activationManager: ActivationManager?

    private var isConfigured = false
    private var isRunning = false
    private var collectionModuleFailures: [String: String] = [:]
    private var userId: String?
    private var previousConsent: ConsentSnapshot?
    private var lastUploadBatchId: String?
    private var lastUploadAt: Date?
    private var lastUploadAttemptAt: Date?
    private var lastUploadFailure: NativeOperationFailure?

    private var _currentSessionHandle: SessionHandle?
    private var _synheartConfig: SynheartConfig?

    private var sessionModule: SessionModule?
    private var sessionSubscription: AnyCancellable?
    private var hsiToSessionCancellable: AnyCancellable?

    private let hsiSubject = CurrentValueSubject<String?, Never>(nil)
    private let typedHsiSubject = CurrentValueSubject<HSIState?, Never>(nil)
    private let hsiDeliveryDeduplicator = HSIDeliveryDeduplicator()
    private var cancellables = Set<AnyCancellable>()

    /// Subject the most recently issued cloud consent token was minted for.
    /// Used to detect a stale (different-subject) token after an account re-key.
    private var currentTokenSubject: String?

    /// Canonical subject reported by the native runtime, captured after init (the
    /// runtime may derive it from `client_id` per RFC-0008) and after a
    /// `rebindSubjectId`. Takes precedence over the configured value so the SDK
    /// agrees with what uploads are attributed under. Nil until the runtime loads.
    private var nativeSubjectIdOverride: String?

    private init() {}

    /// The subject id this SDK instance is bound to — the value uploads are
    /// attributed under and the consent token is minted for. Prefers the native
    /// runtime subject; falls back to the configured value before init. Nil when
    /// not configured.
    var subjectId: String? {
        if let native = nativeSubjectIdOverride, !native.isEmpty { return native }
        return _synheartConfig?.subjectId ?? userId
    }

    /// Capture the runtime's canonical subject so `subjectId` /
    /// `consentTokenSubjectStale` agree with the native source of truth. A
    /// null/empty value (e.g. an older runtime without the symbol) leaves the
    /// override unchanged, keeping the configured fallback.
    private func syncSubjectFromNative() {
        if let native = coreRuntime?.bridge?.runtimeSubjectId(), !native.isEmpty {
            nativeSubjectIdOverride = native
        }
    }

    /// Parse a JSON object string into a dictionary, or nil.
    private func parseDict(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - Public State

    /// Whether the SDK has been initialized.
    public static var isInitialized: Bool {
        shared.isConfigured
    }

    /// The currently active session, if any.
    public static var currentSession: SessionHandle? {
        shared._currentSessionHandle
    }

    /// Whether the SDK is currently running.
    public static var isRunning: Bool {
        shared.isRunning
    }

    /// Collection modules that could not start in the current session. Healthy
    /// independent modules remain operational when this dictionary is non-empty.
    public static var collectionStartupFailures: [String: String] {
        shared.collectionModuleFailures
    }

    /// Stream of HSI JSON frames produced by synheart-engine.
    public static var onHSIUpdate: AnyPublisher<String, Never> {
        shared.hsiSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    // MARK: - Typed State Subscription

    /// Stream of typed HSIState updates.
    public static var onStateUpdate: AnyPublisher<HSIState, Never> {
        shared.typedHsiSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    /// Consent-filtered interaction events accepted by the behavior module and
    /// forwarded to the native runtime during an active behavior session.
    public static var onBehaviorEvent: AnyPublisher<BehaviorEvent, Never> {
        shared.behaviorModule?.capturedEvents
            ?? Empty<BehaviorEvent, Never>().eraseToAnyPublisher()
    }

    /// Real, consent-filtered phone motion samples forwarded to the native runtime.
    public static var onPhoneMotionSample: AnyPublisher<MotionData, Never> {
        shared.phoneModule?.motionSamples
            ?? Empty<MotionData, Never>().eraseToAnyPublisher()
    }

    /// Get the current HSI state as a typed object.
    public static var currentHSIState: HSIState? {
        shared.typedHsiSubject.value
    }

    // MARK: - Metrics API

    /// Record a single metric event for the current session.
    public static func recordMetric(_ event: MetricEvent) throws {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return }
        let _ = cr.recordMetric(event)
    }

    /// Record a batch of metric events for the current session.
    /// Loops over the singular path; useful for hosts that capture bursts.
    public static func recordMetrics(_ events: [MetricEvent]) throws {
        for event in events {
            try recordMetric(event)
        }
    }

    // MARK: - Wear Module — Vendor Events

    /// Process a vendor event from RAMEN into the SRM pipeline.
    ///
    /// The event is normalized to a `CanonicalWearableEvent`, stored, and
    /// pushed to the runtime for longitudinal baseline computation.
    ///
    /// - Returns: The canonical event the vendor payload was mapped to, or
    ///   `nil` if dropped (consent denied, no processor, mapping miss).
    @discardableResult
    public static func processVendorEvent(
        provider: String,
        eventType: String,
        payload: [String: Any],
        eventId: String,
        seq: Int
    ) -> CanonicalWearableEvent? {
        return shared.wearModule?.processVendorEvent(
            provider: provider,
            eventType: eventType,
            payload: payload,
            eventId: eventId,
            seq: seq
        )
    }

    // MARK: - Ambient Capture

    /// When enabled, the runtime forwards every closed HSI window to the
    /// host's HSI callback regardless of session state. When disabled
    /// (default), windows are forwarded only while a session is active.
    public static func setAmbientCapture(_ enabled: Bool) {
        shared.coreRuntime?.setAmbientCapture(enabled)
    }

    /// Returns the current ambient-capture flag (`false` if the runtime
    /// is unavailable or the call hasn't been made).
    public static func getAmbientCapture() -> Bool {
        return shared.coreRuntime?.getAmbientCapture() ?? false
    }

    // MARK: - Local Query API

    /// List stored sessions with optional filters.
    public static func listSessions(range: SessionRange? = nil) throws -> [SessionRecord] {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        return cr.listSessions()
            .compactMap(SessionRecord.init(runtimeMap:))
            .filter { session in
                if let startMs = range?.startMs, session.startUtc < startMs { return false }
                if let endMs = range?.endMs, session.startUtc > endMs { return false }
                if let mode = range?.mode, session.mode != mode { return false }
                return true
            }
    }

    /// Get a session summary (decrypted) for the given session.
    public static func getSessionSummary(_ sessionId: String) throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        return cr.getSessionSummary(sessionId)
    }

    /// Mark a stranded active session as closed without replaying the normal
    /// stop-session lifecycle. The native operation is idempotent.
    @discardableResult
    public static func closeOrphanSession(_ sessionId: String) throws -> Bool {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        return cr.closeOrphanSession(sessionId)
    }

    /// Close active catalog sessions older than the supplied interval. Call at
    /// app startup to repair sessions stranded by process termination.
    @discardableResult
    public static func sweepOrphanSessions(
        olderThan: TimeInterval = 6 * 60 * 60,
        now: Date = Date()
    ) throws -> Int {
        guard olderThan >= 0 else {
            throw SynheartError.invalidArgument("Orphan-session age must be non-negative")
        }
        let cutoffMs = Int64((now.timeIntervalSince1970 - olderThan) * 1_000)
        let orphans = try listSessions().filter {
            $0.isActive && $0.startUtc > 0 && $0.startUtc < cutoffMs
        }
        return try orphans.reduce(into: 0) { closed, session in
            if try closeOrphanSession(session.sessionId) {
                closed += 1
            }
        }
    }

    // MARK: - Research Studies

    /// Enrol the device in a research study by redeeming an access + study code.
    /// Enrolment rides the device's signed cloud credential — no tokens are
    /// handled by the caller. Returns the service response (enrolment on success,
    /// or an `error` key), or nil if the runtime is unavailable.
    public static func enrolResearchStudy(accessCode: String, studyCode: String) async throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return nil }
        return await RuntimeWorkExecutor.run {
            cr.enrolResearchStudy(accessCode: accessCode, studyCode: studyCode)
        }
    }

    /// Preview an access + study code pair without redeeming the code.
    public static func validateResearchStudyCodes(accessCode: String, studyCode: String) async throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return nil }
        return await RuntimeWorkExecutor.run {
            cr.validateResearchStudyCodes(accessCode: accessCode, studyCode: studyCode)
        }
    }

    /// Withdraw from the device's active research study for this app. No codes —
    /// the participant + app come from the device's signed credential. Idempotent.
    public static func withdrawResearchStudy() async throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return nil }
        return await RuntimeWorkExecutor.run { cr.withdrawResearchStudy() }
    }

    /// Request erasure of the data the participant contributed to their study for
    /// this app — the deletion the consent copy promises alongside withdrawal. No
    /// identifiers are passed; the participant + app come from the device's signed
    /// credential. When `dryRun` is true the response is an inventory preview and
    /// nothing is deleted; a real request is accepted asynchronously and carries a
    /// `request_id`. Idempotent. Returns nil if the runtime is unavailable.
    public static func requestStudyDataDeletion(dryRun: Bool = false) async throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return nil }
        return await RuntimeWorkExecutor.run {
            cr.requestStudyDataDeletion(dryRun: dryRun)
        }
    }

    /// Get decrypted HSI window artifacts for a session.
    public static func getHSIWindows(_ sessionId: String, range: WindowRange? = nil) throws -> [[String: Any]] {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        return cr.getHSIWindows(sessionId, range: range)
    }

    // MARK: - Storage & Retention

    /// Get storage usage statistics.
    public static func getStorageUsage() throws -> StorageUsage {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        return cr.getStorageUsage()
    }

    /// Set retention policy. Nil leaves the existing native policy unchanged.
    public static func setRetentionDays(_ days: Int?) throws {
        guard let days else { return }
        guard days >= 0, days <= Int(Int32.max) else {
            throw SynheartError.invalidArgument("Retention days must be between 0 and \(Int32.max)")
        }
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        guard cr.setRetentionDays(days) >= 0 else {
            throw SynheartError.runtimeOperationFailed("Unable to apply retention policy")
        }
    }

    // MARK: - Deletion API

    /// Delete a session and all its artifacts locally.
    public static func deleteLocalSession(_ sessionId: String) throws {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        guard cr.deleteSession(sessionId) else {
            throw SynheartError.runtimeOperationFailed("Unable to delete local session \(sessionId)")
        }
    }

    /// Wipe all local data.
    public static func wipeLocalData() async throws {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        if shared.isRunning {
            try await shared._stopSession()
        }
        let wiped = await RuntimeWorkExecutor.run { cr.wipeLocalData() }
        guard wiped else {
            throw SynheartError.runtimeOperationFailed("Unable to wipe local data")
        }
        shared._currentSessionHandle = nil
        shared.isRunning = false
        shared.collectionModuleFailures = [:]
        shared.resetUploadDiagnostics()
        shared.hsiSubject.send(nil)
        shared.typedHsiSubject.send(nil)
    }

    /// Request account deletion -- requests server-side deletion (device-signed
    /// by the runtime) and wipes local data.
    public static func requestAccountDeletion() async throws -> DeletionRequestResult {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        let serverAccepted = await RuntimeWorkExecutor.run {
            cr.requestAccountDeletion().status == "accepted"
        }
        let localWiped: Bool
        do {
            try await wipeLocalData()
            localWiped = true
        } catch {
            SynheartLogger.log("[Synheart] Account deletion local wipe failed: \(error)")
            localWiped = false
        }
        return DeletionOutcome.accountResult(
            serverAccepted: serverAccepted,
            localWiped: localWiped
        )
    }

    /// Cancel a pending account deletion request (device-signed by the runtime).
    public static func cancelAccountDeletion() async throws -> DeletionRequestResult {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            return DeletionRequestResult(status: "error", message: "Runtime unavailable; cannot cancel deletion.")
        }
        if await RuntimeWorkExecutor.run({ cr.cancelAccountDeletion() }) {
            return DeletionRequestResult(
                status: "cancelled",
                message: "Account deletion cancelled."
            )
        }
        return DeletionRequestResult(status: "error", message: "Cancel request failed.")
    }

    /// Log out by revoking native consent, clearing the persisted native token,
    /// and only then updating the Swift consent snapshot.
    public static func logout() async throws {
        try await shared._logout()
    }

    private func _logout() async throws {
        guard let consentModule, let coreRuntime, coreRuntime.isAvailable else {
            throw SynheartError.notInitialized
        }

        let current = consentModule.current()
        let nativeRevoked = current.copyWith(
            biosignals: false,
            behavior: false,
            phoneContext: false,
            cloudUpload: false,
            syni: false,
            focusEstimation: false,
            emotionEstimation: false,
            vendorSync: false
        )
        if let error = await RuntimeWorkExecutor.run({
            ConsentRuntimeCoordinator.apply(nativeRevoked, replacing: current, through: coreRuntime)
        }) {
            throw error
        }
        guard await RuntimeWorkExecutor.run({ coreRuntime.clearStoredConsent() }) else {
            _ = await RuntimeWorkExecutor.run {
                ConsentRuntimeCoordinator.apply(current, replacing: nativeRevoked, through: coreRuntime)
            }
            throw SynheartError.runtimeOperationFailed("Native consent token cleanup failed")
        }

        try await consentModule.updateConsent(.none())
        currentTokenSubject = nil
    }

    // MARK: - Sync API

    /// Enable or disable sync.
    public static func setSyncEnabled(_ enabled: Bool) async throws {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        let status = await RuntimeWorkExecutor.run {
            cr.setSyncEnabled(enabled)
            return cr.syncStatus()
        }
        guard let status else {
            throw SynheartError.runtimeOperationFailed("Unable to read sync status")
        }
        guard status.enabled == enabled else {
            throw SynheartError.runtimeOperationFailed(
                enabled ? "Native sync prerequisites are not satisfied" : "Unable to disable native sync"
            )
        }
    }

    /// Execute a sync cycle (push + pull).
    public static func syncNow() async throws -> SyncResult {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        let result = await RuntimeWorkExecutor.run { cr.syncNow() }
        guard let result else {
            throw SynheartError.runtimeOperationFailed("Native sync cycle failed")
        }
        return result
    }

    /// Get current sync status.
    public static func getSyncStatus() throws -> SyncStatus {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        guard let status = cr.syncStatus() else {
            throw SynheartError.runtimeOperationFailed("Unable to read sync status")
        }
        return status
    }

    // MARK: - Cloud Ingestion & Device Auth

    /// Observable outbound HSI queue state. The native runtime automatically
    /// enqueues closed HSI windows; hosts should not enqueue every callback again.
    public static var uploadQueueStatus: UploadQueueStatus {
        shared._uploadQueueStatus()
    }

    public static var uploadQueueLength: Int {
        shared.coreRuntime?.uploadQueueLength ?? 0
    }

    private func _uploadQueueStatus() -> UploadQueueStatus {
        guard let runtime = coreRuntime, runtime.isAvailable else {
            return UploadQueueStatus(
                state: .localOnly,
                queueLength: 0,
                lastUploadBatchId: lastUploadBatchId,
                lastUploadAt: lastUploadAt,
                lastUploadAttemptAt: lastUploadAttemptAt,
                lastFailure: lastUploadFailure
            )
        }
        let queueLength = runtime.uploadQueueLength
        let nativeSuccess = runtime.bridge?.lastIngestSuccessAtMs().map {
            Date(timeIntervalSince1970: TimeInterval($0) / 1_000)
        }
        let resolvedLastUpload = nativeSuccess ?? lastUploadAt
        let cloudChosen = _effectiveConsent()?.cloudUpload == true
        let cloudEnforceable = runtime.hasConsent(ConsentType.cloudUpload.rawValue)
        let state: CloudSyncState
        if !cloudChosen {
            state = .localOnly
        } else if !cloudEnforceable {
            state = .blocked
        } else if queueLength > 0 {
            state = .syncing
        } else if resolvedLastUpload != nil {
            state = .synced
        } else {
            state = .pending
        }
        return UploadQueueStatus(
            state: state,
            queueLength: queueLength,
            lastUploadBatchId: lastUploadBatchId,
            lastUploadAt: resolvedLastUpload,
            lastUploadAttemptAt: lastUploadAttemptAt,
            lastFailure: lastUploadFailure
        )
    }

    /// Force the native runtime to flush its automatically-managed HSI queue.
    @discardableResult
    public static func flushUploads(requireConsent: Bool = true) async -> UploadFlushResult {
        await shared._flushUploads(requireConsent: requireConsent)
    }

    private func _flushUploads(requireConsent: Bool) async -> UploadFlushResult {
        lastUploadAttemptAt = Date()
        guard let runtime = coreRuntime, runtime.isAvailable else {
            return recordUploadFailure(.init(
                reason: .misconfigured,
                message: "Core runtime bridge is unavailable"
            ))
        }
        if requireConsent && !runtime.hasConsent(ConsentType.cloudUpload.rawValue) {
            let locallyChosen = _effectiveConsent()?.cloudUpload == true
            return recordUploadFailure(.init(
                reason: .policy,
                message: locallyChosen
                    ? "Cloud upload is selected, but the runtime gate is closed. Check device registration and consent-token issuance."
                    : "Cloud upload consent is not granted"
            ))
        }
        guard let map = await RuntimeWorkExecutor.run({ runtime.flushUploads() }) else {
            return recordUploadFailure(.init(
                reason: .unknown,
                message: "Native upload flush returned no result"
            ))
        }
        let result = UploadFlushResult(runtimeMap: map)
        if let failure = result.failure {
            lastUploadFailure = failure
            return result
        }
        lastUploadFailure = nil
        if result.uploaded > 0 {
            let now = Date()
            lastUploadAt = now
            lastUploadBatchId = result.batchId
                ?? "flush_\(Int64(now.timeIntervalSince1970 * 1_000))"
        }
        return result
    }

    private func recordUploadFailure(_ failure: NativeOperationFailure) -> UploadFlushResult {
        lastUploadFailure = failure
        return UploadFlushResult(success: false, failure: failure)
    }

    private func resetUploadDiagnostics() {
        lastUploadBatchId = nil
        lastUploadAt = nil
        lastUploadAttemptAt = nil
        lastUploadFailure = nil
    }

    /// Native device-auth status, including the separate attestation provenance
    /// claim (`attested`, `unattested`, or `unknown`).
    public static var deviceAuthAvailable: Bool {
        let required = Set([
            "synheart_core_sdk_set_crypto_callbacks",
            "synheart_core_set_storage_callbacks",
            "synheart_core_sdk_register_device",
            "synheart_core_sdk_device_auth_status",
        ])
        return required.isDisjoint(with: CoreRuntimeBridge.symbolDiagnostics.missingOptionalSymbols)
    }

    public static var deviceAuthStatus: DeviceAuthStatus? {
        guard let json = shared.coreRuntime?.bridge?.deviceAuthStatus(),
              let map = shared.parseDict(json) else { return nil }
        return DeviceAuthStatus(runtimeMap: map)
    }

    /// Idempotently register the configured device through the native runtime.
    @discardableResult
    public static func ensureDeviceAuthRegistered() async -> DeviceRegistrationResult {
        await shared._ensureDeviceAuthRegistered()
    }

    private func _ensureDeviceAuthRegistered() async -> DeviceRegistrationResult {
        guard _synheartConfig?.deviceAuthConfig != nil,
              let bridge = coreRuntime?.bridge else {
            let failure = NativeOperationFailure(
                reason: .misconfigured,
                message: "DeviceAuthConfig is required before registering a device"
            )
            return DeviceRegistrationResult(
                success: false,
                status: DeviceAuthStatus(status: "not_configured"),
                failure: failure
            )
        }
        if let existing = Self.deviceAuthStatus, existing.isRegistered {
            return DeviceRegistrationResult(success: true, status: existing)
        }
        guard let clientId = subjectId, !clientId.isEmpty,
              let json = await RuntimeWorkExecutor.run({ bridge.registerDevice(clientId: clientId) }),
              let map = parseDict(json) else {
            let failure = NativeOperationFailure(
                reason: .unknown,
                message: "Native device registration returned no result"
            )
            return DeviceRegistrationResult(
                success: false,
                status: DeviceAuthStatus(status: "failed"),
                failure: failure
            )
        }
        if let failure = NativeOperationFailure.fromRuntimeMap(map, fallback: "Device registration failed") {
            return DeviceRegistrationResult(
                success: false,
                status: DeviceAuthStatus(runtimeMap: map),
                failure: failure
            )
        }
        let status = Self.deviceAuthStatus
            ?? DeviceAuthStatus(
                status: "registered",
                deviceId: map["device_id"] as? String,
                attestation: map["attestation"] as? String ?? "unknown"
            )
        if status.isRegistered {
            _ = await _ensureCloudConsentReady()
        }
        return DeviceRegistrationResult(success: status.isRegistered, status: status)
    }

    // MARK: - Activation API

    /// Activate a feature. If all four authorities are satisfied
    /// (activation, consent, capability, session), the feature's module starts.
    public static func activate(_ feature: SynheartFeature) {
        shared._activationManager?.activate(feature)
        shared._reevaluateFeature(feature)
    }

    /// Deactivate a feature. Stops the feature's module if running.
    public static func deactivate(_ feature: SynheartFeature) {
        shared._activationManager?.deactivate(feature)
        shared._reevaluateFeature(feature)
    }

    /// Check whether a feature is currently activated by the developer.
    public static func isActivated(_ feature: SynheartFeature) -> Bool {
        shared._activationManager?.isActivated(feature) ?? false
    }

    /// Return the set of all currently activated features.
    public static func activatedFeatures() -> Set<SynheartFeature> {
        shared._activationManager?.activatedFeatures() ?? []
    }

    // MARK: - Initialization

    /**
     * Initialize Synheart Core SDK.
     *
     * Must be called before any other operations. Repeated calls after a
     * successful initialization are safe no-ops.
     *
     * Example:
     * ```swift
     * try await Synheart.initialize(config: SynheartConfig(
     *     appId: "com.example.app",
     *     subjectId: "anon_user_123",
     *     allowUnsignedCapabilities: true
     * ))
     * ```
     */
    public static func initialize(
        config: SynheartConfig? = nil,
        userId: String? = nil,
        autoStart: Bool = false
    ) async throws {
        if let config = config {
            try config.validate()
        }
        let resolvedUserId = userId ?? config?.subjectId ?? ""
        let appKey = config?.appId ?? "default"
        try await shared.initializationGate.run {
            try await shared._initialize(
                userId: resolvedUserId,
                config: config,
                appKey: appKey
            )
        }
        if autoStart {
            try await shared._startSession()
        }
    }

    private func _initialize(
        userId: String,
        config: SynheartConfig?,
        appKey: String
    ) async throws {
        guard !isConfigured else { return }

        do {
            try await _performInitialization(
                userId: userId,
                config: config,
                appKey: appKey
            )
        } catch {
            await _resetAfterInitializationFailure()
            throw error
        }
    }

    private func _performInitialization(
        userId: String,
        config: SynheartConfig?,
        appKey: String
    ) async throws {

        self.userId = userId
        let resolvedConfig = config ?? SynheartConfig()

        SynheartLogger.log("[Synheart] Initializing...")

        // Create the native runtime before accepting any legacy capability
        // token so signature verification can never be silently skipped.
        let dataDirectory = try RuntimeDataDirectory.prepare()
        self.coreRuntime = try SynheartCoreShim(
            config: resolvedConfig,
            dataDir: dataDirectory
        )
        let endpoints = ServiceEndpointResolver.resolve(resolvedConfig)

        if resolvedConfig.deviceAuthConfig != nil {
            SynheartAuth.shared.configure(baseUrl: endpoints.authBaseURL)
        }

        // Native consent persistence depends on host storage/crypto callbacks.
        // Install them before reading the authoritative consent snapshot.
        if let bridge = coreRuntime?.bridge {
            let storageRc = bridge.setStorageCallbacks()
            if storageRc != 0 {
                SynheartLogger.log("[Synheart] set_storage_callbacks rc=\(storageRc); state will not persist")
            }
            let cryptoRc = bridge.setSdkCryptoCallbacks()
            if cryptoRc != 0 {
                SynheartLogger.log("[Synheart] set_crypto_callbacks rc=\(cryptoRc); device auth unavailable")
            }
            if resolvedConfig.consentConfig != nil || resolvedConfig.cloudConfig != nil {
                _ = bridge.consentConfigureCloud(
                    baseUrl: endpoints.consentBaseURL,
                    appId: resolvedConfig.appId
                )
            }
        }

        capabilityModule = CapabilityModule(bridge: coreRuntime?.bridge)
        if resolvedConfig.deviceAuthConfig != nil {
            // Device-auth registrations and verified consent tokens are owned by
            // the native runtime. Defaults are provisional SDK-side gates until
            // that runtime authority is established.
            capabilityModule!.loadDefaults()
        } else if let token = resolvedConfig.legacyCapabilityToken,
           let secret = resolvedConfig.legacyCapabilitySecret {
            try capabilityModule!.loadVerifiedToken(token, secret: secret)
        } else if resolvedConfig.allowUnsignedCapabilities {
            SynheartLogger.log("[Synheart] WARNING: Running with unsigned default capabilities. Do not use in production.")
            capabilityModule!.loadDefaults()
        } else {
            throw SynheartError.capabilityTokenRequired
        }

        consentModule = ConsentModule(bridge: coreRuntime?.bridge)

        let capturedAppId = resolvedConfig.appId
        consentModule!.setDeviceSigner { method, path, bodyData in
            do {
                return try SynheartAuth.shared.signRequest(
                    appId: capturedAppId,
                    method: method,
                    path: path,
                    bodyBytes: bodyData
                ).dictionary
            } catch {
                SynheartLogger.log("[Synheart] Device signing unavailable for consent: \(error)")
                return [:]
            }
        }

        try moduleManager.registerModule(capabilityModule!)
        try moduleManager.registerModule(consentModule!)

        wearModule = WearModule(
            capabilities: capabilityModule!,
            consent: consentModule!
        )
        phoneModule = PhoneModule(
            capabilities: capabilityModule!,
            consent: consentModule!,
            runtimeSink: coreRuntime
        )
        behaviorModule = BehaviorModule(
            capabilities: capabilityModule!,
            consent: consentModule!,
            runtimeSink: coreRuntime,
            sessionIdProvider: { [weak self] in self?._currentSessionHandle?.sessionId }
        )

        try moduleManager.registerModule(wearModule!, dependsOn: ["capabilities", "consent"])
        try moduleManager.registerModule(phoneModule!, dependsOn: ["capabilities", "consent"])
        try moduleManager.registerModule(behaviorModule!, dependsOn: ["capabilities", "consent"])

        try await moduleManager.initializeAll()

        if let restored = await RuntimeWorkExecutor.run({
            ConsentRuntimeCoordinator.restore(from: self.coreRuntime!)
        }) {
            try await consentModule!.updateConsent(restored)
        }

        // The editable/current snapshot represents what was requested. Modules
        // and sessions consume the runtime's policy-intersected effective state.
        if let effective = _effectiveConsent() {
            try await consentModule!.updateConsent(effective.snapshot)
        }

        previousConsent = consentModule!.current()
        consentModule!.addListener { [weak self] newConsent in
            self?.handleConsentChange(newConsent)
        }

        let biosignalAdapter = WearModuleBiosignalAdapter(
            rawSamplePublisher: wearModule?.rawSamplePublisher ?? Empty<WearSample, Never>().eraseToAnyPublisher()
        )
        let behaviorAdapter: BehaviorModuleAdapter? = behaviorModule.map { BehaviorModuleAdapter(behaviorModule: $0) }
        sessionModule = SessionModule(
            biosignalProvider: biosignalAdapter,
            behaviorProvider: behaviorAdapter
        )

        hsiToSessionCancellable = hsiSubject
            .compactMap { $0 }
            .sink { [weak self] hsiJson in
                guard let self = self, self.sessionModule?.isActive == true else { return }
                if let data = hsiJson.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.sessionModule?.ingestHsiMetrics(parsed)
                }
            }

        _activationManager = ActivationManager()
        _activationManager!.activateFromConfig(resolvedConfig)

        _synheartConfig = resolvedConfig

        if let cr = coreRuntime, let bridge = cr.bridge {
            SynheartLogger.log("[Synheart] Core runtime bridge loaded")

            // Capture the canonical subject the runtime resolved (a device-auth
            // derive may have changed it) so SDK subject checks match native.
            syncSubjectFromNative()

            bridge.setHsiCallback { [weak self] json in
                guard let self = self else { return }
                guard let consent = self._effectiveConsent(),
                      consent.biosignals || consent.behavior || consent.phoneContext else { return }
                guard self.hsiDeliveryDeduplicator.shouldDeliver(json: json) else { return }
                let typed = HSIState.fromJson(json, subjectId: self.subjectId ?? "")
                self.typedHsiSubject.send(typed)
                self.hsiSubject.send(json)
            }

            // Self-heal: if cloud upload is already in the effective state (e.g. a
            // persisted grant), re-ensure a token for the current subject. Best-effort.
            if let effJson = bridge.consentEffectiveState(),
               let eff = parseDict(effJson),
               (eff["cloud_upload"] as? Bool) == true {
                _ = await _ensureCloudConsentReady()
            }
        }

        isConfigured = true

        SynheartLogger.log("[Synheart] Initialization complete. Call startSession() to begin.")
    }

    /// Clears every partially-created component so a failed initialization can
    /// be retried without duplicate module registrations or stale callbacks.
    private func _resetAfterInitializationFailure() async {
        await moduleManager.disposeAll()

        sessionModule?.dispose()
        sessionModule = nil
        sessionSubscription?.cancel()
        sessionSubscription = nil
        hsiToSessionCancellable?.cancel()
        hsiToSessionCancellable = nil
        cancellables.removeAll()

        coreRuntime?.bridge?.clearHsiCallback()
        coreRuntime = nil

        capabilityModule = nil
        consentModule = nil
        wearModule = nil
        phoneModule = nil
        behaviorModule = nil
        _activationManager = nil
        previousConsent = nil
        _synheartConfig = nil
        nativeSubjectIdOverride = nil
        currentTokenSubject = nil
        userId = nil
        hsiDeliveryDeduplicator.reset()
        hsiSubject.send(nil)
        typedHsiSubject.send(nil)
        isConfigured = false
        isRunning = false
        collectionModuleFailures = [:]
        resetUploadDiagnostics()
    }

    // MARK: - Session Lifecycle

    /**
     * Start a session -- activates permitted modules and begins signal collection.
     *
     * Must be called after initialize(). No data collection occurs until
     * this method is called.
     */
    public static func startSession() async throws {
        try await shared._startSession()
    }

    private func _startSession() async throws {
        guard isConfigured else {
            throw SynheartError.notInitialized
        }
        guard !isRunning else { return }
        guard let consent = _effectiveConsent() else {
            throw SynheartError.runtimeOperationFailed(
                "Native runtime did not provide an effective consent state"
            )
        }
        let collectionFeatures = SessionStartPolicy.operationalCollectionFeatures(
            consent: consent,
            activated: _activationManager?.activatedFeatures() ?? [],
            capabilityAllowed: { [weak self] feature in
                self?._isCapabilityAllowed(feature) ?? false
            }
        )
        guard !collectionFeatures.isEmpty else {
            throw SynheartError.consentRequired(
                "Activate at least one capable collection feature and grant its matching consent before starting a session"
            )
        }
        guard let cr = coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }

        SynheartLogger.log("[Synheart] Starting session...")
        collectionModuleFailures = [:]
        hsiDeliveryDeduplicator.reset()
        hsiSubject.send(nil)
        typedHsiSubject.send(nil)

        guard let nativeHandle = cr.startSession() else {
            throw SynheartError.runtimeOperationFailed("Native session creation failed")
        }
        _currentSessionHandle = nativeHandle

        let sessionId = nativeHandle.sessionId
        let durationSec = 86400

        let config = SessionConfig(
            sessionId: sessionId,
            mode: .focus,
            durationSec: durationSec
        )

        do {
            if let module = sessionModule {
                let stream = module.startSession(config: config)
                sessionSubscription = stream
                    .sink(
                        receiveCompletion: { [weak self] _ in
                            guard let self = self else { return }
                            if self.isRunning {
                                Task { try? await self._stopSession() }
                                SynheartLogger.log("[Synheart] Main session ended (duration or stream closed)")
                            }
                        },
                        receiveValue: { _ in }
                    )
            }

            let requestedModuleIds = Set(collectionFeatures.map(moduleId))
            let report = try await moduleManager.startModulesResiliently(requestedModuleIds)
            collectionModuleFailures = report.failures.filter { requestedModuleIds.contains($0.key) }
            let runningCollectors = report.runningModuleIds.intersection(requestedModuleIds)
            guard !runningCollectors.isEmpty else {
                let detail = collectionModuleFailures
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: "; ")
                throw SynheartError.runtimeOperationFailed(
                    detail.isEmpty
                        ? "No requested collection module became operational"
                        : "No requested collection module became operational (\(detail))"
                )
            }
            isRunning = true
            if !collectionModuleFailures.isEmpty {
                SynheartLogger.log("[Synheart] Session started with degraded collectors: \(collectionModuleFailures)")
            }
            SynheartLogger.log("[Synheart] Session started")
        } catch {
            if let activeId = sessionModule?.currentSessionId {
                sessionModule?.stopSession(sessionId: activeId)
            }
            sessionSubscription?.cancel()
            sessionSubscription = nil
            await moduleManager.stopAll()
            _ = cr.stopSession()
            _currentSessionHandle = nil
            isRunning = false
            collectionModuleFailures = [:]
            _reevaluateAllFeatures()
            throw error
        }
    }

    /**
     * Stop the current session -- halts module streaming and clears ephemeral buffers.
     *
     * Modules remain initialized and can be restarted with startSession().
     */
    public static func stopSession() async throws {
        try await shared._stopSession()
    }

    private func _stopSession() async throws {
        guard isRunning else { return }

        SynheartLogger.log("[Synheart] Stopping session...")

        if let cr = coreRuntime, cr.isAvailable {
            let resolution = await RuntimeWorkExecutor.run {
                SessionStopCoordinator.stop(cr)
            }
            if !resolution.mayClearLocalState {
                _currentSessionHandle = resolution.activeSession ?? _currentSessionHandle
                isRunning = true
                throw SynheartError.runtimeOperationFailed("Native session stop failed")
            }
        }
        isRunning = false
        collectionModuleFailures = [:]

        if let activeId = sessionModule?.currentSessionId {
            sessionModule?.stopSession(sessionId: activeId)
        }
        sessionSubscription?.cancel()
        sessionSubscription = nil

        if let piConfig = _synheartConfig?.labIngestConfig, piConfig.autoIngest, let handle = _currentSessionHandle {
            await _autoIngestSession(handle)
        }

        _currentSessionHandle = nil

        _reevaluateAllFeatures()
        await moduleManager.stopAll()
        SynheartLogger.log("[Synheart] Session stopped")
    }

    private func _autoIngestSession(_: SessionHandle) async {
        _ = await _flushUploads(requireConsent: true)
    }

    // MARK: - Session Module Access

    /// Stream of typed session events from the active session.
    public static var onSessionEvent: AnyPublisher<SessionEvent, Never> {
        shared.sessionModule?.events ?? Empty<SessionEvent, Never>().eraseToAnyPublisher()
    }

    /// Get the status of the current session from the session engine.
    public static func getSessionStatus() -> [String: Any]? {
        shared.sessionModule?.getStatus()
    }

    // MARK: - Consent API

    /// Check if user has granted a specific consent.
    ///
    /// - Parameter consentType: One of `"biosignals"`, `"behavior"`,
    ///   `"phoneContext"`, `"cloudUpload"`. Unknown values return `false`.
    public static func hasConsent(_ consentType: String) async -> Bool {
        await shared._hasConsent(consentType)
    }

    private func _hasConsent(_ consentType: String) async -> Bool {
        guard let type = nativeConsentType(for: consentType),
              let runtime = coreRuntime,
              runtime.isAvailable else { return false }
        return runtime.hasConsent(type.rawValue)
    }

    /// Grant consent for a specific data type.
    ///
    /// - Parameter consentType: One of `"biosignals"`, `"behavior"`,
    ///   `"phoneContext"`, `"cloudUpload"`, `"syni"`. Unknown values are
    ///   silently ignored.
    /// - Throws: `SynheartError.notInitialized` if the consent module
    ///   hasn't been initialized.
    public static func grantConsent(_ consentType: String) async throws {
        try await shared._grantConsent(consentType)
    }

    private func _grantConsent(_ consentType: String) async throws {
        guard let consentModule = consentModule else {
            throw SynheartError.notInitialized
        }
        guard nativeConsentType(for: consentType) != nil else { return }
        guard let coreRuntime, coreRuntime.isAvailable else {
            throw SynheartError.notInitialized
        }

        let current = consentModule.current()
        let updated: ConsentSnapshot

        switch consentType {
        case "biosignals":  updated = current.copyWith(biosignals: true)
        case "behavior":    updated = current.copyWith(behavior: true)
        case "phoneContext": updated = current.copyWith(phoneContext: true)
        case "cloudUpload": updated = current.copyWith(cloudUpload: true)
        case "syni":        updated = current.copyWith(syni: true)
        default:            updated = current
        }

        if let error = await RuntimeWorkExecutor.run({
            ConsentRuntimeCoordinator.apply(updated, replacing: current, through: coreRuntime)
        }) {
            throw error
        }
        try await _refreshEffectiveConsent()

        // Granting cloud upload should immediately mint a consent token for the
        // current subject so pending data can flush. Best-effort.
        if consentType == "cloudUpload" {
            _ = await _ensureCloudConsentReady()
            try await _refreshEffectiveConsent()
        }
    }

    /// Revoke consent for a specific data type. Any modules gated on this
    /// consent are stopped and queued data discarded per retention policy.
    ///
    /// - Parameter consentType: One of `"biosignals"`, `"behavior"`,
    ///   `"phoneContext"`, `"cloudUpload"`, `"syni"`. Unknown values are
    ///   silently ignored.
    /// - Throws: `SynheartError.notInitialized` if the consent module
    ///   hasn't been initialized.
    public static func revokeConsent(_ consentType: String) async throws {
        try await shared._revokeConsent(consentType)
    }

    private func _revokeConsent(_ consentType: String) async throws {
        guard let consentModule = consentModule else {
            throw SynheartError.notInitialized
        }
        guard nativeConsentType(for: consentType) != nil else { return }
        guard let coreRuntime, coreRuntime.isAvailable else {
            throw SynheartError.notInitialized
        }

        let current = consentModule.current()
        let updated: ConsentSnapshot

        switch consentType {
        case "biosignals":  updated = current.copyWith(biosignals: false)
        case "behavior":    updated = current.copyWith(behavior: false)
        case "phoneContext": updated = current.copyWith(phoneContext: false)
        case "cloudUpload": updated = current.copyWith(cloudUpload: false)
        case "syni":        updated = current.copyWith(syni: false)
        default:            updated = current
        }

        if let error = await RuntimeWorkExecutor.run({
            ConsentRuntimeCoordinator.apply(updated, replacing: current, through: coreRuntime)
        }) {
            throw error
        }
        try await _refreshEffectiveConsent()
    }

    private func nativeConsentType(for publicName: String) -> ConsentType? {
        switch publicName {
        case "biosignals": return .biosignals
        case "behavior": return .behavior
        case "phoneContext": return .phoneContext
        case "cloudUpload": return .cloudUpload
        case "syni": return .syni
        default: return nil
        }
    }

    // MARK: - Cloud Consent Token

    /// The subject id this SDK instance is configured for — the value uploads
    /// are attributed under and the consent token is minted for. Nil when not
    /// configured.
    public static var subjectId: String? { shared.subjectId }

    /// Ensure a cloud consent token exists for the current subject so pending
    /// data can upload. Short-circuits when a valid, subject-matched token is
    /// already granted; otherwise reissues it by submitting the current consent
    /// form with cloud upload enabled. Returns true when a usable token is in
    /// place. Safe to call repeatedly; never throws.
    @discardableResult
    public static func ensureCloudConsentReady() async -> Bool {
        await shared._ensureCloudConsentReady()
    }

    private func _ensureCloudConsentReady() async -> Bool {
        guard let bridge = coreRuntime?.bridge else { return false }

        // Cloud upload must be requested in the effective (token-authoritative)
        // state before there is anything to mint a token for.
        guard let effJson = bridge.consentEffectiveState(),
              let eff = parseDict(effJson),
              (eff["cloud_upload"] as? Bool) == true else {
            return false
        }

        // Short-circuit when a usable, subject-matched token is already in place.
        let status = bridge.consentStatus().flatMap { parseDict($0)?["status"] as? String }
        let needsRefresh = bridge.consentNeedsTokenRefresh()
        if CloudConsentLogic.isReadyWithoutReissue(
            status: status,
            needsRefresh: needsRefresh,
            subjectStale: consentTokenSubjectStale()
        ) {
            return true
        }

        let subject = subjectId

        // The runtime can only mint once the device is registered (device-signed).
        // Register on first use; idempotent — skip when already registered.
        let authStatus = bridge.deviceAuthStatus().flatMap { parseDict($0)?["status"] as? String }
        if authStatus != "registered", let clientId = subject, !clientId.isEmpty {
            let reg = bridge.registerDevice(clientId: clientId).flatMap { parseDict($0) }
            let deviceId = reg?["device_id"] as? String
            if reg?["error"] is String || deviceId == nil {
                SynheartLogger.log("[Synheart] device registration failed: \(reg?["error"] as? String ?? "no device_id")")
                return false
            }
        }

        // Reissue: fetch the editable form, opt into cloud upload, resubmit.
        guard let formJson = bridge.consentEditableForm(),
              var form = parseDict(formJson) else { return false }
        form["allow_cloud"] = true
        guard let formData = try? JSONSerialization.data(withJSONObject: form),
              let formStr = String(data: formData, encoding: .utf8) else { return false }

        guard let resultJson = bridge.consentSubmitForm(
            deviceId: _synheartConfig?.deviceId,
            platform: "ios",
            userId: subject,
            formJson: formStr
        ), let result = parseDict(resultJson) else { return false }

        if let err = result["error"] as? String {
            SynheartLogger.log("[Synheart] cloud consent submit failed: \(err)")
            return false
        }
        let synced = (result["synced"] as? Bool) ?? false
        let hasToken = result["token"] is [String: Any]
        guard CloudConsentLogic.submitIssuedToken(synced: synced, hasToken: hasToken) else {
            SynheartLogger.log("[Synheart] cloud consent not synced; token not issued")
            return false
        }
        // The token is minted under the `user_id` we submitted, so its subject
        // is `subject`. Record it to detect staleness after a future re-key.
        currentTokenSubject = subject

        let newStatus = bridge.consentStatus().flatMap { parseDict($0)?["status"] as? String }
        return newStatus?.lowercased() == "granted"
    }

    /// True when the issued cloud consent token was minted for a DIFFERENT
    /// subject than the current one (e.g. after an account re-key). Conservative:
    /// false when there's no token or the subject is unknown.
    public static func consentTokenSubjectStale() -> Bool {
        shared.consentTokenSubjectStale()
    }

    func consentTokenSubjectStale() -> Bool {
        CloudConsentLogic.isTokenSubjectStale(tokenUserId: currentTokenSubject, currentSubject: subjectId)
    }

    /// Rebind the runtime subject id when the signed-in identity changes, then
    /// re-mint cloud consent for the new subject if needed — without a full
    /// dispose/reinit. Prefer this over re-initializing the SDK on sign-in.
    ///
    /// The native runtime atomically re-points consent (`cached_subject_id` +
    /// token slot) and the cloud connector; this syncs the SDK subject and runs
    /// the self-heal so a stale token is reissued before the next upload. Returns
    /// true when the rebind was applied (false on a runtime that lacks the symbol).
    @discardableResult
    public static func rebindSubjectId(_ subjectId: String) async -> Bool {
        await shared._rebindSubjectId(subjectId)
    }

    private func _rebindSubjectId(_ subjectId: String) async -> Bool {
        guard let bridge = coreRuntime?.bridge else { return false }
        let trimmed = subjectId.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let rc = bridge.rebindSubjectId(trimmed)
        if rc < 0 {
            SynheartLogger.log("[Synheart] rebindSubjectId failed (rc=\(rc))")
            return false
        }
        // Keep the SDK subject in lockstep with the native runtime.
        syncSubjectFromNative()
        // rc == 1 => re-mint required; rc == 0 => valid token already loaded.
        // Self-heal regardless: cheap no-op when ready, reissues otherwise.
        _ = await _ensureCloudConsentReady()
        return true
    }

    /// Get current HSI state (latest JSON frame).
    public static var currentState: String? {
        shared.hsiSubject.value
    }

    /// Get current consent snapshot.
    public static var currentConsent: ConsentSnapshot? {
        shared.consentModule?.current()
    }

    /// Runtime-owned editable consent form. Hosts should edit this value and
    /// submit it with ``submitConsentForm(_:deviceId:platform:userId:)``.
    public static var editableConsentForm: ConsentForm? {
        guard let json = shared.coreRuntime?.bridge?.consentEditableForm(),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ConsentForm.self, from: data)
    }

    /// Consent state currently enforced by the native runtime after local
    /// choices, app policy, and any cloud token are reconciled.
    public static var effectiveConsent: ConsentEffectiveState? {
        shared._effectiveConsent()
    }

    private func _effectiveConsent() -> ConsentEffectiveState? {
        guard let json = coreRuntime?.bridge?.consentEffectiveState(),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ConsentEffectiveState.self, from: data)
    }

    private func _refreshEffectiveConsent() async throws {
        guard let consentModule else { throw SynheartError.notInitialized }
        guard let effective = _effectiveConsent() else {
            try await consentModule.updateConsent(.none())
            throw SynheartError.runtimeOperationFailed(
                "Native runtime did not provide an effective consent state"
            )
        }
        try await consentModule.updateConsent(effective.snapshot)
    }

    /// Submit a category-level consent form using the native runtime's
    /// offline-first flow, then refresh the Swift consent snapshot from the
    /// runtime's effective state.
    @discardableResult
    public static func submitConsentForm(
        _ form: ConsentForm,
        deviceId: String? = nil,
        platform: String? = nil,
        userId: String? = nil
    ) async throws -> ConsentSubmissionResult {
        try await shared._submitConsentForm(
            form,
            deviceId: deviceId,
            platform: platform,
            userId: userId
        )
    }

    private func _submitConsentForm(
        _ form: ConsentForm,
        deviceId: String?,
        platform: String?,
        userId: String?
    ) async throws -> ConsentSubmissionResult {
        guard let bridge = coreRuntime?.bridge, consentModule != nil else {
            throw SynheartError.notInitialized
        }
        if form.allowCloud, _synheartConfig?.deviceAuthConfig != nil {
            let registration = await _ensureDeviceAuthRegistered()
            if !registration.success {
                SynheartLogger.log(
                    "[Synheart] Cloud consent saved locally; device registration is not ready: "
                        + (registration.failure?.message ?? registration.status.status)
                )
            }
        }
        let data = try JSONEncoder().encode(form)
        guard let formJSON = String(data: data, encoding: .utf8) else {
            throw SynheartError.invalidArgument("Consent form could not be encoded")
        }
        let configuredConsent = _synheartConfig?.consentConfig
        let resolvedDeviceId = deviceId ?? configuredConsent?.deviceId ?? _synheartConfig?.deviceId
        let resolvedPlatform = platform ?? configuredConsent?.platform ?? _synheartConfig?.platform ?? "ios"
        let resolvedUserId = userId ?? configuredConsent?.userId ?? subjectId

        guard let resultJSON = await RuntimeWorkExecutor.run({
            bridge.consentSubmitForm(
                deviceId: resolvedDeviceId,
                platform: resolvedPlatform,
                userId: resolvedUserId,
                formJson: formJSON
            )
        }) else {
            throw SynheartError.runtimeOperationFailed("Native consent submission returned no result")
        }
        let result = try ConsentSubmissionResult(json: resultJSON)
        if let error = result.error {
            throw SynheartError.runtimeOperationFailed("Native consent submission failed: \(error)")
        }
        try await _refreshEffectiveConsent()
        return result
    }

    /// Update consent.
    public static func updateConsent(_ consent: ConsentSnapshot) async throws {
        try await shared._updateConsent(consent)
    }

    private func _updateConsent(_ consent: ConsentSnapshot) async throws {
        guard let consentModule, let coreRuntime, coreRuntime.isAvailable else {
            throw SynheartError.notInitialized
        }
        let current = consentModule.current()
        if let error = await RuntimeWorkExecutor.run({
            ConsentRuntimeCoordinator.apply(consent, replacing: current, through: coreRuntime)
        }) {
            throw error
        }
        try await _refreshEffectiveConsent()
    }

    // MARK: - SRM API

    /// Get baseline summary from the native synheart-engine (if available).
    public static var runtimeBaselineSummary: String? {
        shared.coreRuntime?.bridge?.srmOverallStatus()
    }

    /// Get all native runtime baselines as JSON, or `nil`.
    public static var runtimeBaselinesJson: String? {
        shared.coreRuntime?.bridge?.baselinesJson()
    }

    /// Export the native runtime SRM snapshot as JSON for cross-session persistence.
    public static func exportRuntimeSRMSnapshot() -> String? {
        shared.coreRuntime?.bridge?.exportSrmSnapshot()
    }

    /// Load a native runtime SRM snapshot from JSON. Returns true on success.
    @discardableResult
    public static func loadRuntimeSRMSnapshot(_ json: String) -> Bool {
        shared.coreRuntime?.bridge?.loadSrmSnapshot(json: json) ?? false
    }

    /// Get the native synheart-engine version, or `nil` if unavailable.
    public static var runtimeVersion: String? {
        guard let diag = shared.coreRuntime?.diagnostics(),
              let version = diag["version"] as? String else { return nil }
        return version
    }

    // MARK: - Sensor Push

    /// Push an RR interval to the core runtime with its sensor provider label.
    public static func pushRr(
        tsMs: Int64,
        rrMs: Double,
        provider: String = "default_sensor"
    ) {
        shared.coreRuntime?.pushRr(tsMs: tsMs, rrMs: rrMs, provider: provider)
    }

    /// Push a heart rate sample to the core runtime.
    public static func pushHr(tsMs: Int64, bpm: Double) {
        shared.coreRuntime?.pushHr(tsMs: tsMs, bpm: bpm)
    }

    /// Push an accelerometer sample to the core runtime.
    public static func pushAccel(tsMs: Int64, x: Double, y: Double, z: Double) {
        shared.coreRuntime?.pushAccel(tsMs: tsMs, x: x, y: y, z: z)
    }

    /// Push a behavior event to the core runtime.
    public static func pushBehavior(tsMs: Int64, eventType: Int32, value: Double) {
        shared.coreRuntime?.pushBehavior(tsMs: tsMs, eventType: eventType, value: value)
    }

    /// Push sleep stages JSON to the core runtime.
    public static func pushSleepStages(json: String) {
        shared.coreRuntime?.pushSleepStages(json: json)
    }

    // MARK: - Consent Change Handling

    private func handleConsentChange(_ newConsent: ConsentSnapshot) {
        previousConsent = newConsent
        _reevaluateAllFeatures()
    }

    // MARK: - Feature Reevaluation

    private func _reevaluateFeature(_ feature: SynheartFeature) {
        let activated = _activationManager?.isActivated(feature) ?? false
        let hasConsent = _hasConsentForFeature(feature)
        let capabilityAllowed = _isCapabilityAllowed(feature)
        let isOperational = activated && hasConsent && capabilityAllowed && isRunning

        switch feature {
        case .wear:
            if isOperational && wearModule?.status != .running {
                Task { do { try await wearModule?.start() } catch { SynheartLogger.log("[Synheart] Failed to start wear module: \(error)") } }
            } else if !isOperational && wearModule?.status == .running {
                Task { do { try await wearModule?.stop() } catch { SynheartLogger.log("[Synheart] Failed to stop wear module: \(error)") } }
            }
        case .behavior:
            if isOperational && behaviorModule?.status != .running {
                Task { do { try await behaviorModule?.start() } catch { SynheartLogger.log("[Synheart] Failed to start behavior module: \(error)") } }
            } else if !isOperational && behaviorModule?.status == .running {
                Task { do { try await behaviorModule?.stop() } catch { SynheartLogger.log("[Synheart] Failed to stop behavior module: \(error)") } }
            }
        case .phoneContext:
            if isOperational && phoneModule?.status != .running {
                Task { do { try await phoneModule?.start() } catch { SynheartLogger.log("[Synheart] Failed to start phone module: \(error)") } }
            } else if !isOperational && phoneModule?.status == .running {
                Task { do { try await phoneModule?.stop() } catch { SynheartLogger.log("[Synheart] Failed to stop phone module: \(error)") } }
            }
        case .cloud, .syni:
            break
        }
    }

    private func _reevaluateAllFeatures() {
        for feature in SynheartFeature.allCases {
            _reevaluateFeature(feature)
        }
    }

    private func _hasConsentForFeature(_ feature: SynheartFeature) -> Bool {
        guard let consent = _effectiveConsent() else { return false }
        switch feature.requiredConsent {
        case "biosignals":  return consent.allows(.biosignals)
        case "behavior":    return consent.allows(.behavior)
        case "phoneContext": return consent.allows(.phoneContext)
        case "cloudUpload": return consent.allows(.cloudUpload)
        case "syni":        return consent.allows(.syni)
        default:            return false
        }
    }

    private func _isCapabilityAllowed(_ feature: SynheartFeature) -> Bool {
        guard _synheartConfig?.deviceRole.supportedFeatures.contains(feature) == true else {
            return false
        }
        guard let cap = capabilityModule else { return false }
        switch feature {
        case .wear:         return cap.capability(.wear) != .none
        case .behavior:     return cap.capability(.behavior) != .none
        case .phoneContext: return cap.capability(.phone) != .none
        case .cloud:        return cap.capability(.cloud) != .none
        case .syni:         return true
        }
    }

    private func moduleId(for feature: SynheartFeature) -> String {
        switch feature {
        case .wear: return "wear"
        case .behavior: return "behavior"
        case .phoneContext: return "phone"
        case .cloud: return "cloud"
        case .syni: return "syni"
        }
    }

    // MARK: - Stop & Dispose

    /// Stop Synheart Core SDK (stops session).
    public static func stop() async throws {
        try await shared._stopSession()
    }

    /// Dispose all resources.
    public static func dispose() async throws {
        try await shared._dispose()
    }

    private func _dispose() async throws {
        try await _stopSession()
        await moduleManager.disposeAll()

        sessionModule?.dispose()
        sessionModule = nil
        sessionSubscription?.cancel()
        sessionSubscription = nil
        hsiToSessionCancellable?.cancel()
        hsiToSessionCancellable = nil

        cancellables.removeAll()

        _currentSessionHandle = nil
        _synheartConfig = nil
        nativeSubjectIdOverride = nil
        currentTokenSubject = nil

        coreRuntime?.bridge?.clearHsiCallback()
        coreRuntime = nil

        hsiDeliveryDeduplicator.reset()
        hsiSubject.send(nil)
        typedHsiSubject.send(nil)

        consentModule = nil
        capabilityModule = nil
        wearModule = nil
        phoneModule = nil
        behaviorModule = nil
        _activationManager = nil
        previousConsent = nil
        isConfigured = false
        isRunning = false
        collectionModuleFailures = [:]
        resetUploadDiagnostics()

        SynheartLogger.log("[Synheart] Disposed")
    }
}

// MARK: - Errors

public enum SynheartError: Error {
    case notInitialized
    case alreadyConfigured
    case runtimeIncompatible(missingSymbols: [String])
    case runtimeCreationFailed(message: String?)
    case invalidArgument(String)
    case runtimeOperationFailed(String)
    case consentRequired(String)
    case notImplemented(String)
    case capabilityTokenRequired
}
