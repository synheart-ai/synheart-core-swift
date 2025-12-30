import Foundation
import Combine

/// HSV Runtime Module
///
/// Orchestrates the HSV runtime pipeline:
/// 1. Schedules windows (30s, 5m, 1h, 24h)
/// 2. Collects features from Wear, Phone, Behavior
/// 3. Fuses features into base HSV
/// 4. Runs Emotion and Focus heads
/// 5. Publishes final HSV
public class HSVRuntimeModule: BaseSynheartModule {
    private let collector: ChannelCollector
    private let fusion = RuntimeFusionEngine()
    private let emotionHead: EmotionHead
    private let focusHead: FocusHead
    
    private var scheduler: WindowScheduler?
    
    private let baseHsvSubject = CurrentValueSubject<HSV?, Never>(nil)
    private let finalHsvSubject = CurrentValueSubject<HSV?, Never>(nil)
    
    private var emotionSubscription: AnyCancellable?
    private var focusSubscription: AnyCancellable?
    
    public init(
        collector: ChannelCollector,
        emotionModel: EmotionModelProtocol? = nil,
        focusModel: FocusModelProtocol? = nil
    ) {
        self.collector = collector
        self.emotionHead = EmotionHead(emotionModel: emotionModel)
        self.focusHead = FocusHead(focusModel: focusModel)
        super.init(moduleId: "hsv_runtime")
    }
    
    /// Stream of base HSV (before emotion/focus)
    public var baseHsvStream: AnyPublisher<HSV, Never> {
        baseHsvSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
    
    /// Stream of final HSV (with emotion and focus)
    public var finalHsvStream: AnyPublisher<HSV, Never> {
        finalHsvSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
    
    /// Get current state
    public var currentState: HSV? {
        return finalHsvSubject.value
    }
    
    // MARK: - SynheartModule
    
    public override func initialize() async throws {
        print("[HSVRuntime] Initializing HSV Runtime...")
        
        // Initialize emotion and focus heads
        emotionHead.subscribe(to: baseHsvStream)
        focusHead.subscribe(to: emotionHead.hsvWithEmotionPublisher)
        
        // Subscribe to focus stream for final HSV
        focusSubscription = focusHead.finalHsvPublisher
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("[HSVRuntime] Focus stream error: \(error)")
                    }
                },
                receiveValue: { [weak self] finalHsv in
                    self?.finalHsvSubject.send(finalHsv)
                }
            )
    }
    
    public override func start() async throws {
        print("[HSVRuntime] Starting HSV Runtime...")
        
        // Start window scheduler
        scheduler = WindowScheduler { [weak self] window in
            // Only compute for 30s window (primary window)
            if window == .window30s {
                Task {
                    await self?.computeState(window)
                }
            }
        }
        
        scheduler?.start()
        print("[HSVRuntime] HSV Runtime started")
    }
    
    public override func stop() async throws {
        print("[HSVRuntime] Stopping HSV Runtime...")
        
        scheduler?.stop()
        scheduler = nil
    }
    
    public override func dispose() async throws {
        print("[HSVRuntime] Disposing HSV Runtime...")
        
        emotionSubscription?.cancel()
        focusSubscription?.cancel()
        
        await scheduler?.stop()
        scheduler = nil
    }
    
    /// Compute state for a window
    private func computeState(_ window: WindowType) async {
        // Collect features from all modules
        let features = collector.collect(window)
        
        guard features.hasAnyFeatures else {
            print("[HSVRuntime] No features available for \(window)")
            return
        }
        
        // Fuse into base HSV
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let baseHsv = await fusion.fuse(features, window: window, timestamp: timestamp)
        
        // Emit base HSV (will flow through emotion -> focus heads)
        baseHsvSubject.send(baseHsv)
        
        print("[HSVRuntime] Computed state for \(window)")
    }
}


