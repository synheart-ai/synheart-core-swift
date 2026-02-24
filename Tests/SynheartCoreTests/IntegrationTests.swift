import XCTest
import Combine
@testable import SynheartCore

final class HSVIntegrationTests: XCTestCase {
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func mockHSV(
        heartRate: Float? = 75.0,
        heartRateVariability: Float? = 50.0,
        behavior: BehaviorState? = nil
    ) -> HSV {
        HSV(
            heartRate: heartRate,
            heartRateVariability: heartRateVariability,
            behavior: behavior,
            meta: MetaState(
                device: DeviceInfo(platform: "test", osVersion: "1.0", deviceModel: "test", deviceId: "test-device"),
                sessionId: "test-session"
            )
        )
    }

    // MARK: - EmotionHead Tests

    func testEmotionHeadPopulatesEmotion() {
        let expectation = XCTestExpectation(description: "EmotionHead populates emotion")
        let hsvSubject = PassthroughSubject<HSV, Never>()
        let emotionHead = EmotionHead()

        emotionHead.subscribe(to: hsvSubject.eraseToAnyPublisher())

        emotionHead.hsvWithEmotionPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.emotion)
                XCTAssertNotNil(hsv.heartRate)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV())

        wait(for: [expectation], timeout: 5.0)
    }

    func testEmotionHeadWithCustomModel() {
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

        let hsvSubject = PassthroughSubject<HSV, Never>()
        let emotionHead = EmotionHead(emotionModel: TestEmotionModel())

        emotionHead.subscribe(to: hsvSubject.eraseToAnyPublisher())

        emotionHead.hsvWithEmotionPublisher
            .sink { hsv in
                if let emotion = hsv.emotion {
                    XCTAssertEqual(emotion.stress, 0.8, accuracy: 0.01)
                    XCTAssertEqual(emotion.calm, 0.2, accuracy: 0.01)
                    XCTAssertEqual(emotion.engagement, 0.7, accuracy: 0.01)
                    XCTAssertEqual(emotion.activation, 0.6, accuracy: 0.01)
                    XCTAssertEqual(emotion.valence, 0.3, accuracy: 0.01)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV())

        wait(for: [expectation], timeout: 5.0)
    }

    func testEmotionHeadErrorHandling() {
        let expectation = XCTestExpectation(description: "EmotionHead handles model error")

        class ErrorEmotionModel: EmotionModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                throw NSError(domain: "test", code: -1, userInfo: nil)
            }
        }

        let hsvSubject = PassthroughSubject<HSV, Never>()
        let emotionHead = EmotionHead(emotionModel: ErrorEmotionModel())

        emotionHead.subscribe(to: hsvSubject.eraseToAnyPublisher())

        emotionHead.hsvWithEmotionPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.meta)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV())

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - FocusHead Tests

    func testFocusHeadPopulatesFocus() {
        let expectation = XCTestExpectation(description: "FocusHead populates focus")
        let hsvSubject = PassthroughSubject<HSV, Never>()
        let focusHead = FocusHead()

        focusHead.subscribe(to: hsvSubject.eraseToAnyPublisher())

        focusHead.finalHsvPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.focus)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV())

        wait(for: [expectation], timeout: 5.0)
    }

    func testFocusHeadWithCustomModel() {
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

        let hsvSubject = PassthroughSubject<HSV, Never>()
        let focusHead = FocusHead(focusModel: TestFocusModel())

        focusHead.subscribe(to: hsvSubject.eraseToAnyPublisher())

        focusHead.finalHsvPublisher
            .sink { hsv in
                if let focus = hsv.focus {
                    XCTAssertEqual(focus.score, 0.9, accuracy: 0.01)
                    XCTAssertEqual(focus.cognitiveLoad, 0.3, accuracy: 0.01)
                    XCTAssertEqual(focus.clarity, 0.85, accuracy: 0.01)
                    XCTAssertEqual(focus.distraction, 0.15, accuracy: 0.01)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV())

        wait(for: [expectation], timeout: 5.0)
    }

    func testFocusHeadErrorHandling() {
        let expectation = XCTestExpectation(description: "FocusHead handles model error")

        class ErrorFocusModel: FocusModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                throw NSError(domain: "test", code: -1, userInfo: nil)
            }
        }

        let hsvSubject = PassthroughSubject<HSV, Never>()
        let focusHead = FocusHead(focusModel: ErrorFocusModel())

        focusHead.subscribe(to: hsvSubject.eraseToAnyPublisher())

        focusHead.finalHsvPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.meta)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV())

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Full Pipeline Tests

    func testFullHeadPipeline() {
        let expectation = XCTestExpectation(description: "Full EmotionHead -> FocusHead pipeline")
        let hsvSubject = PassthroughSubject<HSV, Never>()

        let emotionHead = EmotionHead()
        let focusHead = FocusHead()

        emotionHead.subscribe(to: hsvSubject.eraseToAnyPublisher())
        focusHead.subscribe(to: emotionHead.hsvWithEmotionPublisher)

        focusHead.finalHsvPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.meta)
                XCTAssertNotNil(hsv.heartRate)
                XCTAssertNotNil(hsv.emotion)
                XCTAssertNotNil(hsv.focus)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV())

        wait(for: [expectation], timeout: 5.0)
    }

    func testPipelineWithCustomModels() {
        let expectation = XCTestExpectation(description: "Pipeline with custom models")

        class TestEmotionModel: EmotionModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                return ["stress": 0.8, "calm": 0.2, "engagement": 0.7, "activation": 0.6, "valence": 0.3]
            }
        }

        class TestFocusModel: FocusModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                return ["score": 0.9, "cognitive_load": 0.3, "clarity": 0.85, "distraction": 0.15]
            }
        }

        let hsvSubject = PassthroughSubject<HSV, Never>()
        let emotionHead = EmotionHead(emotionModel: TestEmotionModel())
        let focusHead = FocusHead(focusModel: TestFocusModel())

        emotionHead.subscribe(to: hsvSubject.eraseToAnyPublisher())
        focusHead.subscribe(to: emotionHead.hsvWithEmotionPublisher)

        focusHead.finalHsvPublisher
            .sink { hsv in
                if let emotion = hsv.emotion, let focus = hsv.focus {
                    XCTAssertEqual(emotion.stress, 0.8, accuracy: 0.01)
                    XCTAssertEqual(focus.score, 0.9, accuracy: 0.01)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV())

        wait(for: [expectation], timeout: 5.0)
    }

    func testPipelinePreservesHSVFields() {
        let expectation = XCTestExpectation(description: "Pipeline preserves HSV fields")
        let hsvSubject = PassthroughSubject<HSV, Never>()

        let emotionHead = EmotionHead()
        let focusHead = FocusHead()

        emotionHead.subscribe(to: hsvSubject.eraseToAnyPublisher())
        focusHead.subscribe(to: emotionHead.hsvWithEmotionPublisher)

        let inputBehavior = BehaviorState(typingSpeed: 0.5, scrollVelocity: 0.3, appSwitchRate: 0.2)

        focusHead.finalHsvPublisher
            .sink { hsv in
                XCTAssertEqual(hsv.heartRate, 75.0)
                XCTAssertEqual(hsv.heartRateVariability, 50.0)
                XCTAssertEqual(hsv.behavior?.typingSpeed, 0.5)
                XCTAssertEqual(hsv.behavior?.scrollVelocity, 0.3)
                XCTAssertEqual(hsv.meta.sessionId, "test-session")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV(behavior: inputBehavior))

        wait(for: [expectation], timeout: 5.0)
    }

    func testPipelineWithBothHeadErrors() {
        let expectation = XCTestExpectation(description: "Pipeline handles both head errors")

        class ErrorEmotionModel: EmotionModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                throw NSError(domain: "test", code: -1, userInfo: nil)
            }
        }

        class ErrorFocusModel: FocusModelProtocol {
            func predict(features: [String: Float]) async throws -> [String: Float] {
                throw NSError(domain: "test", code: -1, userInfo: nil)
            }
        }

        let hsvSubject = PassthroughSubject<HSV, Never>()
        let emotionHead = EmotionHead(emotionModel: ErrorEmotionModel())
        let focusHead = FocusHead(focusModel: ErrorFocusModel())

        emotionHead.subscribe(to: hsvSubject.eraseToAnyPublisher())
        focusHead.subscribe(to: emotionHead.hsvWithEmotionPublisher)

        focusHead.finalHsvPublisher
            .sink { hsv in
                XCTAssertNotNil(hsv.meta)
                XCTAssertEqual(hsv.heartRate, 75.0)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        hsvSubject.send(mockHSV())

        wait(for: [expectation], timeout: 5.0)
    }
}
