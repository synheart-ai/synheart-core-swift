import Combine
import Foundation

#if os(iOS) && canImport(CoreMotion)
import CoreMotion
#endif

#if canImport(UIKit)
import UIKit
#endif

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

/// App-visible device state. iOS does not expose physical display power state,
/// so these values represent app activity and protected-data availability.
public enum ScreenState {
    case on
    case off
    case locked
    case unlocked
}

public struct NotificationEvent {
    public let timestamp: Date
    public let opened: Bool

    public init(timestamp: Date, opened: Bool) {
        self.timestamp = timestamp
        self.opened = opened
    }
}

public protocol MotionCollecting: AnyObject {
    var motionStream: AnyPublisher<MotionData, Error> { get }
    var currentMotionLevelValue: Double { get }
    func start() async throws
    func stop() async throws
    func dispose() async throws
}

public protocol ScreenStateTracking: AnyObject {
    var screenStream: AnyPublisher<ScreenState, Error> { get }
    var isScreenOn: Bool { get }
    func start() async throws
    func stop() async throws
    func dispose() async throws
}

public protocol AppFocusTracking: AnyObject {
    var appSwitchStream: AnyPublisher<String, Error> { get }
    func start() async throws
    func stop() async throws
    func dispose() async throws
}

public protocol NotificationTracking: AnyObject {
    var notificationStream: AnyPublisher<NotificationEvent, Error> { get }
    func start() async throws
    func stop() async throws
    func dispose() async throws
}

/// Production motion collector backed by CoreMotion. On devices without an
/// accelerometer it remains safely idle and never fabricates samples.
public final class CoreMotionCollector: MotionCollecting {
    private let controller = PassthroughSubject<MotionData, Error>()
    private var currentMotionLevel = 0.0
    private let levelLock = NSLock()

    #if os(iOS) && canImport(CoreMotion)
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ai.synheart.core.phone-motion"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    #endif

    public init() {}

    public var motionStream: AnyPublisher<MotionData, Error> {
        controller.eraseToAnyPublisher()
    }

    public var currentMotionLevelValue: Double {
        levelLock.lock()
        defer { levelLock.unlock() }
        return currentMotionLevel
    }

    public func start() async throws {
        #if os(iOS) && canImport(CoreMotion)
        guard manager.isAccelerometerAvailable, !manager.isAccelerometerActive else { return }
        manager.accelerometerUpdateInterval = 0.1
        manager.startAccelerometerUpdates(to: queue) { [weak self] data, error in
            guard let self else { return }
            if let error {
                self.controller.send(completion: .failure(error))
                return
            }
            guard let acceleration = data?.acceleration else { return }
            let energy = sqrt(
                acceleration.x * acceleration.x
                    + acceleration.y * acceleration.y
                    + acceleration.z * acceleration.z
            )
            self.levelLock.lock()
            self.currentMotionLevel = min(max(abs(energy - 1.0), 0), 1)
            self.levelLock.unlock()
            self.controller.send(MotionData(
                x: acceleration.x,
                y: acceleration.y,
                z: acceleration.z,
                energy: energy,
                timestamp: Date()
            ))
        }
        #endif
    }

    public func stop() async throws {
        #if os(iOS) && canImport(CoreMotion)
        manager.stopAccelerometerUpdates()
        #endif
    }

    public func dispose() async throws {
        try await stop()
        controller.send(completion: .finished)
    }
}

/// Production tracker backed by this application's lifecycle and
/// protected-data notifications. It never guesses global system state.
public final class IOSScreenStateTracker: ScreenStateTracking {
    private let controller = PassthroughSubject<ScreenState, Error>()
    private var cancellables = Set<AnyCancellable>()
    private var currentState: ScreenState = .off

    public init() {}

    public var screenStream: AnyPublisher<ScreenState, Error> {
        controller.eraseToAnyPublisher()
    }

    public var isScreenOn: Bool {
        currentState == .on || currentState == .unlocked
    }

    public func start() async throws {
        #if canImport(UIKit) && !os(watchOS)
        guard cancellables.isEmpty else { return }
        let center = NotificationCenter.default
        observe(center, name: UIApplication.didBecomeActiveNotification, state: .on)
        observe(center, name: UIApplication.willResignActiveNotification, state: .off)
        observe(center, name: UIApplication.protectedDataWillBecomeUnavailableNotification, state: .locked)
        observe(center, name: UIApplication.protectedDataDidBecomeAvailableNotification, state: .unlocked)
        currentState = UIApplication.shared.applicationState == .active ? .on : .off
        controller.send(currentState)
        #endif
    }

    #if canImport(UIKit) && !os(watchOS)
    private func observe(_ center: NotificationCenter, name: Notification.Name, state: ScreenState) {
        center.publisher(for: name)
            .sink { [weak self] _ in
                self?.currentState = state
                self?.controller.send(state)
            }
            .store(in: &cancellables)
    }
    #endif

    public func stop() async throws {
        cancellables.removeAll()
    }

    public func dispose() async throws {
        try await stop()
        controller.send(completion: .finished)
    }
}

/// iOS does not expose other applications' focus changes. Hosts with an
/// approved source may inject their own implementation.
public final class NoOpAppFocusTracker: AppFocusTracking {
    private let controller = PassthroughSubject<String, Error>()
    public init() {}
    public var appSwitchStream: AnyPublisher<String, Error> { controller.eraseToAnyPublisher() }
    public func start() async throws {}
    public func stop() async throws {}
    public func dispose() async throws { controller.send(completion: .finished) }
}

/// iOS does not expose a global stream of notifications. Hosts may inject a
/// tracker fed by their own UNUserNotificationCenter delegate.
public final class NoOpNotificationTracker: NotificationTracking {
    private let controller = PassthroughSubject<NotificationEvent, Error>()
    public init() {}
    public var notificationStream: AnyPublisher<NotificationEvent, Error> { controller.eraseToAnyPublisher() }
    public func start() async throws {}
    public func stop() async throws {}
    public func dispose() async throws { controller.send(completion: .finished) }
}
