import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Adapter for collecting context information (device state, conversation, user patterns)
public class ContextAdapter {
    private let contextSubject = CurrentValueSubject<ContextState?, Never>(nil)

    public var contextPublisher: AnyPublisher<ContextState, Never> {
        contextSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    private var isRunning = false
    private var updateTimer: AnyCancellable?

    #if canImport(UIKit)
    private var notificationObservers: [NSObjectProtocol] = []
    #endif

    // Conversation state tracking
    private var isInConversation = false
    private var conversationStartTime: Date?

    public init() {}

    /// Start collecting context information
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        startDeviceStateMonitoring()
        startPeriodicContextUpdates()
    }

    /// Stop collecting context information
    public func stop() {
        isRunning = false
        updateTimer?.cancel()
        updateTimer = nil

        #if canImport(UIKit)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        #endif
    }

    /// Get current context state
    public var currentContext: ContextState? {
        contextSubject.value
    }

    // MARK: - Device State Monitoring

    private func startDeviceStateMonitoring() {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Monitor battery state changes
        let batteryStateObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateContext()
        }

        let batteryLevelObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateContext()
        }

        notificationObservers.append(batteryStateObserver)
        notificationObservers.append(batteryLevelObserver)
        #endif

        // Initial update
        updateContext()
    }

    private func startPeriodicContextUpdates() {
        // Update context every 10 seconds
        updateTimer = Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateContext()
            }
    }

    private func updateContext() {
        let deviceState = getCurrentDeviceState()
        let conversationContext = getCurrentConversationContext()
        let patternsContext = getCurrentUserPatternsContext()

        let context = ContextState(
            conversation: conversationContext,
            device: deviceState,
            patterns: patternsContext
        )

        contextSubject.send(context)
    }

    private func getCurrentDeviceState() -> DeviceStateContext {
        #if canImport(UIKit)
        let device = UIDevice.current
        let isCharging = device.batteryState == .charging || device.batteryState == .full
        let batteryLevel = device.batteryLevel >= 0 ? device.batteryLevel : nil

        // Note: Screen state is approximated based on app state
        let isScreenOn = UIApplication.shared.applicationState == .active

        // Network type detection (simplified)
        // In production, you might use Network.framework for more detailed info
        let networkType = "unknown"

        return DeviceStateContext(
            isCharging: isCharging,
            batteryLevel: batteryLevel,
            isScreenOn: isScreenOn,
            networkType: networkType
        )
        #else
        return DeviceStateContext()
        #endif
    }

    private func getCurrentConversationContext() -> ConversationContext {
        let duration = conversationStartTime.map { Date().timeIntervalSince($0) }

        return ConversationContext(
            isInConversation: isInConversation,
            conversationDuration: duration,
            lastInteractionTime: conversationStartTime
        )
    }

    private func getCurrentUserPatternsContext() -> UserPatternsContext {
        let now = Date()
        let calendar = Calendar.current

        // Time of day in seconds since midnight
        let components = calendar.dateComponents([.hour, .minute, .second], from: now)
        let hours = (components.hour ?? 0) * 3600
        let minutes = (components.minute ?? 0) * 60
        let seconds = (components.second ?? 0)
        let timeOfDay = TimeInterval(hours + minutes + seconds)

        // Day of week (1 = Sunday, 7 = Saturday)
        let dayOfWeek = calendar.component(.weekday, from: now)

        // Activity pattern (simplified - could be enhanced with ML)
        let hour = components.hour ?? 0
        let activityPattern: String
        if hour >= 6 && hour < 12 {
            activityPattern = "morning"
        } else if hour >= 12 && hour < 18 {
            activityPattern = "afternoon"
        } else if hour >= 18 && hour < 22 {
            activityPattern = "evening"
        } else {
            activityPattern = "night"
        }

        return UserPatternsContext(
            timeOfDay: timeOfDay,
            dayOfWeek: dayOfWeek,
            activityPattern: activityPattern
        )
    }

    // MARK: - Conversation State Management

    /// Call this when user starts a conversation
    public func startConversation() {
        isInConversation = true
        conversationStartTime = Date()
        updateContext()
    }

    /// Call this when user ends a conversation
    public func endConversation() {
        isInConversation = false
        conversationStartTime = nil
        updateContext()
    }

    /// Update conversation state manually
    /// - Parameter isInConversation: Whether user is currently in a conversation
    public func setConversationState(_ isInConversation: Bool) {
        if isInConversation && !self.isInConversation {
            startConversation()
        } else if !isInConversation && self.isInConversation {
            endConversation()
        }
    }
}
