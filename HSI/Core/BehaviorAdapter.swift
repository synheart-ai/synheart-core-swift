import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Adapter for tracking phone behavioral signals (typing, scrolling, app switches)
public class BehaviorAdapter {
    private let signalSubject = PassthroughSubject<SignalData, Never>()

    public var signalPublisher: AnyPublisher<SignalData, Never> {
        signalSubject.eraseToAnyPublisher()
    }

    private var isRunning = false
    private var appSwitchCount = 0
    private var sessionStartTime = Date()

    #if canImport(UIKit)
    private var notificationObservers: [NSObjectProtocol] = []
    #endif

    public init() {}

    /// Start monitoring behavioral signals
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        sessionStartTime = Date()
        appSwitchCount = 0

        startAppSwitchMonitoring()
    }

    /// Stop monitoring behavioral signals
    public func stop() {
        isRunning = false
        #if canImport(UIKit)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        #endif
    }

    // MARK: - App Switch Monitoring

    private func startAppSwitchMonitoring() {
        #if canImport(UIKit)
        // Monitor app lifecycle transitions to track app switches
        let willResignActive = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppSwitch()
        }

        let didBecomeActive = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppSwitch()
        }

        notificationObservers.append(willResignActive)
        notificationObservers.append(didBecomeActive)
        #endif
    }

    private func handleAppSwitch() {
        guard isRunning else { return }

        appSwitchCount += 1

        let signal = SignalData(
            type: .appSwitch,
            value: Float(appSwitchCount),
            timestamp: Date(),
            source: .phoneSDK,
            metadata: [
                "session_duration": Date().timeIntervalSince(sessionStartTime)
            ]
        )

        signalSubject.send(signal)
    }

    // MARK: - Typing Tracking (Manual Instrumentation)

    /// Call this method when typing activity is detected in your app
    /// - Parameters:
    ///   - characterCount: Number of characters typed
    ///   - duration: Duration of typing session
    public func recordTypingActivity(characterCount: Int, duration: TimeInterval) {
        guard isRunning else { return }

        let typingRate = Float(characterCount) / Float(duration)

        let signal = SignalData(
            type: .typing,
            value: typingRate,
            timestamp: Date(),
            source: .phoneSDK,
            metadata: [
                "character_count": characterCount,
                "duration": duration
            ]
        )

        signalSubject.send(signal)
    }

    /// Call this method for each keystroke/character typed
    public func recordKeystroke() {
        guard isRunning else { return }

        let signal = SignalData(
            type: .typing,
            value: 1.0, // Single keystroke
            timestamp: Date(),
            source: .phoneSDK
        )

        signalSubject.send(signal)
    }

    // MARK: - Scrolling Tracking (Manual Instrumentation)

    /// Call this method when scrolling activity is detected
    /// - Parameters:
    ///   - distance: Distance scrolled in points
    ///   - velocity: Scrolling velocity
    public func recordScrolling(distance: Float, velocity: Float = 0) {
        guard isRunning else { return }

        let signal = SignalData(
            type: .scrolling,
            value: distance,
            timestamp: Date(),
            source: .phoneSDK,
            metadata: [
                "velocity": velocity
            ]
        )

        signalSubject.send(signal)
    }

    // MARK: - Integration Helpers for SwiftUI/UIKit

    #if canImport(UIKit)
    /// Create a text field delegate for automatic typing tracking
    public func makeTextFieldDelegate() -> BehaviorTrackingTextFieldDelegate {
        return BehaviorTrackingTextFieldDelegate(adapter: self)
    }
    #endif
}

#if canImport(UIKit)
/// UITextFieldDelegate that automatically tracks typing activity
public class BehaviorTrackingTextFieldDelegate: NSObject, UITextFieldDelegate {
    private weak var adapter: BehaviorAdapter?

    init(adapter: BehaviorAdapter) {
        self.adapter = adapter
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        adapter?.recordKeystroke()
        return true
    }
}

/// UIScrollViewDelegate that automatically tracks scrolling activity
public class BehaviorTrackingScrollViewDelegate: NSObject, UIScrollViewDelegate {
    private weak var adapter: BehaviorAdapter?
    private var lastContentOffset: CGPoint = .zero

    public init(adapter: BehaviorAdapter) {
        self.adapter = adapter
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let currentOffset = scrollView.contentOffset
        let distance = sqrt(
            pow(currentOffset.x - lastContentOffset.x, 2) +
            pow(currentOffset.y - lastContentOffset.y, 2)
        )

        adapter?.recordScrolling(distance: Float(distance))
        lastContentOffset = currentOffset
    }
}
#endif
