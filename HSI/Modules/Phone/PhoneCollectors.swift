import Foundation
import Combine

/// Motion data from accelerometer/gyroscope
public struct MotionData {
    public let x: Double
    public let y: Double
    public let z: Double
    public let energy: Double
    public let timestamp: Date
    
    public init(x: Double, y: Double, z: Double, energy: Double, timestamp: Date) {
        self.x = x
        self.y = y
        self.z = z
        self.energy = energy
        self.timestamp = timestamp
    }
}

/// Screen state information
public enum ScreenState {
    case on
    case off
    case locked
    case unlocked
}

/// Notification event
public struct NotificationEvent {
    public let timestamp: Date
    public let opened: Bool // true if opened, false if just received
    
    public init(timestamp: Date, opened: Bool) {
        self.timestamp = timestamp
        self.opened = opened
    }
}

/// Collects motion data from device sensors
public class MotionCollector {
    private let controller = PassthroughSubject<MotionData, Error>()
    private var timer: Timer?
    private var currentMotionLevel: Double = 0.0
    
    public var motionStream: AnyPublisher<MotionData, Error> {
        controller.eraseToAnyPublisher()
    }
    
    /// Current normalized motion level (0.0 - 1.0)
    public var currentMotionLevelValue: Double {
        return currentMotionLevel
    }
    
    public func start() async throws {
        // Mock motion data (in production, use CoreMotion)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Simulate varying motion levels
            self.currentMotionLevel += (Double.random(in: 0...1) - 0.5) * 0.1
            self.currentMotionLevel = max(0.0, min(1.0, self.currentMotionLevel))
            
            let x = (Double.random(in: 0...1) - 0.5) * 2
            let y = (Double.random(in: 0...1) - 0.5) * 2
            let z = (Double.random(in: 0...1) - 0.5) * 2
            let energy = sqrt(x * x + y * y + z * z)
            
            let motion = MotionData(
                x: x,
                y: y,
                z: z,
                energy: energy,
                timestamp: Date()
            )
            
            self.controller.send(motion)
        }
    }
    
    public func stop() async throws {
        timer?.invalidate()
        timer = nil
    }
    
    public func dispose() async throws {
        try await stop()
        controller.send(completion: .finished)
    }
}

/// Tracks screen state (on/off/locked/unlocked)
public class ScreenStateTracker {
    private let controller = PassthroughSubject<ScreenState, Error>()
    private var timer: Timer?
    private var currentState: ScreenState = .unlocked
    
    public var screenStream: AnyPublisher<ScreenState, Error> {
        controller.eraseToAnyPublisher()
    }
    
    public var isScreenOn: Bool {
        return currentState == .on || currentState == .unlocked
    }
    
    public func start() async throws {
        // Mock screen state changes (in production, use UIApplication notifications)
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Randomly change screen state
            if Double.random(in: 0...1) < 0.3 {
                let states: [ScreenState] = [.on, .off, .locked, .unlocked]
                self.currentState = states.randomElement() ?? .unlocked
                self.controller.send(self.currentState)
            }
        }
        
        // Emit initial state
        controller.send(currentState)
    }
    
    public func stop() async throws {
        timer?.invalidate()
        timer = nil
    }
    
    public func dispose() async throws {
        try await stop()
        controller.send(completion: .finished)
    }
}

/// Tracks app focus and switching
public class AppFocusTracker {
    private let controller = PassthroughSubject<String, Error>()
    private var timer: Timer?
    private var switchCount = 0
    private var lastSwitch = Date()
    private let mockApps = ["app1", "app2", "app3", "app4"]
    
    public var appSwitchStream: AnyPublisher<String, Error> {
        controller.eraseToAnyPublisher()
    }
    
    /// Get app switch rate (switches per minute)
    public var switchRate: Double {
        let elapsed = Date().timeIntervalSince(lastSwitch) / 60.0
        if elapsed == 0 { return 0.0 }
        return Double(switchCount) / elapsed
    }
    
    public func start() async throws {
        // Mock app switching (in production, use UIApplication notifications)
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Randomly switch apps
            if Double.random(in: 0...1) < 0.4 {
                let app = self.mockApps.randomElement() ?? "app1"
                self.switchCount += 1
                self.lastSwitch = Date()
                self.controller.send(app)
            }
        }
    }
    
    public func stop() async throws {
        timer?.invalidate()
        timer = nil
    }
    
    public func dispose() async throws {
        try await stop()
        controller.send(completion: .finished)
    }
}

/// Tracks notifications
public class NotificationTracker {
    private let controller = PassthroughSubject<NotificationEvent, Error>()
    private var timer: Timer?
    private var recentNotifications: [NotificationEvent] = []
    
    public var notificationStream: AnyPublisher<NotificationEvent, Error> {
        controller.eraseToAnyPublisher()
    }
    
    /// Get notification count in last minute
    public var recentNotificationCount: Int {
        let cutoff = Date().addingTimeInterval(-60)
        return recentNotifications.filter { $0.timestamp > cutoff }.count
    }
    
    public func start() async throws {
        // Mock notifications (in production, use UNUserNotificationCenter)
        timer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Randomly emit notifications
            if Double.random(in: 0...1) < 0.3 {
                let event = NotificationEvent(
                    timestamp: Date(),
                    opened: Double.random(in: 0...1) < 0.5
                )
                self.recentNotifications.append(event)
                self.controller.send(event)
                
                // Clean old notifications
                let cutoff = Date().addingTimeInterval(-5 * 60)
                self.recentNotifications.removeAll { $0.timestamp < cutoff }
            }
        }
    }
    
    public func stop() async throws {
        timer?.invalidate()
        timer = nil
    }
    
    public func dispose() async throws {
        try await stop()
        controller.send(completion: .finished)
    }
}

