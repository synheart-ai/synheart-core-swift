import Foundation
import Combine

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
 * - Cloud Connector (secure uploads)
 *
 * Optional interpretation modules:
 * - Emotion (affect modeling)
 * - Focus (engagement/focus estimation)
 *
 * Example usage:
 * ```swift
 * // Initialize
 * try await Synheart.initialize(
 *     userId: "anon_user_123",
 *     config: SynheartConfig(
 *         enableWear: true,
 *         enablePhone: true,
 *         enableBehavior: true
 *     )
 * )
 *
 * // Subscribe to HSI updates (core state representation)
 * var cancellables = Set<AnyCancellable>()
 * Synheart.onHSIUpdate
 *     .sink { hsi in
 *         print("Arousal Index: \(hsi.affect?.arousalIndex ?? 0)")
 *         print("Engagement Stability: \(hsi.engagement?.engagementStability ?? 0)")
 *     }
 *     .store(in: &cancellables)
 *
 * // Optional: Enable interpretation modules
 * try await Synheart.enableFocus()
 * Synheart.onFocusUpdate
 *     .sink { focus in
 *         print("Focus Score: \(focus.score)")
 *     }
 *     .store(in: &cancellables)
 *
 * try await Synheart.enableEmotion()
 * Synheart.onEmotionUpdate
 *     .sink { emotion in
 *         print("Stress Index: \(emotion.stress)")
 *     }
 *     .store(in: &cancellables)
 *
 * // Enable cloud upload (with consent)
 * try await Synheart.enableCloud()
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
    private var srmModule: SRMModule?
    private var cloudConnector: CloudConnectorModule?

    // Activation manager (RFC-0005 four-authority model)
    private var _activationManager: ActivationManager?

    // State
    private var isConfigured = false
    private var isRunning = false
    private var userId: String?
    private var previousConsent: ConsentSnapshot?

    // Streams
    private let hsiSubject = CurrentValueSubject<String?, Never>(nil)

    private var cancellables = Set<AnyCancellable>()

    // Session data buffers — accumulate during session, persist after stop
    private let bufferQueue = DispatchQueue(label: "com.synheart.core.sessionBuffer")
    private var sessionHsiBuffer: [String] = []
    private var sessionWearBuffer: [WearSample] = []
    private var sessionHsiCancellable: AnyCancellable?
    private var sessionWearCancellable: AnyCancellable?

    private init() {}

    /// Whether the SDK has been initialized.
    public static var isInitialized: Bool {
        shared.isConfigured
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
     * This must be called before any other operations.
     *
     * Example:
     * ```swift
     * try await Synheart.initialize(
     *     userId: "anon_user_123",
     *     config: SynheartConfig(
     *         enableWear: true,
     *         enablePhone: true,
     *         enableBehavior: true
     *     )
     * )
     * ```
     */
    public static func initialize(
        userId: String,
        config: SynheartConfig? = nil,
        appKey: String = "mock_app_key"
    ) async throws {
        try await shared._initialize(
            userId: userId,
            config: config,
            appKey: appKey
        )
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

        SynheartLogger.log("[Synheart] Initializing SRM...")
        srmModule = SRMModule(storage: SRMSnapshotStorage())
        try moduleManager.registerModule(
            srmModule!,
            dependsOn: ["capabilities", "consent"]
        )

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

        if let cloudConfig = config?.cloudConfig {
            SynheartLogger.log("[Synheart] Initializing Cloud Connector...")
            cloudConnector = CloudConnectorModule(
                capabilities: capabilityModule!,
                consent: consentModule!,
                runtimeModule: runtimeModule!,
                config: cloudConfig
            )
            try moduleManager.registerModule(
                cloudConnector!,
                dependsOn: ["capabilities", "consent", "runtime"]
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

        _activationManager = ActivationManager()
        _activationManager!.activateFromConfig(resolvedConfig)

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
     * try await Synheart.initialize(userId: "user_123")
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
        try await moduleManager.startAll()

        // Clear session buffers and start accumulating
        bufferQueue.sync {
            sessionHsiBuffer.removeAll()
            sessionWearBuffer.removeAll()
        }

        sessionHsiCancellable = runtimeModule?.hsiStream
            .sink { [weak self] hsiJson in
                guard let self = self else { return }
                guard self.consentModule?.current().biosignals == true else { return }
                self.bufferQueue.sync { self.sessionHsiBuffer.append(hsiJson) }
            }
        sessionWearCancellable = wearModule?.rawSamplePublisher
            .sink { [weak self] sample in
                guard let self = self else { return }
                self.bufferQueue.sync { self.sessionWearBuffer.append(sample) }
            }

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

        // Cancel buffer subscriptions but keep buffers for post-session queries
        sessionHsiCancellable?.cancel()
        sessionHsiCancellable = nil
        sessionWearCancellable?.cancel()
        sessionWearCancellable = nil

        isRunning = false
        _reevaluateAllFeatures()
        try await moduleManager.stopAll()
        SynheartLogger.log("[Synheart] Session stopped")
    }

    // MARK: - Session Data Buffers

    /// Returns a snapshot of all HSI JSON windows accumulated during the current
    /// (or most recent) session. The list is cleared when ``startSession()`` is called.
    public static func getSessionHsiWindows() -> [String] {
        shared.bufferQueue.sync { Array(shared.sessionHsiBuffer) }
    }

    /// Returns a snapshot of all raw wear samples accumulated during the current
    /// (or most recent) session. The list is cleared when ``startSession()`` is called.
    public static func getSessionWearSamples() -> [WearSample] {
        shared.bufferQueue.sync { Array(shared.sessionWearBuffer) }
    }

    // MARK: - Interpretation Modules


    /**
     * Force upload of queued snapshots now
     *
     * - Throws: CloudConnectorError if cloudUpload consent not granted
     */
    public static func uploadNow() async throws {
        try await shared._uploadNow()
    }

    private func _uploadNow() async throws {
        guard isConfigured else {
            throw SynheartError.notInitialized
        }

        guard let cloudConnector = cloudConnector else {
            throw SynheartError.notImplemented("Cloud connector not enabled")
        }

        try await cloudConnector.uploadNow()
    }

    /**
     * Flush entire upload queue
     *
     * Attempts to upload all queued snapshots while online.
     */
    public static func flushUploadQueue() async throws {
        try await shared._flushUploadQueue()
    }

    private func _flushUploadQueue() async throws {
        guard isConfigured else {
            throw SynheartError.notInitialized
        }

        guard let cloudConnector = cloudConnector else {
            throw SynheartError.notImplemented("Cloud connector not enabled")
        }

        await cloudConnector.flushQueue()
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
            if isOperational && cloudConnector != nil {
                Task { do { try await cloudConnector?.start() } catch { SynheartLogger.log("[Synheart] Failed to start cloud connector: \(error)") } }
            } else if !isOperational && cloudConnector != nil {
                Task { do { try await cloudConnector?.stop() } catch { SynheartLogger.log("[Synheart] Failed to stop cloud connector: \(error)") } }
            }
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

        sessionHsiCancellable?.cancel()
        sessionHsiCancellable = nil
        sessionWearCancellable?.cancel()
        sessionWearCancellable = nil
        bufferQueue.sync {
            sessionHsiBuffer.removeAll()
            sessionWearBuffer.removeAll()
        }

        cancellables.removeAll()

        consentModule = nil
        capabilityModule = nil
        wearModule = nil
        phoneModule = nil
        behaviorModule = nil
        runtimeModule = nil
        srmModule = nil
        cloudConnector = nil
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
