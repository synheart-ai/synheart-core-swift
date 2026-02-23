import Foundation

/// Human State Vector - the main data structure representing human state.
///
/// Aligned with synheart-flux. The HSV is the canonical internal
/// representation fusing physiology, behavior, and context modalities.
/// External consumers receive HSI JSON (via synheart-runtime), never HSV directly.
///
/// This is the shared "state bus" that all Synheart components consume:
/// - Core produces the base HSV with physiology + behavior + context
/// - Emotion Head (via synheart-emotion SDK) populates `emotion`
/// - Focus Head (via synheart-focus SDK) populates `focus`
/// - synheart-runtime exports HSV → HSI 1.0 with `ExportPolicy` filtering
public struct HumanStateVector: Codable {
    // Physiology domain — wearable-derived readings with per-axis confidence
    public var physiology: PhysiologyState

    // Raw biometric signals (retained for backward compatibility / feature extraction)
    public var heartRate: Float?
    public var heartRateVariability: Float?
    public var rmssd: Float?
    public var sdnn: Float?

    // Behavioral metrics
    public var behavior: BehaviorState?

    // Context information
    public var context: ContextState?

    // Emotion state (populated by synheart-emotion SDK via Emotion Head)
    public var emotion: EmotionState?

    // Focus state (populated by synheart-focus SDK via Focus Head)
    public var focus: FocusState?

    // Metadata
    public var meta: MetaState

    // Embedding representation (latent space)
    public var hsiEmbedding: [Float]?

    // Quality and provenance
    public var stateQuality: StateQuality
    public var provenance: ProvenanceInfo

    public init(physiology: PhysiologyState = .empty,
                heartRate: Float? = nil,
                heartRateVariability: Float? = nil,
                rmssd: Float? = nil,
                sdnn: Float? = nil,
                behavior: BehaviorState? = nil,
                context: ContextState? = nil,
                emotion: EmotionState? = nil,
                focus: FocusState? = nil,
                meta: MetaState,
                hsiEmbedding: [Float]? = nil,
                stateQuality: StateQuality = .empty,
                provenance: ProvenanceInfo = .empty) {
        self.physiology = physiology
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
        self.stateQuality = stateQuality
        self.provenance = provenance
    }
}

// Type alias for convenience
public typealias HSV = HumanStateVector
