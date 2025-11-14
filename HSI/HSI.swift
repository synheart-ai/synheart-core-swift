import Foundation
import Combine

/// Main HSI class - Singleton pattern for accessing Human State Interface
public class HSI {
    /// Shared singleton instance
    public static let shared = HSI()
    
    private let stateEngine: StateEngine
    private let emotionHead: EmotionHead
    private let focusHead: FocusHead
    
    private let finalHsvSubject = CurrentValueSubject<HSV?, Never>(nil)
    
    /// Publisher of final HSV (with emotion and focus populated)
    public var statePublisher: AnyPublisher<HSV, Never> {
        finalHsvSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
    
    /// Latest HSV state (optional)
    public var currentState: HSV? {
        finalHsvSubject.value
    }
    
    private var cancellables = Set<AnyCancellable>()
    private var appKey: String?
    private var isConfigured = false
    
    /// Initialize HSI with optional custom components
    /// - Parameters:
    ///   - stateEngine: Custom state engine (optional)
    ///   - emotionHead: Custom emotion head with emotion model (optional)
    ///   - focusHead: Custom focus head with focus model (optional)
    public init(stateEngine: StateEngine? = nil,
                emotionHead: EmotionHead? = nil,
                focusHead: FocusHead? = nil) {
        self.stateEngine = stateEngine ?? StateEngine()
        self.emotionHead = emotionHead ?? EmotionHead()
        self.focusHead = focusHead ?? FocusHead()

        setupPipeline()
    }
    
    /// Configure HSI with app key
    /// - Parameter appKey: Application key for authentication/identification
    public func configure(appKey: String) {
        self.appKey = appKey
        self.isConfigured = true
    }
    
    /// Start the HSI pipeline
    public func start() {
        guard isConfigured else {
            print("Warning: HSI not configured. Call configure(appKey:) first.")
            return
        }
        
        stateEngine.start()
    }
    
    /// Stop the HSI pipeline
    public func stop() {
        stateEngine.stop()
        // Note: Keep pipeline cancellables intact to allow restart
    }
    
    /// Enable cloud sync (future implementation)
    public func enableCloudSync() {
        // TODO: Implement cloud sync functionality
        print("Cloud sync not yet implemented")
    }
    
    private func setupPipeline() {
        // Connect: State Engine -> Emotion Head -> Focus Head -> Final HSV
        
        // State Engine -> Emotion Head
        emotionHead.subscribe(to: stateEngine.baseHsvPublisher)
        
        // Emotion Head -> Focus Head
        focusHead.subscribe(to: emotionHead.hsvWithEmotionPublisher)
        
        // Focus Head -> Final HSV
        focusHead.finalHsvPublisher
            .sink { [weak self] finalHsv in
                self?.finalHsvSubject.send(finalHsv)
            }
            .store(in: &cancellables)
    }
}

