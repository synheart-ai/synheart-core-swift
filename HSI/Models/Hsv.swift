import Foundation

/// Human State Vector - the main data structure representing human state
public struct HumanStateVector: Codable {
    // Core biometric signals
    public var heartRate: Float?
    public var heartRateVariability: Float?
    public var rmssd: Float?
    public var sdnn: Float?
    
    // Behavioral metrics
    public var behavior: BehaviorState?
    
    // Context information
    public var context: ContextState?
    
    // Emotion state (populated by Emotion Head)
    public var emotion: EmotionState?
    
    // Focus state (populated by Focus Head)
    public var focus: FocusState?
    
    // Metadata
    public var meta: MetaState
    
    // Embedding representation (latent space)
    public var hsiEmbedding: [Float]?
    
    public init(heartRate: Float? = nil,
                heartRateVariability: Float? = nil,
                rmssd: Float? = nil,
                sdnn: Float? = nil,
                behavior: BehaviorState? = nil,
                context: ContextState? = nil,
                emotion: EmotionState? = nil,
                focus: FocusState? = nil,
                meta: MetaState,
                hsiEmbedding: [Float]? = nil) {
        self.heartRate = heartRate
        self.heartRateVariability = heartRateVariability
        self.rmssd = rmssd
        self.sdnn = sdnn
        self.behavior = behavior
        self.context = context
        self.emotion = emotion
        self.focus = focus
        self.meta = meta
        self.hsiEmbedding = hsiEmbedding
    }
}

// Type alias for convenience
public typealias HSV = HumanStateVector

