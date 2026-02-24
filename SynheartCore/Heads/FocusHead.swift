import Foundation
import Combine

/// Focus Head: Populates focus state in HSV.
///
/// Delegates inference to an external `FocusModelProtocol` implementation,
/// which is provided by the synheart-focus SDK (synheart-focus-swift).
/// The Core SDK does NOT perform focus inference itself — it only orchestrates
/// the pipeline:
///
/// ```
/// HSV + emotion → FocusHead → [FocusModelProtocol.predict()] → HSV + focus
/// ```
///
/// To integrate:
/// 1. Add synheart-focus-swift as a dependency
/// 2. Pass its FocusModelProtocol implementation to FocusHead init
/// 3. FocusHead extracts features from HSV (including emotion) and delegates to the model
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
                    let features = self.extractFeatures(from: hsv)
                    let focusPredictions = try await self.focusModel.predict(features: features)

                    let focusState = FocusState(
                        score: focusPredictions["score"] ?? 0.0,
                        cognitiveLoad: focusPredictions["cognitive_load"] ?? 0.0,
                        clarity: focusPredictions["clarity"] ?? 0.0,
                        distraction: focusPredictions["distraction"] ?? 0.0
                    )

                    var finalHsv = hsv
                    finalHsv.focus = focusState

                    await MainActor.run {
                        self.finalHsvSubject.send(finalHsv)
                    }
                } catch {
                    print("Error predicting focus: \(error)")
                    await MainActor.run {
                        self.finalHsvSubject.send(hsv)
                    }
                }
            }
        }
    }

    /// Extract features from HSV for focus prediction.
    /// Includes emotion state, physiology, behavioral, and context signals.
    private func extractFeatures(from hsv: HSV) -> [String: Float] {
        var features: [String: Float] = [:]

        // Embedding features
        if let embedding = hsv.hsiEmbedding {
            for (index, value) in embedding.enumerated() {
                features["embedding_\(index)"] = value
            }
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

        // Emotion features (from Emotion Head)
        if let emotion = hsv.emotion {
            features["stress"] = emotion.stress
            features["calm"] = emotion.calm
            features["engagement"] = emotion.engagement
            features["activation"] = emotion.activation
            features["valence"] = emotion.valence
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

        return features
    }
}
