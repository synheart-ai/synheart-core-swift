import Foundation

/// Collected features from all modules
public struct CollectedFeatures {
    public let wear: WearWindowFeatures?
    public let phone: PhoneWindowFeatures?
    public let behavior: BehaviorWindowFeatures?
    
    public init(
        wear: WearWindowFeatures? = nil,
        phone: PhoneWindowFeatures? = nil,
        behavior: BehaviorWindowFeatures? = nil
    ) {
        self.wear = wear
        self.phone = phone
        self.behavior = behavior
    }
    
    /// Check if we have any features
    public var hasAnyFeatures: Bool {
        return wear != nil || phone != nil || behavior != nil
    }
}

/// Collects features from all data modules
public class ChannelCollector {
    private weak var wear: WearFeatureProvider?
    private weak var phone: PhoneFeatureProvider?
    private weak var behavior: BehaviorFeatureProvider?
    
    public init(
        wear: WearFeatureProvider? = nil,
        phone: PhoneFeatureProvider? = nil,
        behavior: BehaviorFeatureProvider? = nil
    ) {
        self.wear = wear
        self.phone = phone
        self.behavior = behavior
    }
    
    /// Collect features for a specific window
    public func collect(_ window: WindowType) -> CollectedFeatures {
        return CollectedFeatures(
            wear: wear?.features(window),
            phone: phone?.features(window),
            behavior: behavior?.features(window)
        )
    }
}

