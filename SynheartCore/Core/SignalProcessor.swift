import Foundation
import Combine

/// Processes raw signals: synchronization, normalization, cleaning, and derived metrics
public class SignalProcessor {
    private let processedSubject = PassthroughSubject<ProcessedSignals, Never>()
    public var processedPublisher: AnyPublisher<ProcessedSignals, Never> {
        processedSubject.eraseToAnyPublisher()
    }
    
    private var signalBuffer: [SignalData] = []
    private let windowSize: TimeInterval = 30.0 // 30 second windows
    private let processingQueue = DispatchQueue(label: "com.synheart.hsi.signalprocessor", qos: .userInitiated)
    
    public init() {}
    
    /// Process incoming raw signals
    public func process(_ signal: SignalData) {
        processingQueue.async { [weak self] in
            self?.processSignal(signal)
        }
    }
    
    private func processSignal(_ signal: SignalData) {
        // Add to buffer
        signalBuffer.append(signal)
        
        // Remove old signals outside the window
        let cutoffTime = signal.timestamp.addingTimeInterval(-windowSize)
        signalBuffer.removeAll { $0.timestamp < cutoffTime }
        
        // Group signals by type
        let groupedSignals = Dictionary(grouping: signalBuffer) { $0.type }
        
        // Process each signal type
        var processed = ProcessedSignals()
        
        // Process heart rate signals
        if let hrSignals = groupedSignals[.heartRate] {
            processed.heartRate = normalizeAndAverage(hrSignals)
        }
        
        // Process HRV signals
        if let hrvSignals = groupedSignals[.heartRateVariability] {
            processed.heartRateVariability = normalizeAndAverage(hrvSignals)
            
            // Calculate derived metrics
            let values = hrvSignals.map { $0.value }
            processed.rmssd = calculateRMSSD(values)
            processed.sdnn = calculateSDNN(values)
        }
        
        // Process behavioral signals
        if let typingSignals = groupedSignals[.typing] {
            processed.typingRate = calculateRate(typingSignals)
        }
        
        if let scrollingSignals = groupedSignals[.scrolling] {
            processed.scrollingRate = calculateRate(scrollingSignals)
        }
        
        if let appSwitchSignals = groupedSignals[.appSwitch] {
            processed.appSwitchRate = calculateRate(appSwitchSignals)
        }
        
        // Emit processed signals
        processedSubject.send(processed)
    }
    
    private func normalizeAndAverage(_ signals: [SignalData]) -> Float {
        guard !signals.isEmpty else { return 0.0 }
        
        // Remove outliers (simple approach: remove values outside 2 standard deviations)
        let values = signals.map { $0.value }
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Float(values.count)
        let stdDev = sqrt(variance)
        
        let filtered = values.filter { abs($0 - mean) <= 2 * stdDev }
        return filtered.reduce(0, +) / Float(filtered.count)
    }
    
    private func calculateRMSSD(_ values: [Float]) -> Float {
        guard values.count >= 2 else { return 0.0 }
        
        var sumSquaredDiffs: Float = 0.0
        for i in 1..<values.count {
            let diff = values[i] - values[i-1]
            sumSquaredDiffs += diff * diff
        }
        
        return sqrt(sumSquaredDiffs / Float(values.count - 1))
    }
    
    private func calculateSDNN(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0.0 }
        
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Float(values.count)
        return sqrt(variance)
    }
    
    private func calculateRate(_ signals: [SignalData]) -> Float {
        guard signals.count >= 2 else { return 0.0 }
        
        let timeSpan = signals.last!.timestamp.timeIntervalSince(signals.first!.timestamp)
        guard timeSpan > 0 else { return 0.0 }
        
        return Float(signals.count) / Float(timeSpan)
    }
}

/// Processed signals ready for fusion
public struct ProcessedSignals {
    public var heartRate: Float?
    public var heartRateVariability: Float?
    public var rmssd: Float?
    public var sdnn: Float?
    public var typingRate: Float?
    public var scrollingRate: Float?
    public var appSwitchRate: Float?
    
    public init() {}
}

