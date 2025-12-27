import Foundation
#if canImport(HealthKit)
import HealthKit
#endif
import Combine

/// Adapter for collecting biosignal data from HealthKit
@available(iOS 13.0, watchOS 6.0, macOS 13.0, *)
public class HealthKitAdapter {
    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif
    private let signalSubject = PassthroughSubject<SignalData, Never>()

    public var signalPublisher: AnyPublisher<SignalData, Never> {
        signalSubject.eraseToAnyPublisher()
    }

    #if canImport(HealthKit)
    private var heartRateQuery: HKObserverQuery?
    private var hrvQuery: HKObserverQuery?
    #endif
    private var isAuthorized = false

    public init() {}

    /// Request HealthKit authorization for heart rate and HRV data
    /// - Parameter completion: Called when authorization completes
    public func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, NSError(domain: "HealthKitAdapter", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "HealthKit not available"]))
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        ]

        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            self?.isAuthorized = success
            completion(success, error)
        }
        #else
        completion(false, NSError(domain: "HealthKitAdapter", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "HealthKit not available on this platform"]))
        #endif
    }

    /// Start collecting heart rate and HRV data
    public func start() {
        guard isAuthorized else {
            print("HealthKit not authorized. Call requestAuthorization first.")
            return
        }

        #if canImport(HealthKit)
        startHeartRateCollection()
        startHRVCollection()
        #endif
    }

    /// Stop collecting data
    public func stop() {
        #if canImport(HealthKit)
        if let query = heartRateQuery {
            healthStore.stop(query)
        }
        if let query = hrvQuery {
            healthStore.stop(query)
        }

        heartRateQuery = nil
        hrvQuery = nil
        #endif
    }

    #if canImport(HealthKit)
    private func startHeartRateCollection() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        // Use observer query to get notified of new samples
        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, _, error in
            if let error = error {
                print("Heart rate observer query error: \(error)")
                return
            }

            self?.fetchLatestHeartRate()
        }

        heartRateQuery = query
        healthStore.execute(query)

        // Also fetch initial samples
        fetchLatestHeartRate()
    }

    private func fetchLatestHeartRate() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: nil,
            limit: 10,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample],
                  error == nil else {
                return
            }

            // Convert samples to SignalData and emit
            for sample in samples {
                let value = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                let signal = SignalData(
                    type: .heartRate,
                    value: Float(value),
                    timestamp: sample.startDate,
                    source: .healthKit
                )
                self.signalSubject.send(signal)
            }
        }

        healthStore.execute(query)
    }

    private func startHRVCollection() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return
        }

        // Use observer query to get notified of new samples
        let query = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] _, _, error in
            if let error = error {
                print("HRV observer query error: \(error)")
                return
            }

            self?.fetchLatestHRV()
        }

        hrvQuery = query
        healthStore.execute(query)

        // Also fetch initial samples
        fetchLatestHRV()
    }

    private func fetchLatestHRV() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: hrvType,
            predicate: nil,
            limit: 10,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self,
                  let samples = samples as? [HKQuantitySample],
                  error == nil else {
                return
            }

            // Convert samples to SignalData and emit
            for sample in samples {
                let value = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                let signal = SignalData(
                    type: .heartRateVariability,
                    value: Float(value),
                    timestamp: sample.startDate,
                    source: .healthKit
                )
                self.signalSubject.send(signal)
            }
        }

        healthStore.execute(query)
    }
    #endif
}
