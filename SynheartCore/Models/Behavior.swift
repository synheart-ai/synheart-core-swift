import Foundation

/// Behavioral metrics state
public struct BehaviorState: Codable {
    public let typingRate: Float?
    public let scrollingRate: Float?
    public let appSwitchRate: Float?
    public let interactionIntensity: Float?
    
    public init(typingRate: Float? = nil,
                scrollingRate: Float? = nil,
                appSwitchRate: Float? = nil,
                interactionIntensity: Float? = nil) {
        self.typingRate = typingRate
        self.scrollingRate = scrollingRate
        self.appSwitchRate = appSwitchRate
        self.interactionIntensity = interactionIntensity
    }
}

