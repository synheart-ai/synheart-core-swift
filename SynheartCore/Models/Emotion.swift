import Foundation

/// Emotion state metrics
public struct EmotionState: Codable {
    public let stress: Float
    public let calm: Float
    public let engagement: Float
    public let activation: Float
    public let valence: Float
    
    public init(stress: Float = 0.0,
                calm: Float = 0.0,
                engagement: Float = 0.0,
                activation: Float = 0.0,
                valence: Float = 0.0) {
        self.stress = stress
        self.calm = calm
        self.engagement = engagement
        self.activation = activation
        self.valence = valence
    }
}

