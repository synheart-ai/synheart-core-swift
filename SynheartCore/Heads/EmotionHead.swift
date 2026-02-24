import Foundation
import Combine

/// Emotion Head: Populates emotion state in HSV.
///
/// Delegates inference to an external `EmotionModelProtocol` implementation,
/// which is provided by the synheart-emotion SDK (synheart-emotion-swift).
/// The Core SDK does NOT perform emotion inference itself — it only orchestrates
/// the pipeline:
///
/// ```
/// Base HSV → EmotionHead → [EmotionModelProtocol.predict()] → HSV + emotion
/// ```
///
/// To integrate:
/// 1. Add synheart-emotion-swift as a dependency
/// 2. Pass its EmotionModelProtocol implementation to EmotionHead init
/// 3. EmotionHead extracts features from HSV and delegates to the model
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
                    let features = self.extractFeatures(from: hsv)
                    let emotionPredictions = try await self.emotionModel.predict(features: features)

                    let emotionState = EmotionState(
                        stress: emotionPredictions["stress"] ?? 0.0,
                        calm: emotionPredictions["calm"] ?? 0.0,
                        engagement: emotionPredictions["engagement"] ?? 0.0,
                        activation: emotionPredictions["activation"] ?? 0.0,
                        valence: emotionPredictions["valence"] ?? 0.0
                    )

                    var hsvWithEmotion = hsv
                    hsvWithEmotion.emotion = emotionState

                    await MainActor.run {
                        self.hsvWithEmotionSubject.send(hsvWithEmotion)
                    }
                } catch {
                    SynheartLogger.log("Error predicting emotion: \(error)")
                    await MainActor.run {
                        self.hsvWithEmotionSubject.send(hsv)
                    }
                }
            }
        }
    }

    /// Extract features from HSV for emotion prediction.
    /// Includes physiology (from wearable), behavioral, and context signals.
    private func extractFeatures(from hsv: HSV) -> [String: Float] {
        var features: [String: Float] = [:]

        // Embedding features
        if let embedding = hsv.hsiEmbedding {
            for (index, value) in embedding.enumerated() {
                features["embedding_\(index)"] = value
            }
        }

        // Heart rate features (raw biosignals)
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

        // Physiology features (from PhysiologyState — synheart-runtime)
        if let score = hsv.physiology.recoveryScore.score {
            features["recovery_score"] = score
        }
        if let score = hsv.physiology.sleepEfficiency.score {
            features["sleep_efficiency"] = score
        }
        if let score = hsv.physiology.hrvDeviation.score {
            features["hrv_deviation"] = score
        }
        if let score = hsv.physiology.strain.score {
            features["strain"] = score
        }

        // Behavioral features
        if let typingSpeed = hsv.behavior?.typingSpeed {
            features["typing_rate"] = typingSpeed
        }
        if let scrollVelocity = hsv.behavior?.scrollVelocity {
            features["scrolling_rate"] = scrollVelocity
        }
        if let appSwitchRate = hsv.behavior?.appSwitchRate {
            features["app_switch_rate"] = appSwitchRate
        }

        // Context features
        if let isActive = hsv.context?.conversation?.isActive {
            features["in_conversation"] = isActive ? 1.0 : 0.0
        }

        return features
    }
}
