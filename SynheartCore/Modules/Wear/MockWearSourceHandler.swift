import Foundation
import Combine

/// Mock wearable data source for testing and development
public class MockWearSourceHandler: WearSourceHandler {
    private let controller = PassthroughSubject<WearSample, Error>()
    private var timer: Timer?
    private var sampleCount = 0
    
    // Simulate realistic HR/HRV patterns
    private var baseHr: Double = 70.0
    private var baseHrv: Double = 50.0
    
    public var sourceType: WearSourceType { .mock }
    public var isAvailable: Bool { true }
    
    public var sampleStream: AnyPublisher<WearSample, Error> {
        controller.eraseToAnyPublisher()
    }
    
    public func initialize() async throws {
        // Mock initialization - nothing to do
    }
    
    public func dispose() async throws {
        timer?.invalidate()
        timer = nil
        controller.send(completion: .finished)
    }
    
    // Start generating samples (called after initialize)
    public func startGenerating() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.generateSample()
        }
    }
    
    private func generateSample() {
        sampleCount += 1
        
        // Simulate HR variation (±5 bpm)
        let hrVariation = Double.random(in: -5...5)
        let hr = baseHr + hrVariation + sin(Double(sampleCount) * 0.1) * 3
        
        // Simulate HRV variation
        let hrvVariation = Double.random(in: -10...10)
        let hrvRmssd = baseHrv + hrvVariation
        
        // Simulate motion (0-1)
        let motionLevel = Double.random(in: 0...0.3)
        
        let sample = WearSample(
            timestamp: Date(),
            hr: hr,
            hrvRmssd: hrvRmssd,
            respRate: Double.random(in: 12...18),
            motionLevel: motionLevel,
            sleepStage: nil,
            rrIntervals: nil
        )
        
        controller.send(sample)
    }
}

