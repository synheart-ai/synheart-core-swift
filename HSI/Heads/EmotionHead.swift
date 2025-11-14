import Foundation
import Combine

/// Emotion Head: Populates emotion state in HSV using synheart_emotion module
public class EmotionHead {
    private let emotionModel: EmotionModelProtocol
    private let hsvWithEmotionSubject = CurrentValueSubject<HSV?, Never>(nil)
    public var hsvWithEmotionPublisher: AnyPublisher<HSV, Never> {
        hsvWithEmotionSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let processingQueue = DispatchQueue(label: "com.synheart.hsi.emotionhead", qos: .userInitiated)
    
    public init(emotionModel: EmotionModelProtocol? = nil) {
        self.emotionModel = emotionModel ?? PlaceholderEmotionModel()
    }
    
    /// Subscribe to base HSV from State Engine
    public func subscribe(to baseHsvPublisher: AnyPublisher<HSV, Never>) {
        baseHsvPublisher
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
                    // Extract features from HSV
                    let features = self.extractFeatures(from: hsv)
                    
                    // Predict emotion using model
                    let emotionPredictions = try await self.emotionModel.predict(features: features)
                    
                    // Create emotion state
                    let emotionState = EmotionState(
                        stress: emotionPredictions["stress"] ?? 0.0,
                        calm: emotionPredictions["calm"] ?? 0.0,
                        engagement: emotionPredictions["engagement"] ?? 0.0,
                        activation: emotionPredictions["activation"] ?? 0.0,
                        valence: emotionPredictions["valence"] ?? 0.0
                    )
                    
                    // Create HSV with emotion populated
                    var hsvWithEmotion = hsv
                    hsvWithEmotion.emotion = emotionState
                    
                    // Emit updated HSV
                    await MainActor.run {
                        self.hsvWithEmotionSubject.send(hsvWithEmotion)
                    }
                } catch {
                    // On error, emit HSV without emotion (or with default emotion)
                    print("Error predicting emotion: \(error)")
                    await MainActor.run {
                        self.hsvWithEmotionSubject.send(hsv)
                    }
                }
            }
        }
    }
    
    /// Extract features from HSV for emotion prediction
    private func extractFeatures(from hsv: HSV) -> [String: Float] {
        var features: [String: Float] = [:]
        
        // Embedding features
        if let embedding = hsv.hsiEmbedding {
            for (index, value) in embedding.enumerated() {
                features["embedding_\(index)"] = value
            }
        }
        
        // Heart rate features
        if let hr = hsv.heartRate {
            features["heart_rate"] = hr
        }
        
        if let hrv = hsv.heartRateVariability {
            features["hrv"] = hrv
        }
        
        if let rmssd = hsv.rmssd {
            features["rmssd"] = rmssd
        }
        
        if let sdnn = hsv.sdnn {
            features["sdnn"] = sdnn
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
        
        // Context features
        if let isInConversation = hsv.context?.conversation.isInConversation {
            features["in_conversation"] = isInConversation ? 1.0 : 0.0
        }
        
        return features
    }
}

