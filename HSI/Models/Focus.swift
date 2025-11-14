import Foundation

/// Focus state metrics
public struct FocusState: Codable {
    public let score: Float
    public let cognitiveLoad: Float
    public let clarity: Float
    public let distraction: Float
    
    public init(score: Float = 0.0,
                cognitiveLoad: Float = 0.0,
                clarity: Float = 0.0,
                distraction: Float = 0.0) {
        self.score = score
        self.cognitiveLoad = cognitiveLoad
        self.clarity = clarity
        self.distraction = distraction
    }
}

