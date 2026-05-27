import Foundation

/// Aggregates behavior events into time windows
class WindowAggregator {
    private var windows: [WindowType: [BehaviorEvent]] = [:]
    
    /// Add an event to all windows
    func addEvent(_ event: BehaviorEvent) {
        let now = event.timestamp
        
        for windowType in [WindowType.window30s, .window5m, .window1h, .window24h] {
            let windowDuration = getWindowDuration(windowType)
            let cutoffTime = now.addingTimeInterval(-windowDuration)
            
            // Initialize if needed
            if windows[windowType] == nil {
                windows[windowType] = []
            }
            
            // Add event
            windows[windowType]?.append(event)
            
            // Remove old events
            windows[windowType]?.removeAll { $0.timestamp < cutoffTime }
        }
    }
    
    /// Get events for a window
    func getEvents(_ window: WindowType) -> [BehaviorEvent] {
        return windows[window] ?? []
    }
    
    /// Clean old windows (call periodically)
    func cleanOldWindows() {
        let now = Date()
        
        for windowType in [WindowType.window30s, .window5m, .window1h, .window24h] {
            let windowDuration = getWindowDuration(windowType)
            let cutoffTime = now.addingTimeInterval(-windowDuration * 2) // Keep 2x window
            
            windows[windowType]?.removeAll { $0.timestamp < cutoffTime }
        }
    }
    
    /// Get window duration
    private func getWindowDuration(_ windowType: WindowType) -> TimeInterval {
        switch windowType {
        case .window30s: return 30
        case .window5m: return 5 * 60
        case .window1h: return 60 * 60
        case .window24h: return 24 * 60 * 60
        }
    }
}

