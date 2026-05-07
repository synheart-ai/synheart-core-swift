import Foundation
import Combine
import SynheartAuth
import SynheartSession

/**
 * Synheart Core SDK - Main Entry Point
 *
 * Orchestrates all core modules and the Rust core runtime bridge.
 *
 * Core modules:
 * - Capabilities Module (feature gating)
 * - Consent Module (permission management + scoped access tokens)
 * - Wear Module (biosignal collection)
 * - Phone Module (motion/context)
 * - Behavior Module (interaction patterns)
 * - Core Runtime Bridge (Rust FFI -- storage, crypto, sync, artifacts, HSI)
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

    private init() {}

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
    ///
    /// Mirrors the Flutter SDK's `recordMetrics(List<MetricEvent>)`.
    public static func recordMetrics(_ events: [MetricEvent]) throws {
        guard let cr = shared.coreRuntime, cr.isAvailable else { return }
        for event in events {
            let _ = cr.recordMetric(event)
        }
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

    /// Get decrypted HSI window artifacts for a session.
    public static func getHSIWindows(_ sessionId: String, range: WindowRange? = nil) throws -> [[String: Any]] {
        guard let bridge = shared.coreRuntime?.bridge else { return [] }
        let json = bridge.getHsiWindows(
            sessionId: sessionId,
            startMs: Int64(range?.startMs ?? 0),
            endMs: Int64(range?.endMs ?? 0),
            limit: Int32(range?.limit ?? 0)
        )
        guard let json,
              let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }
        return arr
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
    /// Pass `nil` to disable retention (keep indefinitely).
    public static func setRetentionDays(_ days: Int?) throws {
        guard let bridge = shared.coreRuntime?.bridge else { return }
        // Native runtime treats 0 as "no retention limit".
        let _ = bridge.setRetentionDays(days: Int32(days ?? 0))
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

    /// Wipe all local data. Alias of `wipeLocalData()` matching the Flutter SDK.
    public static func deleteLocalData() async throws {
        try await wipeLocalData()
    }

    /// Request account deletion -- wipes local data and requests server-side deletion.
    public static func requestAccountDeletion() async throws -> DeletionRequestResult {
        if let token = shared.consentModule?.getCurrentToken(), token.isValid {
            let url = URL(string: "https://api.synheart.ai/auth/v1/delete")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token.token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["confirmation": "DELETE_MY_ACCOUNT"])

            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if statusCode != 200 && statusCode != 202 {
                SynheartLogger.log("[Synheart] Server account deletion request returned status \(statusCode)")
            }
        }

        try await wipeLocalData()
        return DeletionRequestResult(status: "accepted", message: "Local data wiped. Server deletion pending.")
    }

    /// Cancel a pending account deletion request.
    public static func cancelAccountDeletion() async throws -> Bool {
        guard let token = shared.consentModule?.getCurrentToken(), token.isValid else {
            return false
        }

        let url = URL(string: "https://api.synheart.ai/auth/v1/delete/cancel")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token.token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        return statusCode == 200
    }

    /// Log out -- revoke consent.
    public static func logout() {
        try? shared.consentModule?.revokeConsent()
    }

    // MARK: - Sync API

    /// Enable or disable sync.
    public static func setSyncEnabled(_ enabled: Bool) async throws {
        shared.coreRuntime?.bridge?.setSyncEnabled(enabled: enabled)
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
        }

        SynheartLogger.log("[Synheart] Initialization complete. Call startSession() to begin.")
    }

    // MARK: - Session Lifecycle

    /**
     * Start a session -- activates permitted modules and begins signal collection.
     *
     * Must be called after initialize(). No data collection occurs until
     * this method is called.
     *
     * - Parameter durationSec: Session duration in seconds. `nil` uses the
     *   default 24h (86400). Mirrors the Flutter SDK's optional duration.
     * - Returns: The newly created `SessionHandle`, or `nil` if a session was
     *   already running.
     */
    @discardableResult
    public static func startSession(durationSec: Int? = nil) async throws -> SessionHandle? {
        try await shared._startSession(durationSec: durationSec)
        return shared._currentSessionHandle
    }

    private func _startSession(durationSec: Int? = nil) async throws {
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
        let resolvedDuration = durationSec ?? 86400
        let durationSec = resolvedDuration

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
    }

    /// Revoke consent for a specific data type.
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

    // MARK: - Module Status

    /// Per-module readiness flags. Mirrors the Flutter SDK's `getModuleStatuses()`.
    /// Keys: `"wear"`, `"behavior"`, `"phoneContext"`.
    public static func getModuleStatuses() -> [String: Bool] {
        return [
            "wear": shared.wearModule?.status == .running,
            "behavior": shared.behaviorModule?.status == .running,
            "phoneContext": shared.phoneModule?.status == .running,
        ]
    }

    // MARK: - Per-Module Collection Control

    /// Start wear (biosignal) collection. Mirrors Flutter's `startWearCollection({interval})`.
    ///
    /// - Parameter interval: Sample interval. Currently not honored — the
    ///   module uses `SynheartConfig.wearConfig.sampleRateHz` instead. Kept
    ///   in the signature for Flutter-API parity.
    public static func startWearCollection(interval: TimeInterval? = nil) async throws {
        _ = interval
        try await shared.wearModule?.start()
    }

    public static func stopWearCollection() async throws {
        try await shared.wearModule?.stop()
    }

    /// Start behavior (interaction) collection. Mirrors Flutter's `startBehaviorCollection()`.
    public static func startBehaviorCollection() async throws {
        try await shared.behaviorModule?.start()
    }

    public static func stopBehaviorCollection() async throws {
        try await shared.behaviorModule?.stop()
    }

    /// Start phone (motion / context) collection. Mirrors Flutter's `startPhoneCollection()`.
    public static func startPhoneCollection() async throws {
        try await shared.phoneModule?.start()
    }

    public static func stopPhoneCollection() async throws {
        try await shared.phoneModule?.stop()
    }

    // MARK: - Diagnostics & Upload State

    /// Full native runtime diagnostics as a parsed dictionary, or `nil` if the
    /// runtime is unavailable.
    ///
    /// Mirrors the Flutter SDK's `runtimeDiagnostics()` — same payload shape.
    public static func runtimeDiagnostics() -> [String: Any]? {
        guard let json = shared.coreRuntime?.bridge?.diagnostics(),
              let data = json.data(using: .utf8),
              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return parsed
    }

    /// Whether lab metadata is available for the current session.
    public static var isLabMetadataAvailable: Bool {
        shared.coreRuntime?.bridge?.isLabAvailable() ?? false
    }

    /// Number of HSI snapshots queued locally awaiting cloud upload.
    public static var uploadQueueLength: Int {
        shared.coreRuntime?.bridge?.uploadQueueLength() ?? 0
    }

    /// Last error code emitted by the native runtime; 0 if no error.
    public static var lastErrorCode: Int {
        shared.coreRuntime?.bridge?.lastErrorCode() ?? 0
    }

    /// Whether the native runtime library is loaded and responsive.
    public static var isRuntimeAvailable: Bool {
        shared.coreRuntime?.bridge?.isRuntimeAvailable() ?? false
    }

    /// Whether the network is currently reachable per the runtime.
    public static var isNetworkReachable: Bool {
        shared.coreRuntime?.bridge?.isNetworkReachable() ?? false
    }

    /// Force-flush any pending uploads. Returns the runtime's response JSON,
    /// or `nil` if the runtime is unavailable.
    @discardableResult
    public static func flushUploads() -> String? {
        shared.coreRuntime?.bridge?.flushUploads()
    }

    /// Raw JSON describing the most recent upload attempt, or `nil`.
    public static var uploadMetadata: String? {
        shared.coreRuntime?.bridge?.uploadMetadata()
    }

    /// Timestamp of the most recent successful cloud ingest, or `nil`.
    public static var lastIngestSuccessAtMs: Int64? {
        (parsedUploadMetadata()?["lastIngestSuccessAtMs"] as? NSNumber)?.int64Value
    }

    /// ID of the most recent upload batch, or `nil`.
    public static var lastUploadBatchId: String? {
        parsedUploadMetadata()?["lastUploadBatchId"] as? String
    }

    /// Error message from the most recent failed upload, or `nil`.
    public static var lastUploadError: String? {
        parsedUploadMetadata()?["lastUploadError"] as? String
    }

    private static func parsedUploadMetadata() -> [String: Any]? {
        guard let json = shared.coreRuntime?.bridge?.uploadMetadata(),
              let data = json.data(using: .utf8),
              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return parsed
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
