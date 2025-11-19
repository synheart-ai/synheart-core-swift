import Foundation

/// Fusion Engine V2
///
/// Combines features from all modules into a base HSV
public class FusionEngineV2 {
    /// Fuse collected features into base HSV
    public func fuse(
        _ features: CollectedFeatures,
        window: WindowType,
        timestamp: Int64
    ) async -> HumanStateVector {
        // Build fused feature vector
        let fusedVector = buildFusedVector(features)
        
        // Run embedding model (placeholder for now)
        let embedding = await computeEmbedding(fusedVector)
        
        // Create behavior state
        let behavior = buildBehaviorState(features.behavior)
        
        // Create context state
        let context = buildContextState(features.phone)
        
        // Create meta state
        let meta = MetaState(
            device: DeviceInfo(platform: "ios"),
            sessionId: "sess-\(timestamp)",
            timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0),
            embeddings: embedding
        )
        
        // Create base HSV (emotion and focus will be populated by heads)
        return HumanStateVector(
            heartRate: features.wear?.hrAverage.map { Float($0) },
            heartRateVariability: features.wear?.hrvRmssd.map { Float($0) },
            rmssd: features.wear?.hrvRmssd.map { Float($0) },
            sdnn: nil,
            behavior: behavior,
            context: context,
            emotion: nil, // Will be populated by EmotionHead
            focus: nil, // Will be populated by FocusHead
            meta: meta,
            hsiEmbedding: embedding
        )
    }
    
    /// Build fused feature vector from collected features
    private func buildFusedVector(_ features: CollectedFeatures) -> [Double] {
        var vector: [Double] = []
        
        // Wear features (biosignals)
        if let wear = features.wear {
            vector.append(wear.hrAverage ?? 0.0)
            vector.append(wear.hrvRmssd ?? 0.0)
            vector.append(wear.motionIndex ?? 0.0)
            vector.append(wear.respRate ?? 0.0)
        } else {
            vector.append(contentsOf: [0.0, 0.0, 0.0, 0.0])
        }
        
        // Phone features (context)
        if let phone = features.phone {
            vector.append(phone.motionLevel)
            vector.append(phone.screenOnRatio)
            vector.append(phone.appSwitchRate)
            vector.append(phone.notificationRate)
        } else {
            vector.append(contentsOf: [0.0, 0.0, 0.0, 0.0])
        }
        
        // Behavior features
        if let behavior = features.behavior {
            vector.append(behavior.tapRateNorm)
            vector.append(behavior.keystrokeRateNorm)
            vector.append(behavior.scrollVelocityNorm)
            vector.append(behavior.idleRatio)
            vector.append(behavior.switchRateNorm)
            vector.append(behavior.burstiness)
            vector.append(behavior.sessionFragmentation)
            vector.append(behavior.notificationLoad)
        } else {
            vector.append(contentsOf: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
        }
        
        return vector
    }
    
    /// Compute embedding from fused vector (placeholder)
    private func computeEmbedding(_ fusedVector: [Double]) async -> [Float] {
        // TODO: Implement actual embedding model (MLP/Tiny Transformer)
        // For now, return the fused vector padded/truncated to 64D
        if fusedVector.count >= 64 {
            return fusedVector.prefix(64).map { Float($0) }
        } else {
            var result = fusedVector.map { Float($0) }
            result.append(contentsOf: Array(repeating: 0.0, count: 64 - fusedVector.count))
            return result
        }
    }
    
    /// Build behavior state from features
    private func buildBehaviorState(_ features: BehaviorWindowFeatures?) -> BehaviorState? {
        guard let features = features else {
            return BehaviorState()
        }
        
        return BehaviorState(
            typingRate: Float(features.keystrokeRateNorm),
            scrollingRate: Float(features.scrollVelocityNorm),
            appSwitchRate: Float(features.switchRateNorm),
            interactionIntensity: Float(1.0 - features.idleRatio)
        )
    }
    
    /// Build context state from phone features
    private func buildContextState(_ features: PhoneWindowFeatures?) -> ContextState {
        // Placeholder context state
        return ContextState(
            conversation: ConversationContext(),
            device: DeviceStateContext(
                isCharging: false,
                batteryLevel: nil,
                isScreenOn: features != nil && features!.screenOnRatio > 0.5,
                networkType: nil
            ),
            patterns: UserPatternsContext()
        )
    }
    
    /// Get sampling rate for window type
    private func getSamplingRate(_ window: WindowType) -> Double {
        switch window {
        case .window30s:
            return 2.0 // 2 Hz
        case .window5m:
            return 0.2 // 0.2 Hz
        case .window1h:
            return 1.0 / 3600 // 1 sample per hour
        case .window24h:
            return 1.0 / 86400 // 1 sample per day
        }
    }
}

