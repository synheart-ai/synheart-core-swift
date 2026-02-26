import Foundation

/// Human State Vector - INTERNAL ONLY
///
/// The HSV is an intermediate representation computed by synheart-runtime.
/// It contains per-head inference results (emotion, focus, capacity, etc.)
/// with confidence and metadata.
///
/// This is NOT part of the public API - consumers use HSI instead.
/// Used internally for quality assessment, diagnostics, and SRM baselines.
public struct HumanStateVector: Codable {
    public let timestamp: Int64
    public let meta: MetaState
    public let physiology: PhysiologyState
    public let heartRate: Float?
    public let hrvRmssd: Float?
    public let hrvSdnn: Float?
    public let hsiEmbedding: [Float]
    public let behavior: BehaviorState?
    public let context: ContextState?
    public let stateQuality: StateQuality
    public let provenance: ProvenanceInfo

    public init(
        timestamp: Int64,
        meta: MetaState,
        physiology: PhysiologyState = .empty,
        heartRate: Float? = nil,
        hrvRmssd: Float? = nil,
        hrvSdnn: Float? = nil,
        hsiEmbedding: [Float] = [],
        behavior: BehaviorState? = nil,
        context: ContextState? = nil,
        stateQuality: StateQuality = .empty,
        provenance: ProvenanceInfo = .empty
    ) {
        self.timestamp = timestamp
        self.meta = meta
        self.physiology = physiology
        self.heartRate = heartRate
        self.hrvRmssd = hrvRmssd
        self.hrvSdnn = hrvSdnn
        self.hsiEmbedding = hsiEmbedding
        self.behavior = behavior
        self.context = context
        self.stateQuality = stateQuality
        self.provenance = provenance
    }
}

// Convenience alias
public typealias HSV = HumanStateVector
