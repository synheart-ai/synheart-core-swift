import XCTest
import Combine
@testable import SynheartCore

final class SignalProcessorTests: XCTestCase {
    var processor: SignalProcessor!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        processor = SignalProcessor()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables.removeAll()
        processor = nil
        super.tearDown()
    }

    // MARK: - Heart Rate Processing Tests

    func testHeartRateProcessing() {
        let expectation = XCTestExpectation(description: "Process heart rate signals")

        processor.processedPublisher
            .sink { processed in
                XCTAssertNotNil(processed.heartRate, "Heart rate should be processed")
                XCTAssertGreaterThan(processed.heartRate!, 0, "Heart rate should be positive")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Send heart rate signals
        let signal = SignalData(
            type: .heartRate,
            value: 75.0,
            timestamp: Date(),
            source: .healthKit
        )
        processor.process(signal)

        wait(for: [expectation], timeout: 2.0)
    }

    func testHeartRateOutlierRemoval() {
        let expectation = XCTestExpectation(description: "Remove outlier heart rates")

        processor.processedPublisher
            .sink { processed in
                if let hr = processed.heartRate {
                    // Outliers should be filtered out, result should be near 75
                    XCTAssertGreaterThan(hr, 60)
                    XCTAssertLessThan(hr, 90)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Send normal values
        for _ in 0..<10 {
            processor.process(SignalData(
                type: .heartRate,
                value: Float.random(in: 70...80),
                timestamp: Date(),
                source: .healthKit
            ))
        }

        // Send outlier
        processor.process(SignalData(
            type: .heartRate,
            value: 200.0, // Outlier
            timestamp: Date(),
            source: .healthKit
        ))

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - HRV Processing Tests

    func testHRVProcessing() {
        let expectation = XCTestExpectation(description: "Process HRV signals")

        processor.processedPublisher
            .sink { processed in
                if processed.heartRateVariability != nil {
                    XCTAssertNotNil(processed.heartRateVariability)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let signal = SignalData(
            type: .heartRateVariability,
            value: 50.0,
            timestamp: Date(),
            source: .healthKit
        )
        processor.process(signal)

        wait(for: [expectation], timeout: 2.0)
    }

    func testRMSSDCalculation() {
        let expectation = XCTestExpectation(description: "Calculate RMSSD")

        processor.processedPublisher
            .sink { processed in
                if let rmssd = processed.rmssd {
                    XCTAssertGreaterThan(rmssd, 0, "RMSSD should be positive")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Send multiple HRV values
        let values: [Float] = [50, 52, 48, 51, 49, 53, 47, 50]
        for value in values {
            processor.process(SignalData(
                type: .heartRateVariability,
                value: value,
                timestamp: Date(),
                source: .healthKit
            ))
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testSDNNCalculation() {
        let expectation = XCTestExpectation(description: "Calculate SDNN")

        processor.processedPublisher
            .sink { processed in
                if let sdnn = processed.sdnn {
                    XCTAssertGreaterThan(sdnn, 0, "SDNN should be positive")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Send multiple HRV values with variation
        let values: [Float] = [50, 55, 45, 52, 48, 54, 46, 51]
        for value in values {
            processor.process(SignalData(
                type: .heartRateVariability,
                value: value,
                timestamp: Date(),
                source: .healthKit
            ))
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Behavioral Signal Tests

    func testTypingRateCalculation() {
        let expectation = XCTestExpectation(description: "Calculate typing rate")

        processor.processedPublisher
            .sink { processed in
                if let typingSpeed = processed.typingSpeed {
                    XCTAssertGreaterThan(typingSpeed, 0, "Typing rate should be positive")
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Send typing signals over time
        let startTime = Date()
        for i in 0..<10 {
            processor.process(SignalData(
                type: .typing,
                value: 1.0,
                timestamp: startTime.addingTimeInterval(TimeInterval(i)),
                source: .phoneSDK
            ))
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testScrollingRateCalculation() {
        let expectation = XCTestExpectation(description: "Calculate scrolling rate")

        processor.processedPublisher
            .sink { processed in
                if let scrollVelocity = processed.scrollVelocity {
                    XCTAssertGreaterThanOrEqual(scrollVelocity, 0)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let startTime = Date()
        for i in 0..<5 {
            processor.process(SignalData(
                type: .scrolling,
                value: Float.random(in: 10...100),
                timestamp: startTime.addingTimeInterval(TimeInterval(i)),
                source: .phoneSDK
            ))
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testAppSwitchRateCalculation() {
        let expectation = XCTestExpectation(description: "Calculate app switch rate")

        processor.processedPublisher
            .sink { processed in
                if let appSwitchRate = processed.appSwitchRate {
                    XCTAssertGreaterThan(appSwitchRate, 0)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        let startTime = Date()
        for i in 0..<3 {
            processor.process(SignalData(
                type: .appSwitch,
                value: 1.0,
                timestamp: startTime.addingTimeInterval(TimeInterval(i * 5)),
                source: .phoneSDK
            ))
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Windowing Tests

    func testSignalWindowing() {
        let expectation = XCTestExpectation(description: "Test signal windowing")
        expectation.expectedFulfillmentCount = 2

        var processedCount = 0
        processor.processedPublisher
            .sink { _ in
                processedCount += 1
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Send signals beyond the window size (30 seconds)
        let startTime = Date()
        processor.process(SignalData(
            type: .heartRate,
            value: 70.0,
            timestamp: startTime,
            source: .healthKit
        ))

        // Signal 35 seconds later (outside window)
        processor.process(SignalData(
            type: .heartRate,
            value: 75.0,
            timestamp: startTime.addingTimeInterval(35),
            source: .healthKit
        ))

        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(processedCount, 2, "Should process both signals")
    }

    // MARK: - Edge Cases

    func testEmptySignalBuffer() {
        let expectation = XCTestExpectation(description: "Handle empty buffer")

        processor.processedPublisher
            .sink { processed in
                // Should not crash with empty signals
                XCTAssertNil(processed.heartRate)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Process a signal for a different type to trigger emission
        processor.process(SignalData(
            type: .motion,
            value: 1.0,
            timestamp: Date(),
            source: .coreMotion
        ))

        wait(for: [expectation], timeout: 2.0)
    }

    func testZeroValues() {
        let expectation = XCTestExpectation(description: "Handle zero values")

        processor.processedPublisher
            .sink { processed in
                if let hr = processed.heartRate {
                    XCTAssertEqual(hr, 0.0)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        processor.process(SignalData(
            type: .heartRate,
            value: 0.0,
            timestamp: Date(),
            source: .healthKit
        ))

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Performance Tests

    func testProcessingPerformance() {
        measure {
            for _ in 0..<100 {
                processor.process(SignalData(
                    type: .heartRate,
                    value: Float.random(in: 60...100),
                    timestamp: Date(),
                    source: .healthKit
                ))
            }
        }
    }
}
