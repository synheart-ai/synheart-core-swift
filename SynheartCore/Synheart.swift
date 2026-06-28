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
    private var cancellables = Set<AnyCancellable>()

    /// Subject the most recently issued cloud consent token was minted for.
    /// Used to detect a stale (different-subject) token after an account re-key.
    private var currentTokenSubject: String?

    private init() {}

    /// The subject id this SDK instance is configured for — the value uploads
    /// are attributed under and the consent token is minted for. Nil when not
    /// configured.
    var subjectId: String? { _synheartConfig?.subjectId ?? userId }

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
        guard let cr = shared.coreRuntime, cr.isAvailable else { return [] }
        let dicts = cr.listSessions()
        return dicts.compactMap { dict in
            guard let sessionId = dict["session_id"] as? String else { return nil }
            return SessionRecord(
                sessionId: sessionId,
                subjectId: (dict["subject_id"] as? String) ?? "",
                mode: (dict["mode"] as? String) ?? "personal",
                createdAtUtc: (dict["created_at_utc"] as? NSNumber)?.int64Value ?? 0,
                startUtc: (dict["start_utc"] as? NSNumber)?.int64Value ?? 0,
                appId: (dict["app_id"] as? String) ?? "",
                appVersion: (dict["app_version"] as? String) ?? "",
                deviceId: (dict["device_id"] as? String) ?? "",
                platform: (dict["platform"] as? String) ?? "ios"
            )
        }
    }

    /// Get a session summary (decrypted) for the given session.
    public static func getSessionSummary(_ sessionId: String) throws -> [String: Any]? {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return nil }
        return cr.getSessionSummary(sessionId)
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
        return []
    }

    // MARK: - Storage & Retention

    /// Get storage usage statistics.
    public static func getStorageUsage() throws -> StorageUsage {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            return StorageUsage(totalBytes: 0, bySessionBytes: [:])
        }
        return cr.getStorageUsage()
    }

    /// Set retention policy. Deletes sessions older than the given number of days.
    public static func setRetentionDays(_ days: Int?) throws {
    }

    // MARK: - Deletion API

    /// Delete a session and all its artifacts locally.
    public static func deleteLocalSession(_ sessionId: String) throws {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return }
        let _ = cr.deleteSession(sessionId)
    }

    /// Wipe all local data.
    public static func wipeLocalData() async throws {
        if let cr = shared.coreRuntime, cr.isAvailable {
            let _ = cr.wipeLocalData()
        }
        if shared.isRunning {
            try await shared._stopSession()
        }
        shared.coreRuntime = nil
        shared._currentSessionHandle = nil
        shared.isRunning = false
    }

    /// Request account deletion -- requests server-side deletion (device-signed
    /// by the runtime) and wipes local data.
    public static func requestAccountDeletion() async throws -> DeletionRequestResult {
        // The runtime owns the device-signed account-deletion request.
        let serverResult = shared.coreRuntime?.requestAccountDeletion()
        try await wipeLocalData()
        if let serverResult = serverResult, serverResult.status == "accepted" {
            return DeletionRequestResult(status: "accepted", message: "Local data wiped. Server deletion requested.")
        }
        return DeletionRequestResult(status: "accepted", message: "Local data wiped. Server deletion pending.")
    }

    /// Cancel a pending account deletion request (device-signed by the runtime).
    public static func cancelAccountDeletion() async throws -> DeletionRequestResult {
        guard let cr = shared.coreRuntime, cr.isAvailable else {
            return DeletionRequestResult(status: "error", message: "Runtime unavailable; cannot cancel deletion.")
        }
        if cr.cancelAccountDeletion() {
            return DeletionRequestResult(status: "cancelled", message: "Account deletion cancelled.")
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
    }

    /// Execute a sync cycle (push + pull).
    public static func syncNow() async throws -> SyncResult {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return SyncResult() }
        return cr.syncNow()
    }

    /// Get current sync status.
    public static func getSyncStatus() throws -> SyncStatus {
        return SyncStatus(enabled: false)
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
     * Must be called before any other operations. Throws if already initialized.
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
        try await shared._initialize(
            userId: resolvedUserId,
            config: config,
            appKey: appKey
        )
        if autoStart {
            try await shared._startSession()
        }
    }

    private func _initialize(
        userId: String,
        config: SynheartConfig?,
        appKey: String
    ) async throws {
        if isConfigured {
            throw SynheartError.alreadyConfigured
        }

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

        isConfigured = true

        self.coreRuntime = try? SynheartCoreShim(config: resolvedConfig)
        if let cr = coreRuntime, let bridge = cr.bridge {
            SynheartLogger.log("[Synheart] Core runtime bridge loaded")

            bridge.setHsiCallback { [weak self] json in
                guard let self = self else { return }
                guard self.consentModule?.current().biosignals == true else { return }
                self.hsiSubject.send(json)
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

        SynheartLogger.log("[Synheart] Initialization complete. Call startSession() to begin.")
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

        SynheartLogger.log("[Synheart] Starting session...")

        if let cr = coreRuntime, cr.isAvailable {
            if let handle = cr.startSession() {
                _currentSessionHandle = handle
            }
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sessionId = _currentSessionHandle?.sessionId ?? "core_\(nowMs)"
        let durationSec = 86400

        let config = SessionConfig(
            sessionId: sessionId,
            mode: .focus,
            durationSec: durationSec
        )

        if let module = sessionModule {
            let stream = module.startSession(config: config)
            sessionSubscription = stream
                .sink(
                    receiveCompletion: { [weak self] _ in
                        guard let self = self else { return }
                        if self.isRunning {
                            self.isRunning = false
                            self._reevaluateAllFeatures()
                            Task { try? await self.moduleManager.stopAll() }
                            SynheartLogger.log("[Synheart] Main session ended (duration or stream closed)")
                        }
                    },
                    receiveValue: { _ in }
                )
        }

        try await moduleManager.startAll()

        if _currentSessionHandle == nil {
            let mode = _synheartConfig?.mode ?? .personal
            _currentSessionHandle = SessionHandle(sessionId: sessionId, startedAtMs: nowMs, mode: mode)
        }

        isRunning = true
        _reevaluateAllFeatures()
        SynheartLogger.log("[Synheart] Session started")
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
            let _ = cr.stopSession()
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

        isRunning = false
        _reevaluateAllFeatures()
        try await moduleManager.stopAll()
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

        // Reissue: fetch the editable form, opt into cloud upload, resubmit.
        guard let formJson = bridge.consentEditableForm(),
              var form = parseDict(formJson) else { return false }
        form["allow_cloud"] = true
        guard let formData = try? JSONSerialization.data(withJSONObject: form),
              let formStr = String(data: formData, encoding: .utf8) else { return false }

        let subject = subjectId
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

    /// Push an RR interval to the core runtime.
    public static func pushRr(tsMs: Int64, rrMs: Double) {
        shared.coreRuntime?.pushRr(tsMs: tsMs, rrMs: rrMs)
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
        try await moduleManager.disposeAll()

        sessionModule?.dispose()
        sessionModule = nil
        sessionSubscription?.cancel()
        sessionSubscription = nil
        hsiToSessionCancellable?.cancel()
        hsiToSessionCancellable = nil

        cancellables.removeAll()

        _currentSessionHandle = nil
        _synheartConfig = nil

        coreRuntime?.bridge?.clearHsiCallback()
        coreRuntime = nil

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
    case notImplemented(String)
    case capabilityTokenRequired
}
