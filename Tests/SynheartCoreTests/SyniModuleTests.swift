// SPDX-License-Identifier: Apache-2.0

#if canImport(SyniSwift)
import XCTest
import Combine
import SyniSwift
@testable import SynheartCore

final class SyniModuleTests: XCTestCase {

    /// In-memory ConsentProvider for gating tests; no DB / no Synheart.
    private final class FakeConsent: ConsentProvider, @unchecked Sendable {
        private let subject = CurrentValueSubject<ConsentSnapshot, Never>(.none())

        init(initial: ConsentSnapshot = .none()) {
            subject.send(initial)
        }

        func current() -> ConsentSnapshot { subject.value }
        func observe() -> AnyPublisher<ConsentSnapshot, Never> {
            subject.eraseToAnyPublisher()
        }
        func updateConsent(_ newConsent: ConsentSnapshot) async throws {
            subject.send(newConsent)
        }

        func setSyniGranted(_ value: Bool) {
            subject.send(subject.value.copyWith(syni: value))
        }
    }

    // MARK: - Gate visibility

    func testIsGateOpenFalseByDefault() {
        XCTAssertFalse(SyniModule(consent: FakeConsent()).isGateOpen)
    }

    func testIsGateOpenTrueAfterGrantingSyniConsent() {
        let consent = FakeConsent()
        let module = SyniModule(consent: consent)
        consent.setSyniGranted(true)
        XCTAssertTrue(module.isGateOpen)
    }

    func testIsGateOpenFlipsBackOnRevoke() {
        let consent = FakeConsent(initial: .none().copyWith(syni: true))
        let module = SyniModule(consent: consent)
        XCTAssertTrue(module.isGateOpen)
        consent.setSyniGranted(false)
        XCTAssertFalse(module.isGateOpen)
    }

    // MARK: - Gate enforcement

    func testGenerateAsyncThrowsWhenConsentDenied() async {
        let module = SyniModule(consent: FakeConsent())
        do {
            _ = try await module.generateAsync(
                request: SyniRequest(personaId: "test", input: SyniInput(text: "hello"))
            )
            XCTFail("expected SyniConsentDeniedError")
        } catch is SyniConsentDeniedError {
            // expected
        } catch {
            XCTFail("expected SyniConsentDeniedError, got \(error)")
        }
    }

    func testGenerateCallbackEmitsConsentDeniedFailure() {
        let module = SyniModule(consent: FakeConsent())
        let exp = expectation(description: "callback fires")
        module.generate(
            request: SyniRequest(personaId: "test", input: SyniInput(text: "hello"))
        ) { result in
            switch result {
            case .success: XCTFail("expected failure")
            case .failure(let error):
                XCTAssertTrue(error is SyniConsentDeniedError,
                              "expected SyniConsentDeniedError, got \(error)")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testAvailablePersonasThrowsWhenConsentDenied() {
        XCTAssertThrowsError(try SyniModule(consent: FakeConsent()).availablePersonas()) { error in
            XCTAssertTrue(error is SyniConsentDeniedError)
        }
    }

    func testModelsThrowsWhenConsentDenied() {
        XCTAssertThrowsError(try SyniModule(consent: FakeConsent()).models()) { error in
            XCTAssertTrue(error is SyniConsentDeniedError)
        }
    }

    // MARK: - Bypass + non-gated reads

    func testIsReadyDoesNotRequireTheGate() {
        // Without an initialized Syni in unit tests, this returns
        // false; the assertion is just that it returns rather than
        // throwing SyniConsentDeniedError.
        _ = SyniModule(consent: FakeConsent()).isReady
    }

    func testUnsafeSyniIsNilBeforeInitialize() {
        XCTAssertNil(SyniModule(consent: FakeConsent()).unsafeSyni)
    }
}
#endif
