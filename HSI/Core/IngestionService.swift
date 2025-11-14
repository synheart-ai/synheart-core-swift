import Foundation
import Combine

/// Service responsible for collecting raw signals from various sources
public class IngestionService {
    private let signalSubject = PassthroughSubject<SignalData, Never>()
    public var signalPublisher: AnyPublisher<SignalData, Never> {
        signalSubject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    private let healthKitAdapter: Any?
    private let coreMotionAdapter: Any?
    private let behaviorAdapter: BehaviorAdapter?
    private let useMockData: Bool

    /// Initialize ingestion service
    /// - Parameters:
    ///   - healthKitAdapter: Optional HealthKit adapter for biosignal data
    ///   - coreMotionAdapter: Optional CoreMotion adapter for motion data
    ///   - behaviorAdapter: Optional behavior adapter for phone interaction tracking
    ///   - useMockData: If true, generates mock data for testing (default: true)
    public init(healthKitAdapter: Any? = nil,
                coreMotionAdapter: Any? = nil,
                behaviorAdapter: BehaviorAdapter? = nil,
                useMockData: Bool = true) {
        self.healthKitAdapter = healthKitAdapter
        self.coreMotionAdapter = coreMotionAdapter
        self.behaviorAdapter = behaviorAdapter
        self.useMockData = useMockData
    }
    
    /// Start collecting signals from all available sources
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        // Start HealthKit data collection if available
        #if canImport(HealthKit)
        if #available(iOS 13.0, macOS 13.0, watchOS 6.0, *),
           let healthKitAdapter = healthKitAdapter as? HealthKitAdapter {
            healthKitAdapter.signalPublisher
                .sink { [weak self] signal in
                    self?.signalSubject.send(signal)
                }
                .store(in: &cancellables)

            healthKitAdapter.start()
        }
        #endif

        // Start CoreMotion data collection if available
        #if canImport(CoreMotion) && !os(macOS) && !os(tvOS)
        if #available(iOS 13.0, watchOS 6.0, *),
           let coreMotionAdapter = coreMotionAdapter as? CoreMotionAdapter {
            coreMotionAdapter.signalPublisher
                .sink { [weak self] signal in
                    self?.signalSubject.send(signal)
                }
                .store(in: &cancellables)

            coreMotionAdapter.start()
        }
        #endif

        // Start behavior tracking if available
        if let behaviorAdapter = behaviorAdapter {
            behaviorAdapter.signalPublisher
                .sink { [weak self] signal in
                    self?.signalSubject.send(signal)
                }
                .store(in: &cancellables)

            behaviorAdapter.start()
        }

        // Start mock data if enabled (useful for testing)
        if useMockData {
            startMockSignalCollection()
        }

        // TODO: Integrate additional SDKs
        // - Synheart Wear SDK/Service (sleep)
        // - Context Adapters (Screen Time API)
    }
    
    /// Stop collecting signals
    public func stop() {
        isRunning = false

        #if canImport(HealthKit)
        if #available(iOS 13.0, macOS 13.0, watchOS 6.0, *) {
            (healthKitAdapter as? HealthKitAdapter)?.stop()
        }
        #endif

        #if canImport(CoreMotion) && !os(macOS) && !os(tvOS)
        if #available(iOS 13.0, watchOS 6.0, *) {
            (coreMotionAdapter as? CoreMotionAdapter)?.stop()
        }
        #endif

        behaviorAdapter?.stop()
        cancellables.removeAll()
    }
    
    private func startMockSignalCollection() {
        // Mock signal collection - replace with actual SDK integration
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isRunning else { return }
                
                // Emit mock heart rate signal
                let hrSignal = SignalData(
                    type: .heartRate,
                    value: Float.random(in: 60...100),
                    source: .wearSDK
                )
                self.signalSubject.send(hrSignal)
            }
            .store(in: &cancellables)
    }
}

