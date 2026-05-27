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

    // MARK: - Reactive state is not gated

    func testCurrentStateObservableWithoutConsent() {
        let module = SyniModule(consent: FakeConsent())
        XCTAssertEqual(module.currentState, .notInstalled)
        XCTAssertFalse(module.isInstalled)
        XCTAssertFalse(module.hasCloud)
    }

    func testInstallStatePublisherObservableWithoutConsent() {
        let module = SyniModule(consent: FakeConsent())
        _ = module.installState  // confirm property is reachable
    }

    // MARK: - Gate enforcement

    func testChatThrowsConsentDeniedWhenDenied() async {
        let module = SyniModule(consent: FakeConsent())
        do {
            _ = try await module.chat("hi")
            XCTFail("expected SyniConsentDeniedError")
        } catch is SyniConsentDeniedError {
            // expected
        } catch {
            XCTFail("expected SyniConsentDeniedError, got \(error)")
        }
    }

    func testChatStreamThrowsConsentDeniedWhenDenied() {
        let module = SyniModule(consent: FakeConsent())
        XCTAssertThrowsError(try module.chatStream("hi")) { error in
            XCTAssertTrue(error is SyniConsentDeniedError)
        }
    }

    func testInstallThrowsConsentDeniedWhenDenied() async {
        let module = SyniModule(consent: FakeConsent())
        // SyniPersona/Model construction requires real values; use cloud
        // config-less defaults — the consent check fires before the
        // installer is touched, so these never get evaluated.
        do {
            try await module.install(
                persona: SyniSpecPersona.dummyPersona(),
                model: SyniModels.qwen25_15bInstructQ4
            )
            XCTFail("expected SyniConsentDeniedError")
        } catch is SyniConsentDeniedError {
            // expected
        } catch {
            XCTFail("expected SyniConsentDeniedError, got \(error)")
        }
    }

    // MARK: - Bypass

    func testUnsafeAgentReturnsSameReference() {
        let module = SyniModule(consent: FakeConsent())
        XCTAssertTrue(module.unsafeAgent === module.unsafeAgent)
    }
}

// MARK: - Test fixture helpers

private extension SyniSpecPersona {
    /// Cheap stand-in persona for gate-only tests. Gate check fires
    /// before this is ever inspected, so the field values are arbitrary.
    static func dummyPersona() -> SyniPersona {
        return SyniPersona(
            id: "test.persona.v1",
            displayName: "Test",
            systemPrompt: "test",
            responseSchemaId: "chat"
        )
    }
}
#endif
