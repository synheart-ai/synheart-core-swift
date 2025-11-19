import Foundation
import Combine

/// Behavior event stream
///
/// Unified event bus for all user-device interactions
public class BehaviorEventStream {
    private let controller = PassthroughSubject<BehaviorEvent, Error>()
    
    public var events: AnyPublisher<BehaviorEvent, Error> {
        controller.eraseToAnyPublisher()
    }
    
    /// Record a tap event
    public func recordTap(x: Double, y: Double) {
        controller.send(.tap(x: x, y: y))
    }
    
    /// Record a scroll event
    public func recordScroll(delta: Double) {
        controller.send(.scroll(delta: delta))
    }
    
    /// Record a key down event
    public func recordKeyDown() {
        controller.send(.keyDown())
    }
    
    /// Record a key up event
    public func recordKeyUp() {
        controller.send(.keyUp())
    }
    
    /// Record an app switch event
    public func recordAppSwitch() {
        controller.send(.appSwitch())
    }
    
    /// Record a notification received event
    public func recordNotificationReceived() {
        controller.send(.notificationReceived())
    }
    
    /// Record a notification opened event
    public func recordNotificationOpened() {
        controller.send(.notificationOpened())
    }
    
    public func dispose() async throws {
        controller.send(completion: .finished)
    }
}

