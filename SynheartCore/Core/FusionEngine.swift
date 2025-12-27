import Foundation
import Combine

/// Fuses processed signals into base HSV with embedding representation
public class FusionEngine {
    private let hsvSubject = CurrentValueSubject<HSV?, Never>(nil)
    public var hsvPublisher: AnyPublisher<HSV, Never> {
        hsvSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    private let deviceInfo = DeviceInfo()
    private var sessionId = UUID().uuidString
    private let contextAdapter: ContextAdapter?
    private let embeddingModel: EmbeddingModelProtocol

    /// Initialize fusion engine
    /// - Parameters:
    ///   - contextAdapter: Optional context adapter for context information
    ///   - embeddingModel: Optional embedding model (defaults to placeholder)
    public init(contextAdapter: ContextAdapter? = nil,
                embeddingModel: EmbeddingModelProtocol? = nil) {
        self.contextAdapter = contextAdapter
        self.embeddingModel = embeddingModel ?? PlaceholderEmbeddingModel()
    }
    
    /// Fuse processed signals into base HSV
    public func fuse(_ processed: ProcessedSignals) {
        // Generate embedding using model
        let embedding: [Float]
        do {
            embedding = try embeddingModel.generateEmbedding(from: processed)
        } catch {
            print("Error generating embedding: \(error)")
            embedding = [] // Fallback to empty embedding
        }

        // Get current context if available
        let context = contextAdapter?.currentContext

        // Create base HSV
        let hsv = HSV(
            heartRate: processed.heartRate,
            heartRateVariability: processed.heartRateVariability,
            rmssd: processed.rmssd,
            sdnn: processed.sdnn,
            behavior: BehaviorState(
                typingRate: processed.typingRate,
                scrollingRate: processed.scrollingRate,
                appSwitchRate: processed.appSwitchRate
            ),
            context: context,
            emotion: nil, // Will be populated by Emotion Head
            focus: nil, // Will be populated by Focus Head
            meta: MetaState(
                device: deviceInfo,
                sessionId: sessionId,
                timestamp: Date(),
                embeddings: embedding
            ),
            hsiEmbedding: embedding
        )

        hsvSubject.send(hsv)
    }
    
    
    /// Reset session (call when starting a new session)
    public func resetSession() {
        sessionId = UUID().uuidString
    }
}

