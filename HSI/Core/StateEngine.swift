import Foundation
import Combine

/// Orchestrates ingestion, processing, and fusion to produce base HSV
public class StateEngine {
    private let ingestionService: IngestionService
    private let signalProcessor: SignalProcessor
    private let fusionEngine: FusionEngine
    private let contextAdapter: ContextAdapter?

    private let baseHsvSubject = CurrentValueSubject<HSV?, Never>(nil)
    public var baseHsvPublisher: AnyPublisher<HSV, Never> {
        baseHsvSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()
    private var isRunning = false

    /// Initialize state engine
    /// - Parameters:
    ///   - ingestionService: Optional ingestion service
    ///   - signalProcessor: Optional signal processor
    ///   - fusionEngine: Optional fusion engine
    ///   - contextAdapter: Optional context adapter
    public init(ingestionService: IngestionService? = nil,
                signalProcessor: SignalProcessor? = nil,
                fusionEngine: FusionEngine? = nil,
                contextAdapter: ContextAdapter? = nil) {
        self.contextAdapter = contextAdapter ?? ContextAdapter()
        self.ingestionService = ingestionService ?? IngestionService()
        self.signalProcessor = signalProcessor ?? SignalProcessor()
        self.fusionEngine = fusionEngine ?? FusionEngine(contextAdapter: self.contextAdapter)

        setupPipeline()
    }
    
    /// Start the state engine pipeline
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        fusionEngine.resetSession()
        contextAdapter?.start()
        ingestionService.start()
    }
    
    /// Stop the state engine pipeline
    public func stop() {
        isRunning = false
        contextAdapter?.stop()
        ingestionService.stop()
        // Note: Keep pipeline cancellables intact to allow restart
    }
    
    private func setupPipeline() {
        // Connect ingestion -> processing -> fusion -> base HSV
        
        // Ingestion -> Signal Processor
        ingestionService.signalPublisher
            .sink { [weak self] signal in
                self?.signalProcessor.process(signal)
            }
            .store(in: &cancellables)
        
        // Signal Processor -> Fusion Engine
        signalProcessor.processedPublisher
            .sink { [weak self] processed in
                self?.fusionEngine.fuse(processed)
            }
            .store(in: &cancellables)
        
        // Fusion Engine -> Base HSV
        fusionEngine.hsvPublisher
            .sink { [weak self] hsv in
                self?.baseHsvSubject.send(hsv)
            }
            .store(in: &cancellables)
    }
}

