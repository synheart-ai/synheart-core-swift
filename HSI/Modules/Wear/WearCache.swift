import Foundation

/// Cache for wear window features
///
/// Maintains aggregated biosignal features for different time windows
class WearCache {
    private var windowSamples: [WindowType: [WearSample]] = [:]
    private var cachedFeatures: [WindowType: WearWindowFeatures] = [:]
    
    /// Add a new sample to the cache
    func addSample(_ sample: WearSample) {
        let now = sample.timestamp
        
        // Add to each window type
        for windowType in [WindowType.window30s, .window5m, .window1h, .window24h] {
            let windowDuration = getWindowDuration(windowType)
            let cutoffTime = now.addingTimeInterval(-windowDuration)
            
            // Initialize if needed
            if windowSamples[windowType] == nil {
                windowSamples[windowType] = []
            }
            
            // Add new sample
            windowSamples[windowType]?.append(sample)
            
            // Remove old samples
            windowSamples[windowType]?.removeAll { $0.timestamp < cutoffTime }
            
            // Recompute features for this window
            if let samples = windowSamples[windowType] {
                cachedFeatures[windowType] = computeFeatures(windowType, samples: samples)
            }
        }
    }
    
    /// Get features for a specific window
    func getFeatures(_ window: WindowType) -> WearWindowFeatures? {
        return cachedFeatures[window]
    }
    
    /// Clear old data
    func clearOldData() {
        let now = Date()
        
        for windowType in [WindowType.window30s, .window5m, .window1h, .window24h] {
            let windowDuration = getWindowDuration(windowType)
            let cutoffTime = now.addingTimeInterval(-windowDuration * 2) // Keep 2x window
            
            windowSamples[windowType]?.removeAll { $0.timestamp < cutoffTime }
        }
    }
    
    // MARK: - Private Helpers
    
    private func getWindowDuration(_ window: WindowType) -> TimeInterval {
        switch window {
        case .window30s: return 30
        case .window5m: return 5 * 60
        case .window1h: return 60 * 60
        case .window24h: return 24 * 60 * 60
        }
    }
    
    private func computeFeatures(_ window: WindowType, samples: [WearSample]) -> WearWindowFeatures {
        let windowDuration = getWindowDuration(window)
        
        guard !samples.isEmpty else {
            return WearWindowFeatures(windowDuration: windowDuration)
        }
        
        // Compute HR statistics
        let hrValues = samples.compactMap { $0.hr }
        let hrAverage = hrValues.isEmpty ? nil : hrValues.reduce(0, +) / Double(hrValues.count)
        let hrMin = hrValues.isEmpty ? nil : hrValues.min()
        let hrMax = hrValues.isEmpty ? nil : hrValues.max()
        
        // Compute HRV
        let hrvValues = samples.compactMap { $0.hrvRmssd }
        let hrvRmssd = hrvValues.isEmpty ? nil : hrvValues.reduce(0, +) / Double(hrvValues.count)
        
        // Compute motion
        let motionValues = samples.compactMap { $0.motionLevel }
        let motionIndex = motionValues.isEmpty ? nil : motionValues.reduce(0, +) / Double(motionValues.count)
        
        // Compute respiration
        let respValues = samples.compactMap { $0.respRate }
        let respRate = respValues.isEmpty ? nil : respValues.reduce(0, +) / Double(respValues.count)
        
        // Get most common sleep stage
        let sleepStages = samples.compactMap { $0.sleepStage }
        let sleepStage = sleepStages.isEmpty ? nil : mostCommon(sleepStages)
        
        return WearWindowFeatures(
            windowDuration: windowDuration,
            hrAverage: hrAverage,
            hrMin: hrMin,
            hrMax: hrMax,
            hrvRmssd: hrvRmssd,
            motionIndex: motionIndex,
            sleepStage: sleepStage,
            respRate: respRate
        )
    }
    
    private func mostCommon<T: Hashable>(_ items: [T]) -> T? {
        let counts = Dictionary(grouping: items, by: { $0 }).mapValues { $0.count }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

