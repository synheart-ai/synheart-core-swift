import Foundation

/// Cache for wear raw samples
///
/// Feature computation is delegated to synheart-engine.
class WearCache {
    private var windowSamples: [WindowType: [WearSample]] = [:]

    /// Add a new sample to the cache
    func addSample(_ sample: WearSample) {
        let now = sample.timestamp

        for windowType in [WindowType.window30s, .window5m, .window1h, .window24h] {
            let windowDuration = getWindowDuration(windowType)
            let cutoffTime = now.addingTimeInterval(-windowDuration)

            if windowSamples[windowType] == nil {
                windowSamples[windowType] = []
            }

            windowSamples[windowType]?.append(sample)
            windowSamples[windowType]?.removeAll { $0.timestamp < cutoffTime }
        }
    }

    /// Get raw samples for a specific window
    func getSamples(_ window: WindowType) -> [WearSample] {
        return windowSamples[window] ?? []
    }

    /// Clear old data
    func clearOldData() {
        let now = Date()

        for windowType in [WindowType.window30s, .window5m, .window1h, .window24h] {
            let windowDuration = getWindowDuration(windowType)
            let cutoffTime = now.addingTimeInterval(-windowDuration * 2)

            windowSamples[windowType]?.removeAll { $0.timestamp < cutoffTime }
        }
    }

    private func getWindowDuration(_ window: WindowType) -> TimeInterval {
        switch window {
        case .window30s: return 30
        case .window5m: return 5 * 60
        case .window1h: return 60 * 60
        case .window24h: return 24 * 60 * 60
        }
    }
}
