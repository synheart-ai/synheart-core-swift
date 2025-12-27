import XCTest
import Combine
@testable import HSI

final class HSIIntegrationTests: XCTestCase {
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Full Pipeline Tests

    func testFullPipelineWithMockData() {
        let expectation = XCTestExpectation(description: "Complete pipeline execution")

        let hsi = HSI()
        hsi.configure(appKey: "test-key")

        hsi.statePublisher
            .sink { hsv in
                // Verify base HSV fields
                XCTAssertNotNil(hsv.meta)
                XCTAssertNotNil(hsv.meta.timestamp)
                XCTAssertNotNil(hsv.meta.sessionId)

                // Mock data should generate heart rate
                XCTAssertNotNil(hsv.heartRate)

                // Emotion should be populated by emotion head
                XCTAssertNotNil(hsv.emotion)

                // Focus should be populated by focus head
                XCTAssertNotNil(hsv.focus)

                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsi.start()

        wait(for: [expectation], timeout: 5.0)

        hsi.stop()
    }

    func testPipelineStartStop() {
        let hsi = HSI()
        hsi.configure(appKey: "test-key")

        // Start
        hsi.start()
        XCTAssertNil(hsi.currentState, "State should be nil initially")

        // Wait for data
        let expectation = XCTestExpectation(description: "Wait for initial state")
        hsi.statePublisher
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 5.0)

        // Should have state now
        XCTAssertNotNil(hsi.currentState, "State should be populated after start")

        // Stop
        hsi.stop()
    }

    func testPipelineRestart() {
        let expectation1 = XCTestExpectation(description: "First start")
        let expectation2 = XCTestExpectation(description: "Restart")

        let hsi = HSI()
        hsi.configure(appKey: "test-key")

        // First start
        hsi.statePublisher
            .first()
            .sink { _ in
                expectation1.fulfill()
            }
            .store(in: &cancellables)

        hsi.start()
        wait(for: [expectation1], timeout: 5.0)

        // Stop
        hsi.stop()

        // Restart
        hsi.statePublisher
            .first()
            .sink { _ in
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        hsi.start()
        wait(for: [expectation2], timeout: 5.0)

        hsi.stop()
    }

    // MARK: - Custom Model Integration Tests

    func testCustomEmotionModel() {
        let expectation = XCTestExpectation(description: "Custom emotion model")

        class TestEmotionModel: EmotionModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                return [
                    "stress": 0.8,
                    "calm": 0.2,
                    "engagement": 0.7,
                    "activation": 0.6,
                    "valence": 0.3
                ]
            }
        }

        let emotionHead = EmotionHead(emotionModel: TestEmotionModel())
        let hsi = HSI(emotionHead: emotionHead)
        hsi.configure(appKey: "test-key")

        hsi.statePublisher
            .sink { hsv in
                if let emotion = hsv.emotion {
                    XCTAssertEqual(emotion.stress, 0.8, accuracy: 0.01)
                    XCTAssertEqual(emotion.calm, 0.2, accuracy: 0.01)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        hsi.start()
        wait(for: [expectation], timeout: 5.0)
        hsi.stop()
    }

    func testCustomFocusModel() {
        let expectation = XCTestExpectation(description: "Custom focus model")

        class TestFocusModel: FocusModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                return [
                    "score": 0.9,
                    "cognitive_load": 0.3,
                    "clarity": 0.85,
                    "distraction": 0.15
                ]
            }
        }

        let focusHead = FocusHead(focusModel: TestFocusModel())
        let hsi = HSI(focusHead: focusHead)
        hsi.configure(appKey: "test-key")

        hsi.statePublisher
            .sink { hsv in
                if let focus = hsv.focus {
                    XCTAssertEqual(focus.score, 0.9, accuracy: 0.01)
                    XCTAssertEqual(focus.clarity, 0.85, accuracy: 0.01)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        hsi.start()
        wait(for: [expectation], timeout: 5.0)
        hsi.stop()
    }

    // MARK: - State Engine Tests

    func testStateEngineProducesBaseHSV() {
        let expectation = XCTestExpectation(description: "State engine produces base HSV")

        let stateEngine = StateEngine()

        stateEngine.baseHsvPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.meta)
                XCTAssertNotNil(hsv.hsiEmbedding)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        stateEngine.start()
        wait(for: [expectation], timeout: 5.0)
        stateEngine.stop()
    }

    // MARK: - Context Integration Tests

    func testContextIntegration() {
        let expectation = XCTestExpectation(description: "Context populated in HSV")

        let contextAdapter = ContextAdapter()
        let fusionEngine = FusionEngine(contextAdapter: contextAdapter)
        let stateEngine = StateEngine(fusionEngine: fusionEngine, contextAdapter: contextAdapter)

        stateEngine.baseHsvPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.context, "Context should be populated")
                if let context = hsv.context {
                    XCTAssertNotNil(context.device)
                    XCTAssertNotNil(context.patterns)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        stateEngine.start()
        wait(for: [expectation], timeout: 5.0)
        stateEngine.stop()
    }

    // MARK: - Embedding Model Tests

    func testEmbeddingGeneration() {
        let expectation = XCTestExpectation(description: "Embedding generated")

        let embeddingModel = PlaceholderEmbeddingModel(outputSize: 128)
        let fusionEngine = FusionEngine(embeddingModel: embeddingModel)
        let stateEngine = StateEngine(fusionEngine: fusionEngine)

        stateEngine.baseHsvPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.hsiEmbedding)
                XCTAssertEqual(hsv.hsiEmbedding?.count, 128)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        stateEngine.start()
        wait(for: [expectation], timeout: 5.0)
        stateEngine.stop()
    }

    // MARK: - Data Flow Tests

    func testEmotionHeadReceivesBaseHSV() {
        let expectation = XCTestExpectation(description: "Emotion head receives base HSV")

        let stateEngine = StateEngine()
        let emotionHead = EmotionHead()

        emotionHead.subscribe(to: stateEngine.baseHsvPublisher)

        emotionHead.hsvWithEmotionPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.emotion)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        stateEngine.start()
        wait(for: [expectation], timeout: 5.0)
        stateEngine.stop()
    }

    func testFocusHeadReceivesEmotionHSV() {
        let expectation = XCTestExpectation(description: "Focus head receives HSV with emotion")

        let stateEngine = StateEngine()
        let emotionHead = EmotionHead()
        let focusHead = FocusHead()

        emotionHead.subscribe(to: stateEngine.baseHsvPublisher)
        focusHead.subscribe(to: emotionHead.hsvWithEmotionPublisher)

        focusHead.finalHsvPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.emotion, "Should have emotion")
                XCTAssertNotNil(hsv.focus, "Should have focus")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        stateEngine.start()
        wait(for: [expectation], timeout: 5.0)
        stateEngine.stop()
    }

    // MARK: - Performance Tests

    func testPipelinePerformance() {
        let hsi = HSI()
        hsi.configure(appKey: "test-key")

        measure {
            let expectation = XCTestExpectation(description: "Pipeline performance")

            hsi.statePublisher
                .first()
                .sink { _ in
                    expectation.fulfill()
                }
                .store(in: &cancellables)

            hsi.start()
            wait(for: [expectation], timeout: 10.0)
            hsi.stop()
        }
    }

    // MARK: - Error Handling Tests

    func testErrorHandlingInEmotionHead() {
        let expectation = XCTestExpectation(description: "Handle emotion prediction error")

        class ErrorEmotionModel: EmotionModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                throw NSError(domain: "test", code: -1, userInfo: nil)
            }
        }

        let emotionHead = EmotionHead(emotionModel: ErrorEmotionModel())
        let hsi = HSI(emotionHead: emotionHead)
        hsi.configure(appKey: "test-key")

        hsi.statePublisher
            .sink { hsv in
                // Should not crash, emotion might be nil
                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsi.start()
        wait(for: [expectation], timeout: 5.0)
        hsi.stop()
    }

    func testErrorHandlingInFocusHead() {
        let expectation = XCTestExpectation(description: "Handle focus prediction error")

        class ErrorFocusModel: FocusModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                throw NSError(domain: "test", code: -1, userInfo: nil)
            }
        }

        let focusHead = FocusHead(focusModel: ErrorFocusModel())
        let hsi = HSI(focusHead: focusHead)
        hsi.configure(appKey: "test-key")

        hsi.statePublisher
            .sink { hsv in
                // Should not crash, focus might be nil
                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsi.start()
        wait(for: [expectation], timeout: 5.0)
        hsi.stop()
    }
}
