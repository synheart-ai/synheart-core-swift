import Foundation
import Combine

/// Focus Head: Populates focus state in HSV using synheart_focus module
public class FocusHead {
    private let focusModel: FocusModelProtocol
    private let finalHsvSubject = CurrentValueSubject<HSV?, Never>(nil)
    public var finalHsvPublisher: AnyPublisher<HSV, Never> {
        finalHsvSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let processingQueue = DispatchQueue(label: "com.synheart.hsi.focushead", qos: .userInitiated)
    
    public init(focusModel: FocusModelProtocol? = nil) {
        self.focusModel = focusModel ?? PlaceholderFocusModel()
    }
    
    /// Subscribe to HSV with emotion from Emotion Head
    public func subscribe(to hsvWithEmotionPublisher: AnyPublisher<HSV, Never>) {
        hsvWithEmotionPublisher
            .sink { [weak self] hsv in
                self?.processHSV(hsv)
            }
            .store(in: &cancellables)
    }
    
    private func processHSV(_ hsv: HSV) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            Task {
                do {
                    // Extract features from HSV (including emotion)
                    let features = self.extractFeatures(from: hsv)
                    
                    // Predict focus using model
                    let focusPredictions = try await self.focusModel.predict(features: features)
                    
                    // Create focus state
                    let focusState = FocusState(
                        score: focusPredictions["score"] ?? 0.0,
                        cognitiveLoad: focusPredictions["cognitive_load"] ?? 0.0,
                        clarity: focusPredictions["clarity"] ?? 0.0,
                        distraction: focusPredictions["distraction"] ?? 0.0
                    )
                    
                    // Create final HSV with focus populated
                    var finalHsv = hsv
                    finalHsv.focus = focusState
                    
                    // Emit final HSV
                    await MainActor.run {
                        self.finalHsvSubject.send(finalHsv)
                    }
                } catch {
                    // On error, emit HSV without focus (or with default focus)
                    print("Error predicting focus: \(error)")
                    await MainActor.run {
                        self.finalHsvSubject.send(hsv)
                    }
                }
            }
        }
    }
    
    /// Extract features from HSV for focus prediction
    private func extractFeatures(from hsv: HSV) -> [String: Float] {
        var features: [String: Float] = [:]
        
        // Embedding features
        if let embedding = hsv.hsiEmbedding {
            for (index, value) in embedding.enumerated() {
                features["embedding_\(index)"] = value
            }
        }
        
        // Behavioral features
        if let typingRate = hsv.behavior?.typingRate {
            features["typing_rate"] = typingRate
        }
        
        if let scrollingRate = hsv.behavior?.scrollingRate {
            features["scrolling_rate"] = scrollingRate
        }
        
        if let appSwitchRate = hsv.behavior?.appSwitchRate {
            features["app_switch_rate"] = appSwitchRate
        }
        
        // Emotion features
        if let emotion = hsv.emotion {
            features["stress"] = emotion.stress
            features["calm"] = emotion.calm
            features["engagement"] = emotion.engagement
            features["activation"] = emotion.activation
            features["valence"] = emotion.valence
        }
        
        return features
    }
}

