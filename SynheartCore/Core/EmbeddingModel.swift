import Foundation
import CoreML

/// Protocol for embedding generation models
public protocol EmbeddingModelProtocol {
    /// Generate embedding from processed signals
    /// - Parameter signals: Processed signal data
    /// - Returns: Embedding vector
    func generateEmbedding(from signals: ProcessedSignals) throws -> [Float]
}

/// Core ML-based embedding model
@available(iOS 14.0, macOS 11.0, *)
public class CoreMLEmbeddingModel: EmbeddingModelProtocol {
    private let model: MLModel?
    private let inputSize: Int
    private let outputSize: Int

    /// Initialize with Core ML model
    /// - Parameters:
    ///   - modelURL: URL to the compiled .mlmodelc file
    ///   - inputSize: Expected input feature size
    ///   - outputSize: Expected embedding size
    public init(modelURL: URL? = nil, inputSize: Int = 7, outputSize: Int = 128) {
        self.inputSize = inputSize
        self.outputSize = outputSize

        // Try to load the model if URL is provided
        if let url = modelURL {
            do {
                self.model = try MLModel(contentsOf: url)
            } catch {
                print("Failed to load Core ML model: \(error)")
                self.model = nil
            }
        } else {
            self.model = nil
        }
    }

    public func generateEmbedding(from signals: ProcessedSignals) throws -> [Float] {
        guard let model = model else {
            // Fallback to simple feature extraction if no model is loaded
            return generateSimpleEmbedding(from: signals)
        }

        // Prepare input features
        let inputFeatures = prepareInputFeatures(from: signals)

        // Create MLMultiArray for input
        let inputArray = try MLMultiArray(shape: [NSNumber(value: inputSize)], dataType: .float32)
        for (index, value) in inputFeatures.enumerated() {
            if index < inputSize {
                inputArray[index] = NSNumber(value: value)
            }
        }

        // Create feature provider
        let input = try MLDictionaryFeatureProvider(dictionary: ["input": inputArray])

        // Run prediction
        let output = try model.prediction(from: input)

        // Extract embedding from output
        if let embeddingArray = output.featureValue(for: "embedding")?.multiArrayValue {
            var embedding: [Float] = []
            for i in 0..<min(outputSize, embeddingArray.count) {
                embedding.append(Float(truncating: embeddingArray[i]))
            }
            return embedding
        }

        // Fallback if output format is unexpected
        return generateSimpleEmbedding(from: signals)
    }

    private func prepareInputFeatures(from signals: ProcessedSignals) -> [Float] {
        var features: [Float] = []

        // Normalize and add features
        if let hr = signals.heartRate {
            features.append(hr / 200.0) // Normalize to ~0-1 range
        } else {
            features.append(0.0)
        }

        if let hrv = signals.heartRateVariability {
            features.append(hrv / 100.0)
        } else {
            features.append(0.0)
        }

        if let rmssd = signals.rmssd {
            features.append(rmssd / 100.0)
        } else {
            features.append(0.0)
        }

        if let sdnn = signals.sdnn {
            features.append(sdnn / 100.0)
        } else {
            features.append(0.0)
        }

        if let typingRate = signals.typingRate {
            features.append(typingRate / 10.0)
        } else {
            features.append(0.0)
        }

        if let scrollingRate = signals.scrollingRate {
            features.append(scrollingRate / 10.0)
        } else {
            features.append(0.0)
        }

        if let appSwitchRate = signals.appSwitchRate {
            features.append(appSwitchRate / 5.0)
        } else {
            features.append(0.0)
        }

        return features
    }

    private func generateSimpleEmbedding(from signals: ProcessedSignals) -> [Float] {
        // Simple feature-based embedding (no neural network)
        let features = prepareInputFeatures(from: signals)

        // Pad to output size
        var embedding = features
        while embedding.count < outputSize {
            embedding.append(0.0)
        }

        return Array(embedding.prefix(outputSize))
    }
}

/// Placeholder embedding model for testing/development
public class PlaceholderEmbeddingModel: EmbeddingModelProtocol {
    private let outputSize: Int

    public init(outputSize: Int = 128) {
        self.outputSize = outputSize
    }

    public func generateEmbedding(from signals: ProcessedSignals) throws -> [Float] {
        var features: [Float] = []

        // Basic feature extraction
        if let hr = signals.heartRate {
            features.append(hr / 200.0)
        } else {
            features.append(0.0)
        }

        if let hrv = signals.heartRateVariability {
            features.append(hrv / 100.0)
        } else {
            features.append(0.0)
        }

        if let rmssd = signals.rmssd {
            features.append(rmssd / 100.0)
        } else {
            features.append(0.0)
        }

        if let sdnn = signals.sdnn {
            features.append(sdnn / 100.0)
        } else {
            features.append(0.0)
        }

        if let typingRate = signals.typingRate {
            features.append(typingRate / 10.0)
        } else {
            features.append(0.0)
        }

        if let scrollingRate = signals.scrollingRate {
            features.append(scrollingRate / 10.0)
        } else {
            features.append(0.0)
        }

        if let appSwitchRate = signals.appSwitchRate {
            features.append(appSwitchRate / 5.0)
        } else {
            features.append(0.0)
        }

        // Pad to fixed size
        while features.count < outputSize {
            features.append(0.0)
        }

        return Array(features.prefix(outputSize))
    }
}
