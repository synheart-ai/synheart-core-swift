import Foundation
import Combine
import SynheartSession

/**
 * Synheart Core SDK - Main Entry Point
 *
 * This is the main entry point for the Synheart Core SDK.
 * It orchestrates all core modules and optional interpretation modules.
 *
 * Core modules:
 * - Capabilities Module (feature gating)
 * - Consent Module (permission management)
 * - Wear Module (biosignal collection)
 * - Phone Module (motion/context)
 * - Behavior Module (interaction patterns)
 * - HSI Runtime (signal fusion & state computation)
 * - Auth Module (authentication)
 * - Sync Module (secure sync, replaces Cloud Connector)
 *
 * Example usage:
 * ```swift
 * // Initialize
 * try await Synheart.initialize(config: SynheartConfig(
 *     appId: "com.example.app",
 *     subjectId: "anon_user_123",
 *     allowUnsignedCapabilities: true
 * ))
 *
 * // Subscribe to typed state updates
 * var cancellables = Set<AnyCancellable>()
 * Synheart.onStateUpdate
 *     .sink { state in
 *         print("State: \(state)")
 *     }
 *     .store(in: &cancellables)
 *
 * // Start session
 * try await Synheart.startSession()
 *
 * // Sync data
 * try await Synheart.syncNow()
 * ```
 */
public class Synheart {
    public static let shared = Synheart()

    // Module manager
    private let moduleManager = ModuleManager()

    // Core modules
    private var capabilityModule: CapabilityModule?
    private var consentModule: ConsentModule?
    private var wearModule: WearModule?
    private var phoneModule: PhoneModule?
    private var behaviorModule: BehaviorModule?
    private var runtimeModule: RuntimeModule?
    private var platformIngestModule: PlatformIngestModule?

    // Activation manager (RFC-0005 four-authority model)
    private var _activationManager: ActivationManager?

    // State
    private var isConfigured = false
    private var isRunning = false
    private var userId: String?
    private var previousConsent: ConsentSnapshot?

    // Phase 1: Storage and artifact pipeline
    private var storageManager: StorageManager?
    private var _storagePolicy: StoragePolicy?
    private var artifactPipeline: ArtifactPipeline?
    private var _smk: SMK?
    private var _currentSessionHandle: SessionHandle?
    private var artifactHsiCancellable: AnyCancellable?
    private var _synheartConfig: SynheartConfig?

    // Phase 3: Auth & Sync
    private var _authModule: AuthModule?
    private var _syncModule: SyncModule?

    // Session module (wraps SessionEngine from synheart-session-swift)
    private var sessionModule: SessionModule?
    private var sessionSubscription: AnyCancellable?
    private var hsiToSessionCancellable: AnyCancellable?

    // Streams
    private let hsiSubject = CurrentValueSubject<String?, Never>(nil)

    private var cancellables = Set<AnyCancellable>()

    private init() {}

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

    /**
     * Stream of HSI updates (public state representation)
     *
     * HSI (Human State Interface) JSON frames produced by the synheart-runtime
     * engine. Each emission is a serialized HSI snapshot string.
     *
     * This is the ONLY public stream for human state.
     */
    public static var onHSIUpdate: AnyPublisher<String, Never> {
        shared.hsiSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }


    // MARK: - Phase 2: Typed State Subscription

    /// Stream of typed HSIState updates (RFC-CORE-0007 §3).
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

    // MARK: - Phase 2: Metrics API

    /// Record a single metric event for the current session.
    public static func recordMetric(_ event: MetricEvent) throws {
        guard let handle = shared._currentSessionHandle else { return }
        guard shared._storagePolicy?.canIncludeMetrics() == true else { return }
        try shared.storageManager?.insertMetric(sessionId: handle.sessionId, event: event)
    }

    // MARK: - Phase 2: Local Query API

    /// List stored sessions with optional filters.
    public static func listSessions(range: SessionRange? = nil) throws -> [SessionRecord] {
        guard let sm = shared.storageManager, sm.isOpen else { return [] }
        let mode: SynheartMode? = range?.mode.flatMap { SynheartMode(rawValue: $0) }
        return try sm.listSessions(startMs: range?.startMs, endMs: range?.endMs, mode: mode)
    }

    /// Get a session summary (decrypted) for the given session.
    public static func getSessionSummary(_ sessionId: String) throws -> [String: Any]? {
        guard let sm = shared.storageManager, sm.isOpen else { return nil }

        // Check cache first
        if let cached = try sm.getSummaryJson(sessionId),
           let data = cached.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        // Find and decrypt the artifact
        guard let smk = shared._smk else { return nil }
        let artifacts = try sm.getArtifactsBySession(sessionId, type: "session_summary")
        guard let first = artifacts.first else { return nil }
        return try? ArtifactCrypto.decrypt(smk: smk, combined: first.payload)
    }

    /// Get decrypted HSI window artifacts for a session.
    public static func getHSIWindows(_ sessionId: String, range: WindowRange? = nil) throws -> [[String: Any]] {
        guard let sm = shared.storageManager, sm.isOpen, let smk = shared._smk else { return [] }

        let artifacts = try sm.getArtifactsBySession(sessionId, type: "hsi_window")
        var results: [[String: Any]] = []
        for art in artifacts {
            if let s = range?.startMs, art.startMs < s { continue }
            if let e = range?.endMs, art.endMs > e { continue }
            if let json = try? ArtifactCrypto.decrypt(smk: smk, combined: art.payload) {
                results.append(json)
            }
            if let limit = range?.limit, results.count >= limit { break }
        }
        return results
    }

    // MARK: - Phase 2: Storage & Retention

    /// Get storage usage statistics.
    public static func getStorageUsage() throws -> StorageUsage {
        guard let sm = shared.storageManager, sm.isOpen else {
            return StorageUsage(totalBytes: 0, bySessionBytes: [:])
        }
        return try sm.getStorageUsage()
    }

    /// Set retention policy. Deletes sessions older than the given number of days.
    public static func setRetentionDays(_ days: Int?) throws {
        guard let days = days else { return }
        guard let sm = shared.storageManager, sm.isOpen else { return }
        let cutoffMs = Int64(Date().timeIntervalSince1970 * 1000) - Int64(days) * 86400000
        _ = try sm.enforceRetention(cutoffMs: cutoffMs)
    }

    // MARK: - Phase 2: Deletion API

    /// Delete a session and all its artifacts locally.
    public static func deleteLocalSession(_ sessionId: String) throws {
        guard let sm = shared.storageManager, sm.isOpen else { return }
        try sm.deleteSession(sessionId, createTombstones: true)
    }

    /// Wipe all local data.
    public static func wipeLocalData() async throws {
        if shared.isRunning {
            try await shared._stopSession()
        }
        if let sm = shared.storageManager, sm.isOpen {
            try sm.wipeAll()
            sm.close()
        }
        shared.storageManager = nil
        SMK.delete()
        URK.delete()

        // Phase 3: Clear auth/sync state
        shared._syncModule?.dispose()
        shared._syncModule = nil
        shared._authModule?.logout()
        shared._authModule = nil

        shared.artifactPipeline = nil
        shared._storagePolicy = nil
        shared._smk = nil
        shared._currentSessionHandle = nil
    }

    /// Request account deletion — wipes local data and requests server-side deletion.
    public static func requestAccountDeletion() async throws -> DeletionRequestResult {
        // POST server-side deletion request if authenticated
        if let auth = shared._authModule, auth.isAuthenticated, let token = auth.accessToken {
            let url = URL(string: "https://api.synheart.ai/account/v1/delete")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["confirmation": "DELETE_MY_ACCOUNT"])

            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if statusCode != 200 && statusCode != 202 {
                // Log but continue with local wipe
                SynheartLogger.log("[Synheart] Server account deletion request returned status \(statusCode)")
            }
        }

        try await wipeLocalData()
        return DeletionRequestResult(status: "accepted", message: "Local data wiped. Server deletion pending.")
    }

    /// Cancel a pending account deletion request.
    public static func cancelAccountDeletion() async throws -> Bool {
        guard let auth = shared._authModule, auth.isAuthenticated, let token = auth.accessToken else {
            return false
        }

        let url = URL(string: "https://api.synheart.ai/account/v1/delete/cancel")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        return statusCode == 200
    }

    // MARK: - Phase 3: Auth API

    /// Authenticate with a provider token.
    public static func authenticate(provider: String, token: String) async throws -> AuthResult {
        guard let auth = shared._authModule else { throw SynheartError.notInitialized }
        return try await auth.authenticate(provider: provider, token: token)
    }

    /// Get current auth status.
    public static var authStatus: AuthStatus? {
        shared._authModule?.status
    }

    /// Log out and clear auth state.
    public static func logout() {
        shared._syncModule?.dispose()
        shared._authModule?.logout()
        URK.delete()
    }

    // MARK: - Phase 3: Sync API

    /// Enable or disable sync.
    public static func setSyncEnabled(_ enabled: Bool) async throws {
        try await shared._syncModule?.setSyncEnabled(enabled)
    }

    /// Execute a sync cycle (push + pull).
    public static func syncNow() async throws -> SyncResult {
        guard let sync = shared._syncModule else { return SyncResult() }
        return try await sync.syncNow()
    }

    /// Get current sync status.
    public static func getSyncStatus() throws -> SyncStatus {
        guard let sync = shared._syncModule else {
            return SyncStatus(enabled: false)
        }
        return try sync.getStatus()
    }

    // MARK: - Activation API (RFC-0005)

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

    /**
     * Initialize Synheart Core SDK
     *
     * This is the single entry point for the SDK. Must be called before any
     * other operations. Idempotent — throws if already initialized.
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

        SynheartLogger.log("[Synheart] Initializing capability module...")
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

        SynheartLogger.log("[Synheart] Initializing consent module...")
        consentModule = ConsentModule()

        try moduleManager.registerModule(capabilityModule!)
        try moduleManager.registerModule(consentModule!)

        SynheartLogger.log("[Synheart] Initializing data modules...")
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

        // SRM is handled by the native runtime (RuntimeBridge.exportSrmSnapshot /
        // loadSrmSnapshot). BaselineSnapshot artifacts are produced via ArtifactPipeline.

        SynheartLogger.log("[Synheart] Initializing Runtime...")
        let runtimeSessionId = UUID().uuidString
        let bridge = RuntimeBridge.createIfAvailable(config: .init(
            subjectId: userId,
            sessionId: runtimeSessionId
        ))
        let behaviorPub: AnyPublisher<BehaviorEvent, Never>? = behaviorModule?.eventStreamInstance.events
            .catch { _ in Empty<BehaviorEvent, Never>() }
            .eraseToAnyPublisher()
        runtimeModule = RuntimeModule(
            bridge: bridge,
            wearSamplePublisher: nil,
            behaviorEventPublisher: behaviorPub
        )
        try moduleManager.registerModule(
            runtimeModule!,
            dependsOn: ["wear", "phone", "behavior", "srm"]
        )

        if let platformIngestConfig = config?.platformIngestConfig {
            SynheartLogger.log("[Synheart] Initializing Platform Ingest...")
            platformIngestModule = PlatformIngestModule(
                consentModule: consentModule!,
                config: platformIngestConfig
            )
            try moduleManager.registerModule(
                platformIngestModule!,
                dependsOn: ["consent"]
            )
        }

        SynheartLogger.log("[Synheart] Initializing all modules...")
        try await moduleManager.initializeAll()

        previousConsent = consentModule!.current()
        consentModule!.addListener { [weak self] newConsent in
            self?.handleConsentChange(newConsent)
        }

        runtimeModule?.hsiStream
            .sink { [weak self] hsiJson in
                guard let self = self else { return }
                guard self.consentModule?.current().biosignals == true else { return }
                self.hsiSubject.send(hsiJson)
            }
            .store(in: &cancellables)

        // Create SessionModule with adapted providers (mirrors Dart's
        // _watchSessionModule + _mainSession initialization pattern).
        let biosignalAdapter = WearModuleBiosignalAdapter(
            rawSamplePublisher: wearModule?.rawSamplePublisher ?? Empty<WearSample, Never>().eraseToAnyPublisher()
        )
        let behaviorAdapter: BehaviorModuleAdapter? = behaviorModule.map { BehaviorModuleAdapter(behaviorModule: $0) }
        sessionModule = SessionModule(
            biosignalProvider: biosignalAdapter,
            behaviorProvider: behaviorAdapter
        )

        // Bridge HSI metrics from runtime -> session engine (HRV is authoritative
        // from session-runtime; the session SDK no longer computes it locally).
        hsiToSessionCancellable = runtimeModule?.hsiStream
            .sink { [weak self] hsiJson in
                guard let self = self, self.sessionModule?.isActive == true else { return }
                if let data = hsiJson.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.sessionModule?.ingestHsiMetrics(parsed)
                }
            }

        _activationManager = ActivationManager()
        _activationManager!.activateFromConfig(resolvedConfig)

        // Phase 1: Initialize storage and artifact pipeline
        _synheartConfig = resolvedConfig
        if resolvedConfig.storage.enabled && !resolvedConfig.appId.isEmpty && !resolvedConfig.subjectId.isEmpty {
            do {
                _storagePolicy = storagePolicyForMode(resolvedConfig.mode)
                _smk = try SMK.loadOrCreate()
                let basePath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? NSTemporaryDirectory()
                storageManager = StorageManager(basePath: basePath)
                try storageManager!.open()

                artifactPipeline = ArtifactPipeline(
                    storage: storageManager!,
                    policy: _storagePolicy!,
                    smk: _smk!,
                    subjectId: resolvedConfig.subjectId,
                    appId: resolvedConfig.appId,
                    appVersion: resolvedConfig.appVersion,
                    deviceId: resolvedConfig.deviceId,
                    platform: resolvedConfig.platform
                )

                // Wire HSI stream to artifact pipeline
                artifactHsiCancellable = runtimeModule?.hsiStream
                    .sink { [weak self] hsiJson in
                        guard let self = self, let pipeline = self.artifactPipeline, self._currentSessionHandle != nil else { return }
                        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                        try? pipeline.ingestHsiFrame(hsiJson, timestampMs: nowMs)
                    }

                SynheartLogger.log("[Synheart] Storage and artifact pipeline initialized")
            } catch {
                SynheartLogger.log("[Synheart] Storage init failed (non-fatal): \(error)")
            }
        }

        // Phase 3: Initialize auth and sync modules
        let appId = resolvedConfig.appId
        if !appId.isEmpty {
            _authModule = AuthModule(appId: appId)
            _ = await _authModule!.restoreSession()

            if let sm = storageManager, sm.isOpen {
                _syncModule = SyncModule(
                    auth: _authModule!,
                    storage: sm,
                    smk: _smk,
                    baseUrl: "https://api.synheart.ai"
                )
            }
            SynheartLogger.log("[Synheart] Auth and sync modules initialized")
        }

        isConfigured = true
        SynheartLogger.log("[Synheart] Initialization complete. Call startSession() to begin.")
    }

    // MARK: - Session Lifecycle

    /**
     * Start a session — activates permitted modules and begins signal collection.
     *
     * Per RFC §5.2: Core must activate permitted modules, route normalized
     * signals to synheart-runtime, enable HSV updates, and enable optional HSI export.
     *
     * Must be called after initialize(). No data collection occurs until
     * this method is called (RFC §3.3).
     *
     * Example:
     * ```swift
     * try await Synheart.initialize(config: SynheartConfig(
     *     appId: "com.example.app",
     *     subjectId: "user_123",
     *     allowUnsignedCapabilities: true
     * ))
     * try await Synheart.startSession()
     * ```
     */
    public static func startSession() async throws {
        try await shared._startSession()
    }

    private func _startSession() async throws {
        guard isConfigured else {
            throw SynheartError.notInitialized
        }
        guard !isRunning else {
            return // Already running
        }

        SynheartLogger.log("[Synheart] Starting session...")

        // Open main collection session via Session SDK (RFC: session boundary)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sessionId = "core_\(nowMs)"
        let mode = _synheartConfig?.mode ?? .personal
        let durationSec = 86400 // default 24h — long-lived; stop explicitly

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
                            SynheartLogger.log(
                                "[Synheart] Main session ended (duration or stream closed)"
                            )
                        }
                    },
                    receiveValue: { _ in }
                )
        }

        try await moduleManager.startAll()

        // Phase 1: Create session record and start artifact pipeline
        if let sm = storageManager, sm.isOpen {
            try? sm.insertSession(SessionRecord(
                sessionId: sessionId,
                subjectId: _synheartConfig?.subjectId ?? userId ?? "",
                mode: mode.rawValue,
                createdAtUtc: nowMs / 1000,
                startUtc: nowMs / 1000,
                appId: _synheartConfig?.appId ?? "",
                appVersion: _synheartConfig?.appVersion ?? "0.0.0",
                deviceId: _synheartConfig?.deviceId ?? "",
                platform: _synheartConfig?.platform ?? "ios"
            ))
            artifactPipeline?.onSessionStart(sessionId, mode: mode)
        }
        _currentSessionHandle = SessionHandle(sessionId: sessionId, startedAtMs: nowMs, mode: mode)

        isRunning = true
        _reevaluateAllFeatures()
        SynheartLogger.log("[Synheart] Session started")
    }

    /**
     * Stop the current session — halts module streaming and clears ephemeral buffers.
     *
     * Per RFC §5.2: Core must halt module streaming, stop synheart-runtime updates,
     * clear ephemeral buffers, and prevent further HSI export.
     *
     * Modules remain initialized and can be restarted with startSession().
     *
     * Example:
     * ```swift
     * try await Synheart.stopSession()
     * ```
     */
    public static func stopSession() async throws {
        try await shared._stopSession()
    }

    private func _stopSession() async throws {
        guard isRunning else {
            return
        }

        SynheartLogger.log("[Synheart] Stopping session...")

        // Close main collection session via Session SDK
        if let activeId = sessionModule?.currentSessionId {
            sessionModule?.stopSession(sessionId: activeId)
        }
        sessionSubscription?.cancel()
        sessionSubscription = nil

        // Phase 1: Finalize session summary and baseline snapshot
        if let handle = _currentSessionHandle, let pipeline = artifactPipeline {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

            // SessionSummary artifact
            do {
                _ = try pipeline.finalizeSession(sessionStartMs: handle.startedAtMs, sessionEndMs: nowMs)
                SynheartLogger.log("[Synheart] Session summary artifact created")
            } catch {
                SynheartLogger.log("[Synheart] Session summary creation failed: \(error)")
            }

            // BaselineSnapshot from native SRM export
            do {
                if let srmJson = runtimeModule?.bridge?.exportSrmSnapshot() {
                    _ = try pipeline.produceBaselineSnapshot(srmJson)
                    SynheartLogger.log("[Synheart] Baseline snapshot artifact created")
                }
            } catch {
                SynheartLogger.log("[Synheart] Baseline snapshot creation failed: \(error)")
            }
        }
        // Auto-ingest session data via Platform Ingest
        if let piConfig = _synheartConfig?.platformIngestConfig, piConfig.autoIngest, let handle = _currentSessionHandle, platformIngestModule != nil {
            await _autoIngestSession(handle)
        }

        _currentSessionHandle = nil

        // Auto-sync after session ends
        if let sync = _syncModule, sync.enabled {
            Task { try? await sync.syncNow() }
        }

        isRunning = false
        _reevaluateAllFeatures()
        try await moduleManager.stopAll()
        SynheartLogger.log("[Synheart] Session stopped")
    }

    // MARK: - Auto-Ingest

    private func _autoIngestSession(_ session: SessionHandle) async {
        let behaviorEvents = behaviorModule?.rawEvents(.window1h) ?? []
        let phoneDataPoints = phoneModule?.rawDataPoints(.window1h) ?? []

        let payload = PlatformPayloadBuilder.buildSession(
            sessionId: session.sessionId,
            deviceId: _synheartConfig?.deviceId ?? "",
            appId: _synheartConfig?.appId ?? "",
            userId: _synheartConfig?.subjectId ?? "",
            startedAtMs: session.startedAtMs,
            endedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            dataOnCloud: _syncModule?.enabled ?? false,
            wearSamples: [],
            behaviorEvents: behaviorEvents,
            phoneDataPoints: phoneDataPoints
        )
        let _ = await platformIngestModule!.ingestSession(payload)
    }

    // MARK: - Session Module Access

    /// Stream of typed session events from the active session.
    /// Returns a publisher that emits `SessionEvent` values from the underlying
    /// `SessionEngine` (via `SessionModule`).
    public static var onSessionEvent: AnyPublisher<SessionEvent, Never> {
        shared.sessionModule?.events ?? Empty<SessionEvent, Never>().eraseToAnyPublisher()
    }

    /// Get the status of the current session from the session engine.
    public static func getSessionStatus() -> [String: Any]? {
        shared.sessionModule?.getStatus()
    }

    // MARK: - Platform Ingestion

    /// Ingest a session payload via the Platform Ingest module.
    ///
    /// Requires `behavior` consent.
    ///
    /// - Throws: `SynheartError` if SDK not initialized or platform ingest not configured
    public static func ingestSession(_ payload: [String: Any]) async throws -> PlatformIngestResponse {
        guard shared.isConfigured else {
            throw SynheartError.notInitialized
        }
        guard let module = shared.platformIngestModule else {
            throw SynheartError.notImplemented("Platform ingest not configured")
        }
        return await module.ingestSession(payload)
    }

    /// Ingest a metadata payload via the Platform Ingest module.
    ///
    /// Requires `biosignals` consent.
    ///
    /// - Throws: `SynheartError` if SDK not initialized or platform ingest not configured
    public static func ingestMetadata(_ payload: [String: Any]) async throws -> PlatformIngestResponse {
        guard shared.isConfigured else {
            throw SynheartError.notInitialized
        }
        guard let module = shared.platformIngestModule else {
            throw SynheartError.notImplemented("Platform ingest not configured")
        }
        return await module.ingestMetadata(payload)
    }

    /// Get the underlying PlatformIngestClient for standalone/background usage.
    ///
    /// Returns nil if platform ingest is not configured.
    public static var platformIngestClient: PlatformIngestClient? {
        shared.platformIngestModule?.client
    }

    /**
     * Check if user has granted a specific consent
     *
     * Example:
     * ```swift
     * let hasConsent = await Synheart.hasConsent("biosignals")
     * ```
     */
    public static func hasConsent(_ consentType: String) async -> Bool {
        await shared._hasConsent(consentType)
    }

    private func _hasConsent(_ consentType: String) async -> Bool {
        guard let consentModule = consentModule else {
            return false
        }

        let consent = consentModule.current()
        switch consentType {
        case "biosignals":
            return consent.biosignals
        case "behavior":
            return consent.behavior
        case "phoneContext":
            return consent.phoneContext
        case "cloudUpload":
            return consent.cloudUpload
        default:
            return false
        }
    }

    /**
     * Grant consent for a specific data type
     *
     * Example:
     * ```swift
     * try await Synheart.grantConsent("biosignals")
     * ```
     */
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
        case "biosignals":
            updated = current.copyWith(biosignals: true)
        case "behavior":
            updated = current.copyWith(behavior: true)
        case "phoneContext":
            updated = current.copyWith(phoneContext: true)
        case "cloudUpload":
            updated = current.copyWith(cloudUpload: true)
        case "syni":
            updated = current.copyWith(syni: true)
        default:
            updated = current
        }

        try await consentModule.updateConsent(updated)
    }

    /**
     * Revoke consent for a specific data type
     *
     * Example:
     * ```swift
     * try await Synheart.revokeConsent("biosignals")
     * ```
     */
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
        case "biosignals":
            updated = current.copyWith(biosignals: false)
        case "behavior":
            updated = current.copyWith(behavior: false)
        case "phoneContext":
            updated = current.copyWith(phoneContext: false)
        case "cloudUpload":
            updated = current.copyWith(cloudUpload: false)
        case "syni":
            updated = current.copyWith(syni: false)
        default:
            updated = current
        }

        try await consentModule.updateConsent(updated)
    }

    /**
     * Get current HSI state (latest JSON frame)
     */
    public static var currentState: String? {
        shared.hsiSubject.value
    }

    /**
     * Get current consent snapshot
     */
    public static var currentConsent: ConsentSnapshot? {
        shared.consentModule?.current()
    }

    /**
     * Update consent
     */
    public static func updateConsent(_ consent: ConsentSnapshot) async throws {
        guard let consentModule = shared.consentModule else {
            throw SynheartError.notInitialized
        }
        try await consentModule.updateConsent(consent)
    }

    // MARK: - synheart-runtime SRM API (baselines live in the native Rust engine)

    /// Get baseline summary from the native synheart-runtime (if available).
    ///
    /// Returns a JSON string like `{"total":14,"ready":0,"warming":5,"empty":9}`
    /// or `nil` if the native runtime is not linked.
    public static var runtimeBaselineSummary: String? {
        shared.runtimeModule?.bridge?.baselineSummary()
    }

    /// Get all native runtime baselines as JSON, or `nil`.
    public static var runtimeBaselinesJson: String? {
        shared.runtimeModule?.bridge?.baselinesJson()
    }

    /// Export the native runtime SRM snapshot as JSON for cross-session persistence.
    public static func exportRuntimeSRMSnapshot() -> String? {
        shared.runtimeModule?.bridge?.exportSrmSnapshot()
    }

    /// Load a native runtime SRM snapshot from JSON.
    /// Returns 0 on success, non-zero error code on failure, or `nil` if runtime unavailable.
    public static func loadRuntimeSRMSnapshot(_ json: String) -> Int32? {
        shared.runtimeModule?.bridge?.loadSrmSnapshot(json: json)
    }

    /// Get the native synheart-runtime version, or `nil` if unavailable.
    public static var runtimeVersion: String? {
        RuntimeBridge.version()
    }

    // MARK: - Consent Change Handling

    private func handleConsentChange(_ newConsent: ConsentSnapshot) {
        previousConsent = newConsent
        _reevaluateAllFeatures()
    }

    // MARK: - Feature Reevaluation (RFC-0005 Four-Authority Model)

    /// Reevaluate whether a single feature should be operational.
    ///
    /// ```
    /// isOperational = activated AND hasConsent AND capabilityAllowed AND isRunning
    /// ```
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
        case .cloud:
            break // Cloud connector replaced by SyncModule
        case .syni:
            break
        }
    }

    /// Reevaluate all features (e.g. after consent change or session start/stop).
    private func _reevaluateAllFeatures() {
        for feature in SynheartFeature.allCases {
            _reevaluateFeature(feature)
        }
    }

    /// Check consent for a feature's required consent type.
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

    /// Check whether the CapabilityModule allows a given feature.
    private func _isCapabilityAllowed(_ feature: SynheartFeature) -> Bool {
        guard let cap = capabilityModule else { return false }
        switch feature {
        case .wear:         return cap.capability(.wear) != .none
        case .behavior:     return cap.capability(.behavior) != .none
        case .phoneContext:  return cap.capability(.phone) != .none
        case .cloud:        return cap.capability(.cloud) != .none
        case .syni:         return true // no capability gate for syni yet
        }
    }

    /**
     * Stop Synheart Core SDK (stops session)
     */
    public static func stop() async throws {
        try await shared._stopSession()
    }

    /**
     * Dispose all resources
     */
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

        // Phase 1: Clean up storage and artifact pipeline
        artifactHsiCancellable?.cancel()
        artifactHsiCancellable = nil
        storageManager?.close()
        storageManager = nil
        artifactPipeline = nil
        _storagePolicy = nil
        _smk = nil
        _currentSessionHandle = nil
        _synheartConfig = nil

        // Phase 3
        _syncModule?.dispose()
        _syncModule = nil
        _authModule?.logout()
        _authModule = nil

        consentModule = nil
        capabilityModule = nil
        wearModule = nil
        phoneModule = nil
        behaviorModule = nil
        runtimeModule = nil
        platformIngestModule = nil
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
