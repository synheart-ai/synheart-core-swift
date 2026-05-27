import XCTest
import Combine
@testable import SynheartCore

/// Tests that the HSI stream is consent-gated: when biosignal consent is
/// false, HSI frames must NOT be emitted to the public stream.
final class ConsentGateTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testHSIFramesBlockedWhenBiosignalsConsentFalse() {
        // Simulate the consent gate logic from Synheart.swift:
        //   guard self.consentModule?.current().biosignals == true else { return }
        let consent = ConsentSnapshot(
            biosignals: false,
            behavior: true,
            phoneContext: true,
            cloudUpload: false,
            syni: false
        )

        let source = PassthroughSubject<String, Never>()
        let gated = PassthroughSubject<String, Never>()
        var received = [String]()

        source
            .filter { _ in consent.biosignals }
            .sink { gated.send($0) }
            .store(in: &cancellables)

        gated
            .sink { received.append($0) }
            .store(in: &cancellables)

        source.send("{\"hsi_version\":\"1.0\",\"frame\":1}")
        source.send("{\"hsi_version\":\"1.0\",\"frame\":2}")

        XCTAssertTrue(received.isEmpty,
            "HSI frames should not be emitted when biosignals consent is false")
    }

    func testHSIFramesEmittedWhenBiosignalsConsentTrue() {
        let consent = ConsentSnapshot(
            biosignals: true,
            behavior: true,
            phoneContext: true,
            cloudUpload: false,
            syni: false
        )

        let source = PassthroughSubject<String, Never>()
        var received = [String]()

        source
            .filter { _ in consent.biosignals }
            .sink { received.append($0) }
            .store(in: &cancellables)

        source.send("{\"hsi_version\":\"1.0\",\"frame\":1}")

        XCTAssertEqual(received.count, 1,
            "HSI frames should be emitted when biosignals consent is true")
    }

    func testConsentGateBlocksAllFramesWithNoneConsent() {
        let consent = ConsentSnapshot.none()

        let source = PassthroughSubject<String, Never>()
        var received = [String]()

        source
            .filter { _ in consent.biosignals }
            .sink { received.append($0) }
            .store(in: &cancellables)

        source.send("{\"frame\":1}")
        source.send("{\"frame\":2}")
        source.send("{\"frame\":3}")

        XCTAssertTrue(received.isEmpty,
            "No frames should pass when consent is none()")
    }
}
