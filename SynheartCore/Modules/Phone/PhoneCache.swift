import Foundation

/// Cache for phone raw data points
///
class PhoneCache {
    private var windowData: [WindowType: [PhoneDataPoint]] = [:]

    /// Add motion data
    func addMotionData(_ motion: MotionData) {
        addDataPoint(PhoneDataPoint(
            timestamp: motion.timestamp,
            motionLevel: motion.energy / 3.0,
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

    /// Get raw data points for a window
    func getDataPoints(_ window: WindowType) -> [PhoneDataPoint] {
        return windowData[window] ?? []
    }

    /// Add a data point to all windows
    private func addDataPoint(_ point: PhoneDataPoint) {
        let now = point.timestamp

        for windowType in [WindowType.window30s, .window5m, .window1h, .window24h] {
            let windowDuration = getWindowDuration(windowType)
            let cutoffTime = now.addingTimeInterval(-windowDuration)

            if windowData[windowType] == nil {
                windowData[windowType] = []
            }

            windowData[windowType]?.append(point)
            windowData[windowType]?.removeAll { $0.timestamp < cutoffTime }
        }
    }

    private func getWindowDuration(_ windowType: WindowType) -> TimeInterval {
        switch windowType {
        case .window30s: return 30
        case .window5m: return 5 * 60
        case .window1h: return 60 * 60
        case .window24h: return 24 * 60 * 60
        }
    }
}

/// Data point for phone data
public struct PhoneDataPoint {
    public let timestamp: Date
    public let motionLevel: Double?
    public let screenOn: Bool?
    public let appSwitch: Bool?
    public let notification: Bool?

    public init(
        timestamp: Date,
        motionLevel: Double? = nil,
        screenOn: Bool? = nil,
        appSwitch: Bool? = nil,
        notification: Bool? = nil
    ) {
        self.timestamp = timestamp
        self.motionLevel = motionLevel
        self.screenOn = screenOn
        self.appSwitch = appSwitch
        self.notification = notification
    }
}
