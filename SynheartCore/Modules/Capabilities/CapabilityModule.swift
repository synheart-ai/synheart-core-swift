import Foundation
import Combine

/// Capabilities Module
///
/// Manages SDK capabilities based on authentication tokens.
/// Determines which features each module can use based on capability tiers.
public class CapabilityModule: BaseSynheartModule, CapabilityProvider {
    private var capabilities: SDKCapabilities?
    private var token: CapabilityToken?
    private let verifier = CapabilityVerifier()
    private let capabilitiesSubject = CurrentValueSubject<SDKCapabilities?, Never>(nil)

    /// Stream of capability updates
    public var capabilitiesStream: AnyPublisher<SDKCapabilities?, Never> {
        return capabilitiesSubject.eraseToAnyPublisher()
    }

    public init() {
        super.init(moduleId: "capabilities")
    }

    /// Load capabilities from token
    public func loadFromToken(_ token: CapabilityToken, secret: String) throws {
        guard verifier.isValid(token, secret: secret) else {
            throw CapabilityException("Invalid capability token")
        }

        self.token = token
        self.capabilities = try verifier.parse(token)
        capabilitiesSubject.send(capabilities)
    }

    /// Load default capabilities (for development/testing)
    public func loadDefaults() {
        capabilities = SDKCapabilities.defaultCapabilities()
        capabilitiesSubject.send(capabilities)
    }

    // MARK: - CapabilityProvider

    public func capability(_ module: Module) -> CapabilityLevel {
        guard let capabilities = capabilities else {
            return .none
        }
        return capabilities.getLevel(module)
    }

    public func isEnabled(_ feature: FeatureFlag) -> Bool {
        guard let capabilities = capabilities else {
            return false
        }

        return isFeatureEnabled(feature, capabilities: capabilities)
    }

    public func canAccessFeature(moduleId: String, featureId: String) -> Bool {
        return true
    }

    public func getAllCapabilities() -> [Module: CapabilityLevel] {
        guard let capabilities = capabilities else {
            return [:]
        }

        return [
            .behavior: capabilities.behavior,
            .wear: capabilities.wear,
            .phone: capabilities.phone,
            .hsi: capabilities.hsi,
            .cloud: capabilities.cloud
        ]
    }

    /// Check if a feature is enabled based on capability levels
    private func isFeatureEnabled(_ feature: FeatureFlag, capabilities: SDKCapabilities) -> Bool {
        switch feature {
        // Wear features
        case .wearDerivedMetrics:
            return capabilities.wear.rawValue >= CapabilityLevel.core.rawValue
        case .wearHighFrequencyHrv:
            return capabilities.wear.rawValue >= CapabilityLevel.extended.rawValue
        case .wearRawRrIntervals:
            return capabilities.wear.rawValue >= CapabilityLevel.research.rawValue

        // Phone features
        case .phoneMotionAndScreen:
            return capabilities.phone.rawValue >= CapabilityLevel.core.rawValue
        case .phoneHashedAppSwitching:
            return capabilities.phone.rawValue >= CapabilityLevel.core.rawValue
        case .phoneDetailedAppContext:
            return capabilities.phone.rawValue >= CapabilityLevel.extended.rawValue
        case .phoneRawNotificationStructure:
            return capabilities.phone.rawValue >= CapabilityLevel.extended.rawValue

        // Behavior features
        case .behaviorBasicMetrics:
            return capabilities.behavior.rawValue >= CapabilityLevel.core.rawValue
        case .behaviorExtendedPatterns:
            return capabilities.behavior.rawValue >= CapabilityLevel.extended.rawValue
        case .behaviorFullTimingStream:
            return capabilities.behavior.rawValue >= CapabilityLevel.research.rawValue

        // HSI features
        case .hsiEmotionFocus:
            return capabilities.hsi.rawValue >= CapabilityLevel.core.rawValue
        case .hsiFullEmbedding:
            return capabilities.hsi.rawValue >= CapabilityLevel.extended.rawValue
        case .hsiFusionVectorAccess:
            return capabilities.hsi.rawValue >= CapabilityLevel.research.rawValue

        // Cloud features
        case .cloudBasicIngest:
            return capabilities.cloud.rawValue >= CapabilityLevel.core.rawValue
        case .cloudExtendedEndpoints:
            return capabilities.cloud.rawValue >= CapabilityLevel.extended.rawValue
        case .cloudResearchEndpoints:
            return capabilities.cloud.rawValue >= CapabilityLevel.research.rawValue
        }
    }

    // MARK: - Module Lifecycle

    override public func onInitialize() async throws {
        // Nothing to initialize
    }

    override public func onStart() async throws {
        // Nothing to start
    }

    override public func onStop() async throws {
        // Nothing to stop
    }

    override public func onDispose() async throws {
        capabilities = nil
        token = nil
        capabilitiesSubject.send(nil)
    }
}

// Extension to add Comparable conformance for enum comparison
extension CapabilityLevel: Comparable {
    public static func < (lhs: CapabilityLevel, rhs: CapabilityLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var rawValue: Int {
        switch self {
        case .none: return 0
        case .core: return 1
        case .extended: return 2
        case .research: return 3
        }
    }
}
