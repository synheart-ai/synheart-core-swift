import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif
import Combine

/// Adapter for collecting motion and activity data from CoreMotion
@available(iOS 13.0, watchOS 6.0, *)
@available(macOS, unavailable)
@available(tvOS, unavailable)
public class CoreMotionAdapter {
    #if canImport(CoreMotion) && !os(macOS) && !os(tvOS)
    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    #endif

    private let signalSubject = PassthroughSubject<SignalData, Never>()

    public var signalPublisher: AnyPublisher<SignalData, Never> {
        signalSubject.eraseToAnyPublisher()
    }

    private var isRunning = false
    private let updateInterval: TimeInterval = 1.0 // 1 second

    public init() {}

    /// Check if motion services are available
    public var isMotionAvailable: Bool {
        #if canImport(CoreMotion) && !os(macOS) && !os(tvOS)
        return motionManager.isDeviceMotionAvailable
        #else
        return false
        #endif
    }

    /// Check if activity tracking is available
    public var isActivityAvailable: Bool {
        #if canImport(CoreMotion) && !os(macOS) && !os(tvOS)
        return CMMotionActivityManager.isActivityAvailable()
        #else
        return false
        #endif
    }

    /// Check if pedometer is available
    public var isPedometerAvailable: Bool {
        #if canImport(CoreMotion) && !os(macOS) && !os(tvOS)
        return CMPedometer.isStepCountingAvailable()
        #else
        return false
        #endif
    }

    /// Start collecting motion data
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        #if canImport(CoreMotion) && !os(macOS) && !os(tvOS)
        startDeviceMotion()
        startActivityMonitoring()
        startPedometerUpdates()
        #endif
    }

    /// Stop collecting motion data
    public func stop() {
        isRunning = false

        #if canImport(CoreMotion) && !os(macOS) && !os(tvOS)
        motionManager.stopDeviceMotionUpdates()
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        #endif
    }

    #if canImport(CoreMotion) && !os(macOS) && !os(tvOS)
    private func startDeviceMotion() {
        guard motionManager.isDeviceMotionAvailable else {
            return
        }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else {
                return
            }

            // Extract motion intensity (magnitude of user acceleration)
            let accel = motion.userAcceleration
            let intensity = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)

            let signal = SignalData(
                type: .motion,
                value: Float(intensity),
                timestamp: Date(),
                source: .coreMotion,
                metadata: [
                    "x": accel.x,
                    "y": accel.y,
                    "z": accel.z,
                    "rotation_rate_x": motion.rotationRate.x,
                    "rotation_rate_y": motion.rotationRate.y,
                    "rotation_rate_z": motion.rotationRate.z
                ]
            )

            self.signalSubject.send(signal)
        }
    }

    private func startActivityMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            return
        }

        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self = self, let activity = activity else {
                return
            }

            // Map activity to a simple numeric value
            var activityValue: Float = 0.0
            var activityType = "unknown"

            if activity.stationary {
                activityValue = 0.0
                activityType = "stationary"
            } else if activity.walking {
                activityValue = 1.0
                activityType = "walking"
            } else if activity.running {
                activityValue = 2.0
                activityType = "running"
            } else if activity.automotive {
                activityValue = 0.5
                activityType = "automotive"
            } else if activity.cycling {
                activityValue = 1.5
                activityType = "cycling"
            }

            let signal = SignalData(
                type: .motion,
                value: activityValue,
                timestamp: activity.startDate,
                source: .coreMotion,
                metadata: [
                    "activity_type": activityType,
                    "confidence": activity.confidence.rawValue
                ]
            )

            self.signalSubject.send(signal)
        }
    }

    private func startPedometerUpdates() {
        guard CMPedometer.isStepCountingAvailable() else {
            return
        }

        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self = self, let data = data, error == nil else {
                return
            }

            // Emit step count as motion signal
            let steps = data.numberOfSteps
            let signal = SignalData(
                type: .motion,
                value: Float(truncating: steps),
                timestamp: Date(),
                source: .coreMotion,
                metadata: [
                    "metric": "steps",
                    "distance": data.distance?.floatValue ?? 0.0,
                    "floors_ascended": data.floorsAscended?.floatValue ?? 0.0,
                    "floors_descended": data.floorsDescended?.floatValue ?? 0.0
                ]
            )

            self.signalSubject.send(signal)
        }
    }
    #endif
}
