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
    private var hsiRuntimeModule: HSIRuntimeModule?
    // TODO: CloudConnectorModule
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

    /**
     * Stream of HSI updates (core state representation)
     *
     * HSI contains:
     * - State axes (affect, engagement, activity, context)
     * - State indices (arousalIndex, engagementStability, etc.)
     * - 64D state embedding
     *
     * HSI does NOT contain interpretation (emotion, focus).
     */
    public static var onHSIUpdate: AnyPublisher<HSV, Never> {
        shared.hsiSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
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
        moduleManager.registerModule(capabilityModule!)
        moduleManager.registerModule(consentModule!)

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

        moduleManager.registerModule(wearModule!, dependsOn: ["capabilities", "consent"])
        moduleManager.registerModule(phoneModule!, dependsOn: ["capabilities", "consent"])
        moduleManager.registerModule(behaviorModule!, dependsOn: ["capabilities", "consent"])

        // 5. Initialize HSI Runtime (NO emotion/focus here - they're optional)
        print("[Synheart] Initializing HSI Runtime...")
        let collector = ChannelCollector(
            wear: wearModule!,
            phone: phoneModule!,
            behavior: behaviorModule!
        )
        hsiRuntimeModule = HSIRuntimeModule(collector: collector)
        moduleManager.registerModule(
            hsiRuntimeModule!,
            dependsOn: ["wear", "phone", "behavior"]
        )

        // 6. Initialize all modules
        print("[Synheart] Initializing all modules...")
        try await moduleManager.initializeAll()

        // 7. Subscribe to HSI stream (core state only)
        hsiRuntimeModule?.hsiStream
            .sink { [weak self] hsi in
                self?.hsiSubject.send(hsi)
            }
            .store(in: &cancellables)

        // 8. Start modules
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

        focusHead = FocusHead()

        // Focus head subscribes to HSI stream
        Self.onHSIUpdate
            .sink { [weak self] hsi in
                guard let self = self, let focusHead = self.focusHead else { return }
                let hsvWithFocus = focusHead.processOne(hsi)
                if let focus = hsvWithFocus.focus {
                    self.focusSubject.send(focus)
                }
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

        emotionHead = EmotionHead()

        // Emotion head subscribes to HSI stream
        Self.onHSIUpdate
            .sink { [weak self] hsi in
                guard let self = self, let emotionHead = self.emotionHead else { return }
                let hsvWithEmotion = emotionHead.processOne(hsi)
                if let emotion = hsvWithEmotion.emotion {
                    self.emotionSubject.send(emotion)
                }
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
        // TODO: Implement cloud sync
        throw SynheartError.notImplemented("Cloud sync not yet implemented")
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

        let consent = await consentModule.current()
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

        var current = await consentModule.current()
        switch consentType {
        case "biosignals":
            current.biosignals = true
        case "behavior":
            current.behavior = true
        case "motion", "phoneContext":
            current.motion = true
        case "cloudUpload":
            current.cloudUpload = true
        case "syni":
            current.syni = true
        default:
            break
        }

        try await consentModule.updateConsent(current)
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

        var current = await consentModule.current()
        switch consentType {
        case "biosignals":
            current.biosignals = false
        case "behavior":
            current.behavior = false
        case "motion", "phoneContext":
            current.motion = false
        case "cloudUpload":
            current.cloudUpload = false
        case "syni":
            current.syni = false
        default:
            break
        }

        try await consentModule.updateConsent(current)
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
        get async {
            await shared.consentModule?.current()
        }
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
        hsiRuntimeModule = nil
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
