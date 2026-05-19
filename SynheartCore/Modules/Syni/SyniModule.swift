// SPDX-License-Identifier: Apache-2.0
//
// Synheart-side gate around the Syni on-device agent SDK.
//
// Unlike Flutter's `package:syni` (which exposes a `SyniAgent` class
// with `chat()` / `chatStream()`), the native `SyniSwift` SDK is a
// different orchestration shape: a `Syni` class with a `.shared`
// singleton that owns `generate(request:completion:)` /
// `generateAsync(request:)`. This module wraps the singleton with a
// `ConsentType.syni` gate so consumers can't accidentally bypass the
// consent check by calling `Syni.shared` directly.

#if canImport(SyniSwift)
import Foundation
import SyniSwift

/// Thrown when a Syni call is attempted without `consent.syni == true`.
public struct SyniConsentDeniedError: Error, Sendable {
    public let message: String
    public init(message: String = "Syni access requires explicit user consent (ConsentType.syni).") {
        self.message = message
    }
}

/// Synheart-side facade around the `Syni` on-device agent SDK.
///
/// ```swift
/// let module = SyniModule(consent: Synheart.consentModule!)
/// try module.initialize(config: SyniConfig(...))
/// let response = try await module.generateAsync(request: request)
/// ```
///
/// Every call routing through this module first checks consent. The
/// gate is consent-only today; capability-token gating is the caller's
/// responsibility (use `Synheart.isFeatureOperational`).
public final class SyniModule: @unchecked Sendable {

    private let consent: ConsentProvider

    public init(consent: ConsentProvider) {
        self.consent = consent
    }

    /// Direct access to the underlying singleton. Bypasses the consent
    /// gate — use only when you've performed the check yourself (e.g.
    /// during initialization, before consent has been granted, in
    /// internal tooling). Nil when `Syni.initialize(config:)` hasn't
    /// been called yet.
    public var unsafeSyni: Syni? { Syni.shared }

    /// True if the user has granted SYNI consent on the current snapshot.
    public var isGateOpen: Bool { consent.current().syni }

    /// True if the underlying `Syni` singleton has been initialized
    /// AND is ready to serve generations. Mirrors `Syni.isReady`.
    /// Does not require the gate to be open.
    public var isReady: Bool { Syni.isReady }

    /// Initialize the underlying Syni SDK with `config`. Requires
    /// SYNI consent to be granted; throws `SyniConsentDeniedError`
    /// otherwise. Re-initialization is handled by the underlying SDK.
    public func initialize(config: SyniConfig) throws {
        try requireGate()
        try Syni.initialize(config: config)
    }

    /// Generate a response (callback variant). Gated.
    public func generate(
        request: SyniRequest,
        completion: @escaping (Result<SyniResponse, Error>) -> Void
    ) {
        do {
            try requireGate()
        } catch {
            completion(.failure(error))
            return
        }
        guard let syni = Syni.shared else {
            completion(.failure(SyniError.notInitialized))
            return
        }
        syni.generate(request: request) { result in
            switch result {
            case .success(let r): completion(.success(r))
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    /// Generate a response (async/throws variant). Gated.
    public func generateAsync(request: SyniRequest) async throws -> SyniResponse {
        try requireGate()
        guard let syni = Syni.shared else {
            throw SyniError.notInitialized
        }
        return try await syni.generateAsync(request: request)
    }

    /// Model manager (downloads / lookup / delete). Gated.
    public func models() throws -> ModelManager {
        try requireGate()
        guard let syni = Syni.shared else {
            throw SyniError.notInitialized
        }
        return syni.models
    }

    /// IDs of registered personas. Gated. Returns `[]` if Syni hasn't
    /// been initialized yet.
    public func availablePersonas() throws -> [String] {
        try requireGate()
        return Syni.shared?.availablePersonas ?? []
    }

    /// Reset the underlying Syni SDK (releases all resources;
    /// primarily for testing). Not gated — letting consent revocation
    /// drive a reset is the expected path.
    public func reset() {
        Syni.reset()
    }

    private func requireGate() throws {
        if !isGateOpen {
            throw SyniConsentDeniedError()
        }
    }
}
#endif
