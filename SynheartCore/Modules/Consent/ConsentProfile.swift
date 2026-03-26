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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        biosignals = (try? container.decode(BiosignalsConsent.self, forKey: .biosignals)) ?? BiosignalsConsent()
        phoneContext = (try? container.decode(PhoneContextConsent.self, forKey: .phoneContext)) ?? PhoneContextConsent()
        behavior = (try? container.decode(BehaviorConsent.self, forKey: .behavior)) ?? BehaviorConsent()
        interpretation = (try? container.decode(InterpretationConsent.self, forKey: .interpretation)) ?? InterpretationConsent()
    }
}

/// Biosignals consent configuration
public struct BiosignalsConsent: Codable {
    /// Consent for vitals (HR, HRV)
    public let vitals: Bool

    /// Consent for sleep data
    public let sleep: Bool

    public init(vitals: Bool = false, sleep: Bool = false) {
        self.vitals = vitals
        self.sleep = sleep
    }
}

/// Phone context consent configuration
public struct PhoneContextConsent: Codable {
    /// Consent for motion data
    public let motion: Bool

    /// Consent for screen state
    public let screenState: Bool

    public init(motion: Bool = false, screenState: Bool = false) {
        self.motion = motion
        self.screenState = screenState
    }
}

/// Behavior consent configuration
public struct BehaviorConsent: Codable {
    /// Consent for behavior tracking
    public let enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
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
