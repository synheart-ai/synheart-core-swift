import Foundation

/// Capability levels for module features
public enum CapabilityLevel {
    /// No access
    case none

    /// Core features only
    case core

    /// Extended features
    case extended

    /// Research-level features (internal only)
    case research
}

/// Module identifiers
public enum Module {
    case wear
    case phone
    case behavior
    case hsi
    case cloud
}

/// Feature flags for fine-grained control
public enum FeatureFlag {
    // Wear features
    case wearDerivedMetrics
    case wearHighFrequencyHrv
    case wearRawRrIntervals

    // Phone features
    case phoneMotionAndScreen
    case phoneHashedAppSwitching
    case phoneDetailedAppContext
    case phoneRawNotificationStructure

    // Behavior features
    case behaviorBasicMetrics
    case behaviorExtendedPatterns
    case behaviorFullTimingStream

    // HSI features
    case hsiEmotionFocus
    case hsiFullEmbedding
    case hsiFusionVectorAccess

    // Cloud features
    case cloudBasicIngest
    case cloudExtendedEndpoints
    case cloudResearchEndpoints
}

/// Provider interface for capability checking
public protocol CapabilityProvider: AnyObject {
    /// Get the capability level for a specific module
    func capability(_ module: Module) -> CapabilityLevel

    /// Check if a specific feature is enabled
    func isEnabled(_ feature: FeatureFlag) -> Bool

    /// Check if a module can access a specific feature
    func canAccessFeature(moduleId: String, featureId: String) -> Bool

    /// Get all capabilities as a dictionary
    func getAllCapabilities() -> [Module: CapabilityLevel]
}
