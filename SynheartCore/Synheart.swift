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
    private var hsvRuntimeModule: HSVRuntimeModule?
    private var cloudConnector: CloudConnectorModule?
    // TODO: SyniHooksModule

    // Optional interpretation modules
    private var emotionHead: EmotionHead?
    private var focusHead: FocusHead?

    // State
    private var isConfigured = false
    private var isRunning = false
    private var userId: String?

    // Streams
    private let hsiSubject = CurrentValueSubject<HSV?, Never>(nil)
    private let emotionSubject = CurrentValueSubject<EmotionState?, Never>(nil)
    private let focusSubject = CurrentValueSubject<FocusState?, Never>(nil)

    private var cancellables = Set<AnyCancellable>()

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
     * Stream of HSI updates (core state representation)
     *
     * HSI contains:
     * - State axes (affect, engagement, activity, context)
     * - State indices (arousalIndex, engagementStability, etc.)
     * - 64D state embedding
     *
     * HSI MAY include interpretation fields (emotion, focus) if available.
     */
    public static var onHSIUpdate: AnyPublisher<HSV, Never> {
        shared.hsiSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    /**
     * Stream of base HSV updates (before emotion/focus heads)
     *
     * This is useful if you want strictly "core" state without interpretation.
     * Emits only after initialize() and while the HSI runtime module is running.
     */
    public static var onBaseHSIUpdate: AnyPublisher<HSV, Never> {
        guard let runtime = shared.hsvRuntimeModule else {
            return Empty().eraseToAnyPublisher()
        }
        return runtime.baseHsvStream
    }

    /**
     * Stream of emotion updates (optional interpretation)
     *
     * Only emits if emotion module is enabled via enableEmotion().
     */
    public static var onEmotionUpdate: AnyPublisher<EmotionState, Never> {
        shared.emotionSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    /**
     * Stream of focus updates (optional interpretation)
     *
     * Only emits if focus module is enabled via enableFocus().
     */
    public static var onFocusUpdate: AnyPublisher<FocusState, Never> {
        shared.focusSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
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

        print("[Synheart] Initializing...")

        // 1. Initialize capability module
        print("[Synheart] Initializing capability module...")
        capabilityModule = CapabilityModule()
        try await capabilityModule?.loadDefaults() // TODO: Load from token in production

        // 2. Initialize consent module
        print("[Synheart] Initializing consent module...")
        consentModule = ConsentModule()

        // 3. Register modules
        try moduleManager.registerModule(capabilityModule!)
        try moduleManager.registerModule(consentModule!)

        // 4. Initialize data collection modules
        print("[Synheart] Initializing data modules...")
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

        // 5. Initialize HSV Runtime (core + interpretation heads)
        print("[Synheart] Initializing HSV Runtime...")
        let collector = ChannelCollector(
            wear: wearModule!,
            phone: phoneModule!,
            behavior: behaviorModule!
        )
        hsvRuntimeModule = HSVRuntimeModule(
            collector: collector,
            emotionModel: config?.emotionModel,
            focusModel: config?.focusModel
        )
        try moduleManager.registerModule(
            hsvRuntimeModule!,
            dependsOn: ["wear", "phone", "behavior"]
        )

        // 6. Initialize Cloud Connector (optional, depends on config)
        if let cloudConfig = config?.cloudConfig {
            print("[Synheart] Initializing Cloud Connector...")
            cloudConnector = CloudConnectorModule(
                capabilities: capabilityModule!,
                consent: consentModule!,
                hsvRuntime: hsvRuntimeModule!,
                config: cloudConfig
            )
            try moduleManager.registerModule(
                cloudConnector!,
                dependsOn: ["capabilities", "consent", "hsv_runtime"]
            )
        }

        // 7. Initialize all modules
        print("[Synheart] Initializing all modules...")
        try await moduleManager.initializeAll()

        // 8. Subscribe to HSI stream (core state only)
        hsvRuntimeModule?.finalHsvStream
            .sink { [weak self] hsi in
                self?.hsiSubject.send(hsi)
            }
            .store(in: &cancellables)

        // 9. Start modules
        print("[Synheart] Starting all modules...")
        try await moduleManager.startAll()

        isConfigured = true
        isRunning = true
        print("[Synheart] Initialization complete")
    }

    /**
     * Enable focus interpretation module
     *
     * This is an optional interpretation module that consumes HSI
     * and produces focus estimates.
     *
     * Example:
     * ```swift
     * try await Synheart.enableFocus()
     * Synheart.onFocusUpdate
     *     .sink { focus in
     *         print("Focus Score: \(focus.score)")
     *     }
     *     .store(in: &cancellables)
     * ```
     */
    public static func enableFocus() async throws {
        try await shared._enableFocus()
    }

    private func _enableFocus() async throws {
        if !isConfigured {
            throw SynheartError.notInitialized
        }

        if focusHead != nil {
            print("[Synheart] Focus module already enabled")
            return
        }

        print("[Synheart] Enabling focus module...")
        // Enabling focus means: start publishing focus updates if/when the runtime provides them.
        // Focus computation happens inside HSVRuntimeModule's focus head.
        focusHead = FocusHead() // kept as an "enabled flag" for now (backwards compatible)
        Self.onHSIUpdate
            .compactMap { $0.focus }
            .sink { [weak self] focus in
                self?.focusSubject.send(focus)
            }
            .store(in: &cancellables)

        print("[Synheart] Focus module enabled")
    }

    /**
     * Enable emotion interpretation module
     *
     * This is an optional interpretation module that consumes HSI
     * and produces emotion estimates.
     *
     * Example:
     * ```swift
     * try await Synheart.enableEmotion()
     * Synheart.onEmotionUpdate
     *     .sink { emotion in
     *         print("Stress Index: \(emotion.stress)")
     *     }
     *     .store(in: &cancellables)
     * ```
     */
    public static func enableEmotion() async throws {
        try await shared._enableEmotion()
    }

    private func _enableEmotion() async throws {
        if !isConfigured {
            throw SynheartError.notInitialized
        }

        if emotionHead != nil {
            print("[Synheart] Emotion module already enabled")
            return
        }

        print("[Synheart] Enabling emotion module...")
        // Enabling emotion means: start publishing emotion updates if/when the runtime provides them.
        // Emotion computation happens inside HSVRuntimeModule's emotion head.
        emotionHead = EmotionHead() // kept as an "enabled flag" for now (backwards compatible)
        Self.onHSIUpdate
            .compactMap { $0.emotion }
            .sink { [weak self] emotion in
                self?.emotionSubject.send(emotion)
            }
            .store(in: &cancellables)

        print("[Synheart] Emotion module enabled")
    }

    /**
     * Enable cloud uploads (requires cloudUpload consent)
     *
     * Example:
     * ```swift
     * try await Synheart.enableCloud()
     * ```
     */
    public static func enableCloud() async throws {
        try await shared._enableCloud()
    }

    private func _enableCloud() async throws {
        guard isConfigured else {
            throw SynheartError.notInitialized
        }

        guard let consentModule = consentModule else {
            throw SynheartError.notInitialized
        }

        let currentConsent = consentModule.current()
        guard currentConsent.cloudUpload else {
            throw CloudConnectorError.consentRequired("cloudUpload consent required")
        }

        guard let cloudConnector = cloudConnector else {
            throw SynheartError.notImplemented(
                "Cloud connector not configured. Provide cloudConfig during initialization"
            )
        }

        try await cloudConnector.start()
    }

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
     * Disable cloud uploads
     */
    public static func disableCloud() async throws {
        try await shared._disableCloud()
    }

    private func _disableCloud() async throws {
        guard isConfigured else {
            throw SynheartError.notInitialized
        }

        try await cloudConnector?.stop()
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
        case "phoneContext", "motion":
            return consent.motion
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
        case "motion", "phoneContext":
            updated = current.copyWith(motion: true)
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
        case "motion", "phoneContext":
            updated = current.copyWith(motion: false)
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
     * Get current HSI state (latest)
     */
    public static var currentState: HSV? {
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

    /**
     * Stop Synheart Core SDK
     */
    public static func stop() async throws {
        try await shared._stop()
    }

    private func _stop() async throws {
        if !isRunning {
            return
        }

        print("[Synheart] Stopping...")
        try await moduleManager.stopAll()
        isRunning = false
        print("[Synheart] Stopped")
    }

    /**
     * Dispose all resources
     */
    public static func dispose() async throws {
        try await shared._dispose()
    }

    private func _dispose() async throws {
        try await _stop()
        try await moduleManager.disposeAll()

        cancellables.removeAll()

        consentModule = nil
        capabilityModule = nil
        wearModule = nil
        phoneModule = nil
        behaviorModule = nil
        hsvRuntimeModule = nil
        cloudConnector = nil
        emotionHead = nil
        focusHead = nil
        isConfigured = false
        isRunning = false

        print("[Synheart] Disposed")
    }
}

// MARK: - Errors

public enum SynheartError: Error {
    case notInitialized
    case alreadyConfigured
    case notImplemented(String)
}
