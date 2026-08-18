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
    private var userId: String?
    private var previousConsent: ConsentSnapshot?

    private var _currentSessionHandle: SessionHandle?
    private var _synheartConfig: SynheartConfig?

    private var sessionModule: SessionModule?
    private var sessionSubscription: AnyCancellable?
    private var hsiToSessionCancellable: AnyCancellable?

    private let hsiSubject = CurrentValueSubject<String?, Never>(nil)
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

    /// Stream of HSI JSON frames produced by synheart-engine.
    public static var onHSIUpdate: AnyPublisher<String, Never> {
        shared.hsiSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    // MARK: - Typed State Subscription

    /// Stream of typed HSIState updates.
    public static var onStateUpdate: AnyPublisher<HSIState, Never> {
        shared.hsiSubject
            .compactMap { $0 }
            .map { HSIState.fromJson($0, subjectId: shared._synheartConfig?.subjectId ?? shared.userId ?? "") }
            .eraseToAnyPublisher()
    }

    /// Get the current HSI state as a typed object.
    public static var currentHSIState: HSIState? {
        guard let json = shared.hsiSubject.value else { return nil }
        return HSIState.fromJson(json, subjectId: shared._synheartConfig?.subjectId ?? shared.userId ?? "")
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
    public static func enrolResearchStudy(accessCode: String, studyCode: String) throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return nil }
        return cr.enrolResearchStudy(accessCode: accessCode, studyCode: studyCode)
    }

    /// Preview an access + study code pair without redeeming the code.
    public static func validateResearchStudyCodes(accessCode: String, studyCode: String) throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return nil }
        return cr.validateResearchStudyCodes(accessCode: accessCode, studyCode: studyCode)
    }

    /// Withdraw from the device's active research study for this app. No codes —
    /// the participant + app come from the device's signed credential. Idempotent.
    public static func withdrawResearchStudy() throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return nil }
        return cr.withdrawResearchStudy()
    }

    /// Request erasure of the data the participant contributed to their study for
    /// this app — the deletion the consent copy promises alongside withdrawal. No
    /// identifiers are passed; the participant + app come from the device's signed
    /// credential. When `dryRun` is true the response is an inventory preview and
    /// nothing is deleted; a real request is accepted asynchronously and carries a
    /// `request_id`. Idempotent. Returns nil if the runtime is unavailable.
    public static func requestStudyDataDeletion(dryRun: Bool = false) throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return nil }
        return cr.requestStudyDataDeletion(dryRun: dryRun)
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
        guard cr.wipeLocalData() else {
            throw SynheartError.runtimeOperationFailed("Unable to wipe local data")
        }
        shared._currentSessionHandle = nil
        shared.isRunning = false
        shared.hsiSubject.send(nil)
    }

    /// Request account deletion -- requests server-side deletion (device-signed
    /// by the runtime) and wipes local data.
    public static func requestAccountDeletion() async throws -> DeletionRequestResult {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        let serverAccepted = cr.requestAccountDeletion().status == "accepted"
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
        if cr.cancelAccountDeletion() {
            return DeletionRequestResult(
                status: "cancelled",
                message: "Account deletion cancelled."
            )
        }
        return DeletionRequestResult(status: "error", message: "Cancel request failed.")
    }

    /// Log out -- revoke consent.
    public static func logout() {
        try? shared.consentModule?.revokeConsent()
    }

    // MARK: - Sync API

    /// Enable or disable sync.
    public static func setSyncEnabled(_ enabled: Bool) async throws {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }
        cr.setSyncEnabled(enabled)
        guard let status = cr.syncStatus() else {
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
        guard let result = cr.syncNow() else {
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

        SynheartLogger.log("[Synheart] Initializing...")

        capabilityModule = CapabilityModule()
        let resolvedConfig = config ?? SynheartConfig()
        if let token = resolvedConfig.capabilityToken,
           let secret = resolvedConfig.capabilitySecret {
            try capabilityModule!.loadFromToken(token, secret: secret)
        } else if resolvedConfig.allowUnsignedCapabilities {
            SynheartLogger.log("[Synheart] WARNING: Running with unsigned default capabilities. Do not use in production.")
            capabilityModule!.loadDefaults()
        } else {
            throw SynheartError.capabilityTokenRequired
        }

        consentModule = ConsentModule()

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
            consent: consentModule!
        )
        behaviorModule = BehaviorModule(
            capabilities: capabilityModule!,
            consent: consentModule!
        )

        try moduleManager.registerModule(wearModule!, dependsOn: ["capabilities", "consent"])
        try moduleManager.registerModule(phoneModule!, dependsOn: ["capabilities", "consent"])
        try moduleManager.registerModule(behaviorModule!, dependsOn: ["capabilities", "consent"])

        try await moduleManager.initializeAll()

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

        if !resolvedConfig.appId.isEmpty {
            SynheartAuth.shared.configure(baseUrl: "https://api.synheart.ai/auth")
        }

        let dataDirectory = try RuntimeDataDirectory.prepare()
        self.coreRuntime = try SynheartCoreShim(
            config: resolvedConfig,
            dataDir: dataDirectory
        )
        if let cr = coreRuntime, let bridge = cr.bridge {
            SynheartLogger.log("[Synheart] Core runtime bridge loaded")

            // Capture the canonical subject the runtime resolved (a device-auth
            // derive may have changed it) so SDK subject checks match native.
            syncSubjectFromNative()

            bridge.setHsiCallback { [weak self] json in
                guard let self = self else { return }
                guard self.consentModule?.current().biosignals == true else { return }
                guard self.hsiDeliveryDeduplicator.shouldDeliver(json: json) else { return }
                self.hsiSubject.send(json)
            }

            // Device auth: hand the runtime its secure-storage + Secure Enclave
            // crypto callbacks before any registration so consent tokens persist
            // and can be minted. Best-effort: a build lacking the symbols just
            // means minting stays unavailable (logged), not a crash.
            let storageRc = bridge.setStorageCallbacks()
            if storageRc != 0 {
                SynheartLogger.log("[Synheart] set_storage_callbacks rc=\(storageRc); state will not persist")
            }
            let cryptoRc = bridge.setSdkCryptoCallbacks()
            if cryptoRc != 0 {
                SynheartLogger.log("[Synheart] set_crypto_callbacks rc=\(cryptoRc); device auth unavailable")
            }

            // Configure the cloud consent client so a subject-scoped token can be
            // minted; without a base URL the cloud clients are unconfigured.
            let cloudBaseUrl = resolvedConfig.cloudConfig?.baseUrl ?? ApiEndpoints.defaultCloudBaseUrl
            _ = bridge.consentConfigureCloud(baseUrl: cloudBaseUrl, appId: resolvedConfig.appId)

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
        isConfigured = false
        isRunning = false
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
        guard let consent = consentModule?.current(),
              SessionStartPolicy.hasCollectionConsent(consent) else {
            throw SynheartError.consentRequired(
                "Grant biosignals, behavior, or phone-context consent before starting a session"
            )
        }
        guard let cr = coreRuntime, cr.isAvailable else {
            throw SynheartError.notInitialized
        }

        SynheartLogger.log("[Synheart] Starting session...")

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

            try await moduleManager.startAll()
            isRunning = true
            _reevaluateAllFeatures()
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
        isRunning = false

        SynheartLogger.log("[Synheart] Stopping session...")

        var nativeStopped = true
        if let cr = coreRuntime, cr.isAvailable {
            nativeStopped = cr.stopSession()
        }

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
        guard nativeStopped else {
            throw SynheartError.runtimeOperationFailed("Native session stop failed")
        }
        SynheartLogger.log("[Synheart] Session stopped")
    }

    private func _autoIngestSession(_ session: SessionHandle) async {
        coreRuntime?.bridge?.flushUploads()
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
        guard let consentModule = consentModule else { return false }

        let consent = consentModule.current()
        switch consentType {
        case "biosignals":  return consent.biosignals
        case "behavior":    return consent.behavior
        case "phoneContext": return consent.phoneContext
        case "cloudUpload": return consent.cloudUpload
        default:            return false
        }
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

        try await consentModule.updateConsent(updated)

        // Granting cloud upload should immediately mint a consent token for the
        // current subject so pending data can flush. Best-effort.
        if consentType == "cloudUpload" {
            _ = await _ensureCloudConsentReady()
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

        try await consentModule.updateConsent(updated)
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

    /// Update consent.
    public static func updateConsent(_ consent: ConsentSnapshot) async throws {
        guard let consentModule = shared.consentModule else {
            throw SynheartError.notInitialized
        }
        try await consentModule.updateConsent(consent)
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
        guard let consent = consentModule?.current() else { return false }
        switch feature.requiredConsent {
        case "biosignals":  return consent.biosignals
        case "behavior":    return consent.behavior
        case "phoneContext": return consent.phoneContext
        case "cloudUpload": return consent.cloudUpload
        case "syni":        return consent.syni
        default:            return false
        }
    }

    private func _isCapabilityAllowed(_ feature: SynheartFeature) -> Bool {
        guard let cap = capabilityModule else { return false }
        switch feature {
        case .wear:         return cap.capability(.wear) != .none
        case .behavior:     return cap.capability(.behavior) != .none
        case .phoneContext: return cap.capability(.phone) != .none
        case .cloud:        return cap.capability(.cloud) != .none
        case .syni:         return true
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

        consentModule = nil
        capabilityModule = nil
        wearModule = nil
        phoneModule = nil
        behaviorModule = nil
        _activationManager = nil
        previousConsent = nil
        isConfigured = false
        isRunning = false

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
