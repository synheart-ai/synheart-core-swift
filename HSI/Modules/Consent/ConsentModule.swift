import Foundation
import Combine

/// Consent Module
///
/// Single source of truth for user consent on the device.
/// Gates collection and export of biosignals, behavior, motion/context,
/// cloud upload, and Syni personalization.
public class ConsentModule: BaseSynheartModule, ConsentProvider {
    private let storage: ConsentStorage
    private let consentSubject = CurrentValueSubject<ConsentSnapshot?, Never>(nil)
    private var currentConsent: ConsentSnapshot?

    /// Callbacks for when consent changes
    private var listeners: [(ConsentSnapshot) -> Void] = []

    public init(storage: ConsentStorage? = nil) {
        self.storage = storage ?? ConsentStorage()
        super.init(moduleId: "consent")
    }

    // MARK: - ConsentProvider

    public func current() -> ConsentSnapshot {
        guard let consent = currentConsent else {
            fatalError("Consent module not initialized")
        }
        return consent
    }

    public func observe() -> AnyPublisher<ConsentSnapshot, Never> {
        return consentSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    public func updateConsent(_ newConsent: ConsentSnapshot) async throws {
        let oldConsent = currentConsent
        currentConsent = newConsent

        // Persist to storage
        try storage.save(newConsent)

        // Emit to stream
        consentSubject.send(newConsent)

        // Notify listeners
        notifyListeners(newConsent)

        // Check for consent revocations and log
        if let oldConsent = oldConsent {
            logConsentChanges(old: oldConsent, new: newConsent)
        }
    }

    // MARK: - Public API

    /// Register a listener for consent changes
    public func addListener(_ listener: @escaping (ConsentSnapshot) -> Void) {
        listeners.append(listener)
    }

    /// Remove all listeners (no way to remove specific listener without identity)
    public func clearListeners() {
        listeners.removeAll()
    }

    /// Load consent from storage or use defaults
    public func loadConsent() async throws {
        if let stored = try storage.load() {
            currentConsent = stored
            consentSubject.send(stored)
        } else {
            // No stored consent, use defaults (all denied for safety)
            let defaultConsent = ConsentSnapshot.none()
            currentConsent = defaultConsent
            consentSubject.send(defaultConsent)
        }
    }

    /// Grant all consents
    public func grantAll() async throws {
        try await updateConsent(ConsentSnapshot.all())
    }

    /// Revoke all consents
    public func revokeAll() async throws {
        try await updateConsent(ConsentSnapshot.none())
    }

    /// Update a specific consent type
    public func updateConsentType(_ type: ConsentType, granted: Bool) async throws {
        guard let current = currentConsent else {
            throw NSError(domain: "ConsentModule", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Consent module not initialized"
            ])
        }

        let updated = current.copyWith(
            biosignals: type == .biosignals ? granted : current.biosignals,
            behavior: type == .behavior ? granted : current.behavior,
            motion: type == .motion ? granted : current.motion,
            cloudUpload: type == .cloudUpload ? granted : current.cloudUpload,
            syni: type == .syni ? granted : current.syni,
            timestamp: Date()
        )

        try await updateConsent(updated)
    }

    // MARK: - Private Methods

    /// Notify all registered listeners
    private func notifyListeners(_ consent: ConsentSnapshot) {
        for listener in listeners {
            listener(consent)
        }
    }

    /// Log consent changes for debugging
    private func logConsentChanges(old: ConsentSnapshot, new: ConsentSnapshot) {
        if old.biosignals != new.biosignals {
            print("Consent changed: biosignals \(new.biosignals ? "granted" : "revoked")")
        }
        if old.behavior != new.behavior {
            print("Consent changed: behavior \(new.behavior ? "granted" : "revoked")")
        }
        if old.motion != new.motion {
            print("Consent changed: motion \(new.motion ? "granted" : "revoked")")
        }
        if old.cloudUpload != new.cloudUpload {
            print("Consent changed: cloudUpload \(new.cloudUpload ? "granted" : "revoked")")
        }
        if old.syni != new.syni {
            print("Consent changed: syni \(new.syni ? "granted" : "revoked")")
        }
    }

    // MARK: - Module Lifecycle

    override public func onInitialize() async throws {
        try await loadConsent()
    }

    override public func onStart() async throws {
        // Nothing to start
    }

    override public func onStop() async throws {
        // Nothing to stop
    }

    override public func onDispose() async throws {
        consentSubject.send(nil)
        listeners.removeAll()
        currentConsent = nil
    }
}
