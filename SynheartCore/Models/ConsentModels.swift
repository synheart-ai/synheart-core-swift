import Foundation

/// Editable category-level consent form owned by the native runtime.
///
/// Hosts edit this value and submit it through ``Synheart/submitConsentForm(_:deviceId:platform:userId:)``.
/// The runtime persists the choice and intersects it with any configured app
/// policy before exposing ``ConsentEffectiveState``.
public struct ConsentForm: Codable, Equatable, Sendable {
    public let profileId: String
    public let biosignals: Bool
    public let phoneContext: Bool
    public let behavior: Bool
    public let consentTier: ConsentTier
    public let allowCloud: Bool
    public let allowResearch: Bool
    public let allowVendorSync: Bool
    public let syni: Bool

    public init(
        profileId: String,
        biosignals: Bool,
        phoneContext: Bool,
        behavior: Bool,
        consentTier: ConsentTier,
        allowCloud: Bool,
        allowResearch: Bool,
        allowVendorSync: Bool,
        syni: Bool = false
    ) {
        self.profileId = profileId
        self.biosignals = biosignals
        self.phoneContext = phoneContext
        self.behavior = behavior
        self.consentTier = consentTier
        self.allowCloud = allowCloud
        self.allowResearch = allowResearch
        self.allowVendorSync = allowVendorSync
        self.syni = syni
    }

    enum CodingKeys: String, CodingKey {
        case profileId = "profile_id"
        case biosignals
        case phoneContext = "phone_context"
        case behavior
        case consentTier = "consent_tier"
        case allowCloud = "allow_cloud"
        case allowResearch = "allow_research"
        case allowVendorSync = "allow_vendor_sync"
        case syni
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profileId = (try? container.decode(String.self, forKey: .profileId)) ?? ""
        biosignals = (try? container.decode(Bool.self, forKey: .biosignals)) ?? false
        phoneContext = (try? container.decode(Bool.self, forKey: .phoneContext)) ?? false
        behavior = (try? container.decode(Bool.self, forKey: .behavior)) ?? false
        consentTier = (try? container.decode(ConsentTier.self, forKey: .consentTier)) ?? .local
        allowCloud = (try? container.decode(Bool.self, forKey: .allowCloud)) ?? false
        allowResearch = (try? container.decode(Bool.self, forKey: .allowResearch)) ?? false
        allowVendorSync = (try? container.decode(Bool.self, forKey: .allowVendorSync)) ?? false
        syni = (try? container.decode(Bool.self, forKey: .syni)) ?? false
    }

    public func copyWith(
        profileId: String? = nil,
        biosignals: Bool? = nil,
        phoneContext: Bool? = nil,
        behavior: Bool? = nil,
        consentTier: ConsentTier? = nil,
        allowCloud: Bool? = nil,
        allowResearch: Bool? = nil,
        allowVendorSync: Bool? = nil,
        syni: Bool? = nil
    ) -> ConsentForm {
        ConsentForm(
            profileId: profileId ?? self.profileId,
            biosignals: biosignals ?? self.biosignals,
            phoneContext: phoneContext ?? self.phoneContext,
            behavior: behavior ?? self.behavior,
            consentTier: consentTier ?? self.consentTier,
            allowCloud: allowCloud ?? self.allowCloud,
            allowResearch: allowResearch ?? self.allowResearch,
            allowVendorSync: allowVendorSync ?? self.allowVendorSync,
            syni: syni ?? self.syni
        )
    }
}

/// Read-only consent state currently enforced by the native runtime.
public struct ConsentEffectiveState: Codable, Equatable, Sendable {
    public let biosignals: Bool
    public let phoneContext: Bool
    public let behavior: Bool
    public let cloudUpload: Bool
    public let syni: Bool
    public let vendorSync: Bool
    public let research: Bool
    public let timestampMs: Int64
    public let version: String

    public init(
        biosignals: Bool,
        phoneContext: Bool,
        behavior: Bool,
        cloudUpload: Bool,
        syni: Bool,
        vendorSync: Bool,
        research: Bool,
        timestampMs: Int64,
        version: String
    ) {
        self.biosignals = biosignals
        self.phoneContext = phoneContext
        self.behavior = behavior
        self.cloudUpload = cloudUpload
        self.syni = syni
        self.vendorSync = vendorSync
        self.research = research
        self.timestampMs = timestampMs
        self.version = version
    }

    public var hasAnyGrant: Bool {
        biosignals || phoneContext || behavior || cloudUpload || syni || vendorSync || research
    }

    enum CodingKeys: String, CodingKey {
        case biosignals
        case phoneContext = "phone_context"
        case behavior
        case cloudUpload = "cloud_upload"
        case syni
        case vendorSync = "vendor_sync"
        case research
        case timestampMs = "timestamp_ms"
        case version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        biosignals = (try? container.decode(Bool.self, forKey: .biosignals)) ?? false
        phoneContext = (try? container.decode(Bool.self, forKey: .phoneContext)) ?? false
        behavior = (try? container.decode(Bool.self, forKey: .behavior)) ?? false
        cloudUpload = (try? container.decode(Bool.self, forKey: .cloudUpload)) ?? false
        syni = (try? container.decode(Bool.self, forKey: .syni)) ?? false
        vendorSync = (try? container.decode(Bool.self, forKey: .vendorSync)) ?? false
        research = (try? container.decode(Bool.self, forKey: .research)) ?? false
        timestampMs = (try? container.decode(Int64.self, forKey: .timestampMs)) ?? 0
        version = (try? container.decode(String.self, forKey: .version)) ?? ""
    }

    public func allows(_ type: ConsentType) -> Bool {
        switch type {
        case .biosignals: return biosignals
        case .phoneContext: return phoneContext
        case .behavior: return behavior
        case .cloudUpload: return cloudUpload
        case .syni: return syni
        case .vendorSync: return vendorSync
        case .focusEstimation, .emotionEstimation: return biosignals
        }
    }

    public var snapshot: ConsentSnapshot {
        ConsentSnapshot(
            biosignals: biosignals,
            behavior: behavior,
            phoneContext: phoneContext,
            cloudUpload: cloudUpload,
            syni: syni,
            vendorSync: vendorSync,
            tier: research ? .research : (cloudUpload ? .cloud : .local),
            timestamp: timestampMs > 0
                ? Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1_000)
                : Date(),
            version: version.isEmpty ? "1.0.0" : version
        )
    }
}

/// Result returned after the runtime persists and optionally cloud-syncs a
/// consent form.
public struct ConsentSubmissionResult: Equatable, Sendable {
    public let synced: Bool
    public let tokenIssued: Bool
    public let error: String?
    public let rawJSON: String

    public var succeeded: Bool { error == nil }

    init(json: String) throws {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SynheartError.runtimeOperationFailed("Native consent submission returned invalid JSON")
        }
        synced = object["synced"] as? Bool ?? false
        tokenIssued = object["token"] != nil && !(object["token"] is NSNull)
        error = object["error"] as? String
        rawJSON = json
    }
}
