import Foundation

/// Cache for phone window features
class PhoneCache {
    private var windowData: [WindowType: [PhoneDataPoint]] = [:]
    private var cachedFeatures: [WindowType: PhoneWindowFeatures] = [:]
    
    /// Add motion data
    func addMotionData(_ motion: MotionData) {
        addDataPoint(PhoneDataPoint(
            timestamp: motion.timestamp,
            motionLevel: motion.energy / 3.0, // Normalize to 0-1
            screenOn: nil,
            appSwitch: nil,
            notification: nil
        ))
    }
    
    /// Add screen state change
    func addScreenState(_ state: ScreenState, timestamp: Date) {
        addDataPoint(PhoneDataPoint(
            timestamp: timestamp,
            motionLevel: nil,
            screenOn: state == .on || state == .unlocked,
            appSwitch: nil,
            notification: nil
        ))
    }
    
    /// Add app switch event
    func addAppSwitch(timestamp: Date) {
        addDataPoint(PhoneDataPoint(
            timestamp: timestamp,
            motionLevel: nil,
            screenOn: nil,
            appSwitch: true,
            notification: nil
        ))
    }
    
    /// Add notification event
    func addNotification(_ event: NotificationEvent) {
        addDataPoint(PhoneDataPoint(
            timestamp: event.timestamp,
            motionLevel: nil,
            screenOn: nil,
            appSwitch: nil,
            notification: true
        ))
    }
    
    /// Get features for a window
    func getFeatures(_ window: WindowType) -> PhoneWindowFeatures? {
        return cachedFeatures[window]
    }
    
    /// Add a data point and recompute features
    private func addDataPoint(_ point: PhoneDataPoint) {
        let now = point.timestamp
        
        for windowType in [WindowType.window30s, .window5m, .window1h, .window24h] {
            let windowDuration = getWindowDuration(windowType)
            let cutoffTime = now.addingTimeInterval(-windowDuration)
            
            // Initialize if needed
            if windowData[windowType] == nil {
                windowData[windowType] = []
            }
            
            // Add new point
            windowData[windowType]?.append(point)
            
            // Remove old points
            windowData[windowType]?.removeAll { $0.timestamp < cutoffTime }
            
            // Recompute features
            if let data = windowData[windowType] {
                cachedFeatures[windowType] = computeFeatures(windowType, data: data)
            }
        }
    }
    
    /// Compute features from data points
    private func computeFeatures(_ windowType: WindowType, data: [PhoneDataPoint]) -> PhoneWindowFeatures {
        if data.isEmpty {
            return PhoneWindowFeatures(
                motionLevel: 0.0,
                appSwitchRate: 0.0,
                screenOnRatio: 0.0,
                notificationRate: 0.0
            )
        }
        
        // Motion level (average)
        let motionValues = data.compactMap { $0.motionLevel }
        let motionLevel = motionValues.isEmpty ? 0.0 : motionValues.reduce(0, +) / Double(motionValues.count)
        
        // Screen on ratio
        let screenOnCount = data.filter { $0.screenOn == true }.count
        let screenOnRatio = data.isEmpty ? 0.0 : Double(screenOnCount) / Double(data.count)
        
        // App switch rate (switches per minute)
        let appSwitches = data.filter { $0.appSwitch == true }.count
        let windowMinutes = getWindowDuration(windowType) / 60.0
        let appSwitchRate = windowMinutes > 0 ? Double(appSwitches) / windowMinutes : 0.0
        
        // Notification rate (per minute)
        let notifications = data.filter { $0.notification == true }.count
        let notificationRate = windowMinutes > 0 ? Double(notifications) / windowMinutes : 0.0
        
        return PhoneWindowFeatures(
            motionLevel: motionLevel,
            appSwitchRate: min(1.0, max(0.0, appSwitchRate)),
            screenOnRatio: screenOnRatio,
            notificationRate: min(1.0, max(0.0, notificationRate))
        )
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

/// Internal data point for phone data
private struct PhoneDataPoint {
    let timestamp: Date
    let motionLevel: Double?
    let screenOn: Bool?
    let appSwitch: Bool?
    let notification: Bool?
}

