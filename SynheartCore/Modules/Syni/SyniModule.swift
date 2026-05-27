// SPDX-License-Identifier: Apache-2.0
//
// Synheart-side gate around the Syni on-device agent SDK.
//
// Mirrors the Flutter shape: `SyniAgent` actor + install lifecycle
// state machine + typed `chat()` / `chatStream()` returning
// `SyniChatResponse` and `SyniChatEvent` respectively. The underlying
// `SyniSwift.SyniAgent` is wrapped with a `consent.syni` gate so
// consumers can't accidentally bypass the consent check.
//
// API note: matches the post-alignment SyniSwift package (0.0.2+,
// `chore/align-public-api-to-flutter-shape` and later). The earlier
// `Syni` singleton shape is gone.

#if canImport(SyniSwift)
import Combine
import Foundation
import SyniSwift

/// Thrown when a Syni call is attempted without `consent.syni == true`.
public struct SyniConsentDeniedError: Error, Sendable {
    public let message: String
    public init(message: String = "Syni access requires explicit user consent (ConsentType.syni).") {
        self.message = message
    }
}

/// Synheart-side facade around the `SyniAgent` on-device agent SDK.
///
/// ```swift
/// let module = SyniModule(consent: consentModule, cloudConfig: cfg)
/// try await module.install(persona: persona, model: model)
/// let resp = try await module.chat("hi")
/// ```
///
/// Every method that touches the agent first checks consent; throws
/// `SyniConsentDeniedError` when denied. The reactive `installState` /
/// `currentState` / `hasCloud` / `isInstalled` reads are not gated —
/// they're cheap state observations consumers may legitimately need
/// before deciding to ask for consent.
public final class SyniModule: @unchecked Sendable {

    private let consent: ConsentProvider

    /// Direct access to the underlying agent. Bypasses the consent
    /// gate — use only when you've performed the check yourself
    /// (e.g. during initialization, before consent has been granted,
    /// in internal tooling).
    public let unsafeAgent: SyniAgent

    public init(
        consent: ConsentProvider,
        installer: SyniInstaller? = nil,
        cloudConfig: SyniCloudConfig? = nil
    ) {
        self.consent = consent
        self.unsafeAgent = SyniAgent(installer: installer, cloudConfig: cloudConfig)
    }

    /// True if the user has granted SYNI consent on the current snapshot.
    public var isGateOpen: Bool { consent.current().syni }

    // MARK: - Reactive state (not gated)

    public var installState: AnyPublisher<SyniInstallState, Never> { unsafeAgent.installState }
    public var currentState: SyniInstallState { unsafeAgent.currentState }
    public var isInstalled: Bool { unsafeAgent.isInstalled }
    public var hasCloud: Bool { unsafeAgent.hasCloud }

    // MARK: - Lifecycle

    /// Install `persona` with `model`. Gated; async/throws.
    public func install(persona: SyniPersona, model: SyniModelSpec) async throws {
        try requireGate()
        try await unsafeAgent.install(persona: persona, model: model)
    }

    /// Restore an existing install if the on-disk state matches
    /// `persona` + `model`. Gated; returns true on successful restore.
    public func restoreInstallIfReady(persona: SyniPersona, model: SyniModelSpec) async throws -> Bool {
        try requireGate()
        return await unsafeAgent.restoreInstallIfReady(persona: persona, model: model)
    }

    /// Uninstall the current persona + model. Gated.
    public func uninstall() async throws {
        try requireGate()
        await unsafeAgent.uninstall()
    }

    /// Release resources held by the underlying runtime. Not gated.
    public func dispose() async {
        await unsafeAgent.dispose()
    }

    // MARK: - Chat

    /// Single-turn chat. Returns the assembled `SyniChatResponse`. Gated.
    public func chat(
        _ message: String,
        hsiContext: [String: Any]? = nil,
        seed: UInt64 = 0,
        mode: SyniExecutionMode = .localFirst
    ) async throws -> SyniChatResponse {
        try requireGate()
        return try await unsafeAgent.chat(message, hsiContext: hsiContext, seed: seed, mode: mode)
    }

    /// Streaming chat. Emits `SyniChatEvent` (`.delta` / `.final`).
    /// Gate is checked at call time; revoking consent mid-stream does
    /// NOT cancel the in-flight generation.
    public func chatStream(
        _ message: String,
        hsiContext: [String: Any]? = nil,
        seed: UInt64 = 0,
        mode: SyniExecutionMode = .localFirst
    ) throws -> AsyncThrowingStream<SyniChatEvent, Error> {
        try requireGate()
        return unsafeAgent.chatStream(message, hsiContext: hsiContext, seed: seed, mode: mode)
    }

    private func requireGate() throws {
        if !isGateOpen {
            throw SyniConsentDeniedError()
        }
    }
}
#endif
