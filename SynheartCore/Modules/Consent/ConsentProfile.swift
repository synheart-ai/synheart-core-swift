import Foundation

/// Consent profile from consent service
public struct ConsentProfile: Codable {
    /// Profile ID
    public let id: String

    /// Profile name
    public let name: String

    /// Profile description
    public let description: String

    /// Consent channels configuration
    public let channels: ConsentChannels

    /// Whether cloud upload is enabled
    public let cloudEnabled: Bool

    /// Whether vendor sync is enabled
    public let vendorSyncEnabled: Bool

    /// Whether this is the default profile
    public let isDefault: Bool

    public init(
        id: String,
        name: String,
        description: String,
        channels: ConsentChannels,
        cloudEnabled: Bool,
        vendorSyncEnabled: Bool,
        isDefault: Bool
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.channels = channels
        self.cloudEnabled = cloudEnabled
        self.vendorSyncEnabled = vendorSyncEnabled
        self.isDefault = isDefault
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, channels
        case cloudEnabled = "cloud"
        case vendorSyncEnabled
        case isDefault = "is_default"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        channels = try container.decode(ConsentChannels.self, forKey: .channels)

        // Support both "cloud" and "cloudEnabled" keys
        if let cloud = try? container.decode(Bool.self, forKey: .cloudEnabled) {
            cloudEnabled = cloud
        } else {
            cloudEnabled = false
        }

        vendorSyncEnabled = (try? container.decode(Bool.self, forKey: .vendorSyncEnabled)) ?? false
        isDefault = (try? container.decode(Bool.self, forKey: .isDefault)) ?? false
    }
}

/// Consent channels configuration
public struct ConsentChannels: Codable {
    /// Biosignals consent configuration
    public let biosignals: BiosignalsConsent

    /// Phone context consent configuration
    public let phoneContext: PhoneContextConsent

    /// Behavior consent configuration
    public let behavior: BehaviorConsent

    /// Interpretation consent configuration
    public let interpretation: InterpretationConsent

    public init(
        biosignals: BiosignalsConsent,
        phoneContext: PhoneContextConsent,
        behavior: BehaviorConsent,
        interpretation: InterpretationConsent
    ) {
        self.biosignals = biosignals
        self.phoneContext = phoneContext
        self.behavior = behavior
        self.interpretation = interpretation
    }

    enum CodingKeys: String, CodingKey {
        case biosignals
        case phoneContext
        case phoneContextSnake = "phone_context"
        case behavior
        case interpretation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        biosignals = (try? container.decode(BiosignalsConsent.self, forKey: .biosignals)) ?? BiosignalsConsent()
        // Try camelCase first, then snake_case
        if let ctx = try? container.decode(PhoneContextConsent.self, forKey: .phoneContext) {
            phoneContext = ctx
        } else {
            phoneContext = (try? container.decode(PhoneContextConsent.self, forKey: .phoneContextSnake)) ?? PhoneContextConsent()
        }
        behavior = (try? container.decode(BehaviorConsent.self, forKey: .behavior)) ?? BehaviorConsent()
        interpretation = (try? container.decode(InterpretationConsent.self, forKey: .interpretation)) ?? InterpretationConsent()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(biosignals, forKey: .biosignals)
        try container.encode(phoneContext, forKey: .phoneContext)
        try container.encode(behavior, forKey: .behavior)
        try container.encode(interpretation, forKey: .interpretation)
    }
}

/// Biosignals consent configuration
public struct BiosignalsConsent: Codable {
    /// Consent for vitals (HR, HRV)
    public let vitals: Bool

    /// Consent for advanced cardiac metrics (e.g. ECG, BP estimation)
    public let cardioAdvanced: Bool

    /// Consent for neuromuscular signals (e.g. EMG, EDA)
    public let neuromuscular: Bool

    /// Consent for wearable motion data (e.g. accelerometer, gyroscope)
    public let wearableMotion: Bool

    /// Consent for sleep data
    public let sleep: Bool

    enum CodingKeys: String, CodingKey {
        case vitals
        case cardioAdvanced = "cardio_advanced"
        case neuromuscular
        case wearableMotion = "wearable_motion"
        case sleep
    }

    public init(
        vitals: Bool = false,
        cardioAdvanced: Bool = false,
        neuromuscular: Bool = false,
        wearableMotion: Bool = false,
        sleep: Bool = false
    ) {
        self.vitals = vitals
        self.cardioAdvanced = cardioAdvanced
        self.neuromuscular = neuromuscular
        self.wearableMotion = wearableMotion
        self.sleep = sleep
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vitals = (try? container.decode(Bool.self, forKey: .vitals)) ?? false
        cardioAdvanced = (try? container.decode(Bool.self, forKey: .cardioAdvanced)) ?? false
        neuromuscular = (try? container.decode(Bool.self, forKey: .neuromuscular)) ?? false
        wearableMotion = (try? container.decode(Bool.self, forKey: .wearableMotion)) ?? false
        sleep = (try? container.decode(Bool.self, forKey: .sleep)) ?? false
    }
}

/// Phone context consent configuration
public struct PhoneContextConsent: Codable {
    /// Consent for device motion sensors (accelerometer, gyroscope)
    public let deviceMotion: Bool

    /// Consent for device context (locale, timezone, device type)
    public let deviceContext: Bool

    /// Consent for system state (screen on/off, charging, connectivity)
    public let systemState: Bool

    enum CodingKeys: String, CodingKey {
        case deviceMotion = "device_motion"
        case deviceContext = "device_context"
        case systemState = "system_state"
        // Legacy keys for backward-compat decoding
        case legacyMotion = "motion"
        case legacyScreenState = "screenState"
    }

    public init(
        deviceMotion: Bool = false,
        deviceContext: Bool = false,
        systemState: Bool = false
    ) {
        self.deviceMotion = deviceMotion
        self.deviceContext = deviceContext
        self.systemState = systemState
    }

    /// Backward-compatible alias for `deviceMotion`
    @available(*, deprecated, renamed: "deviceMotion")
    public var motion: Bool { deviceMotion }

    /// Backward-compatible alias for `systemState`
    @available(*, deprecated, renamed: "systemState")
    public var screenState: Bool { systemState }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try new key first, fall back to legacy key
        if let val = try? container.decode(Bool.self, forKey: .deviceMotion) {
            deviceMotion = val
        } else {
            deviceMotion = (try? container.decode(Bool.self, forKey: .legacyMotion)) ?? false
        }
        deviceContext = (try? container.decode(Bool.self, forKey: .deviceContext)) ?? false
        if let val = try? container.decode(Bool.self, forKey: .systemState) {
            systemState = val
        } else {
            systemState = (try? container.decode(Bool.self, forKey: .legacyScreenState)) ?? false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceMotion, forKey: .deviceMotion)
        try container.encode(deviceContext, forKey: .deviceContext)
        try container.encode(systemState, forKey: .systemState)
    }
}

/// Behavior consent configuration
public struct BehaviorConsent: Codable {
    /// Consent for digital activity tracking (typing, mouse, app usage)
    public let digitalActivity: Bool

    /// Consent for notification pattern analysis
    public let notificationPatterns: Bool

    /// Consent for app context collection
    public let appContext: Bool

    enum CodingKeys: String, CodingKey {
        case digitalActivity = "digital_activity"
        case notificationPatterns = "notification_patterns"
        case appContext = "app_context"
        // Legacy key for backward-compat decoding
        case legacyEnabled = "enabled"
    }

    public init(
        digitalActivity: Bool = false,
        notificationPatterns: Bool = false,
        appContext: Bool = false
    ) {
        self.digitalActivity = digitalActivity
        self.notificationPatterns = notificationPatterns
        self.appContext = appContext
    }

    /// Backward-compatible computed property: true if any behavior channel is enabled
    public var enabled: Bool { digitalActivity || notificationPatterns || appContext }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try new granular keys first
        if let val = try? container.decode(Bool.self, forKey: .digitalActivity) {
            digitalActivity = val
            notificationPatterns = (try? container.decode(Bool.self, forKey: .notificationPatterns)) ?? false
            appContext = (try? container.decode(Bool.self, forKey: .appContext)) ?? false
        } else if let legacyEnabled = try? container.decode(Bool.self, forKey: .legacyEnabled) {
            // Legacy: map old `enabled` to `digitalActivity`
            digitalActivity = legacyEnabled
            notificationPatterns = false
            appContext = false
        } else {
            digitalActivity = false
            notificationPatterns = false
            appContext = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(digitalActivity, forKey: .digitalActivity)
        try container.encode(notificationPatterns, forKey: .notificationPatterns)
        try container.encode(appContext, forKey: .appContext)
    }
}

/// Interpretation consent configuration
public struct InterpretationConsent: Codable {
    /// Consent for focus estimation
    public let focusEstimation: Bool

    /// Consent for emotion estimation
    public let emotionEstimation: Bool

    enum CodingKeys: String, CodingKey {
        case focusEstimation = "focus_estimation"
        case emotionEstimation = "emotion_estimation"
    }

    public init(focusEstimation: Bool = false, emotionEstimation: Bool = false) {
        self.focusEstimation = focusEstimation
        self.emotionEstimation = emotionEstimation
    }
}
