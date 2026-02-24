import Foundation
import Network
import Combine

/// Network connectivity monitor
///
/// Monitors network state and emits connectivity changes via Combine publisher.
/// Used to trigger auto-flush when network becomes available.
public class NetworkMonitor {
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.synheart.networkmonitor")

    private let connectivitySubject = CurrentValueSubject<Bool, Never>(false)
    public var connectivityPublisher: AnyPublisher<Bool, Never> {
        connectivitySubject.eraseToAnyPublisher()
    }

    public var isOnline: Bool {
        connectivitySubject.value
    }

    public init() {
        self.monitor = NWPathMonitor()
        startMonitoring()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            self?.connectivitySubject.send(isConnected)

            if isConnected {
                SynheartLogger.log("[NetworkMonitor] Network available")
            } else {
                SynheartLogger.log("[NetworkMonitor] Network lost")
            }
        }

        monitor.start(queue: queue)
    }

    public func dispose() {
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}
