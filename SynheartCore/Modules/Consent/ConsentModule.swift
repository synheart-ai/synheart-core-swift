import Foundation
import Combine
import Security

/// Consent Module — thin wrapper delegating core logic to the native runtime via CoreRuntimeBridge.
///
/// Platform-specific concerns (Keychain device ID, Combine publishers, UI hooks) stay here.
public class ConsentModule: BaseSynheartModule, ConsentProvider {
    private let consentSubject = CurrentValueSubject<ConsentSnapshot?, Never>(nil)
    private var currentConsent: ConsentSnapshot?
    private var listeners: [(ConsentSnapshot) -> Void] = []
    private weak var bridge: CoreRuntimeBridge?

    private static let deviceIdKey = "synheart_device_id"
    private let keychainService = "ai.synheart.hsi"

    public init(bridge: CoreRuntimeBridge? = nil) {
        self.bridge = bridge
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
        currentConsent = newConsent
        consentSubject.send(newConsent)
        notifyListeners(newConsent)
    }

    // MARK: - Public API

    public func addListener(_ listener: @escaping (ConsentSnapshot) -> Void) {
        listeners.append(listener)
    }

    public func clearListeners() {
        listeners.removeAll()
    }

    public func grantAll() async throws {
        let snapshot = ConsentSnapshot.all()
        try await updateConsent(snapshot)
    }

    public func revokeAll() async throws {
        let snapshot = ConsentSnapshot.none()
        try await updateConsent(snapshot)
    }

    public func updateConsentType(_ type: ConsentType, granted: Bool) async throws {
        if granted {
            bridge?.grantConsent(type: type.rawValue)
        } else {
            bridge?.revokeConsent(type: type.rawValue)
        }

        if let json = bridge?.currentConsent(),
           let data = json.data(using: .utf8),
           let snapshot = try? JSONDecoder().decode(ConsentSnapshot.self, from: data) {
            try await updateConsent(snapshot)
        }
    }

    public func checkConsentStatus() -> ConsentStatus {
        guard let bridge = bridge else { return .pending }
        let json = bridge.currentConsent()
        if json == nil { return .pending }
        return .granted
    }

    public func denyConsent() async throws {
        try await updateConsent(ConsentSnapshot.none())
        SynheartLogger.log("[ConsentModule] Consent explicitly denied by user")
    }

    // MARK: - Compat shims (post native-runtime migration)

    /// Returns the current auth token, if any. The pre-migration
    /// SDK held an in-process token here; the runtime owns it now.
    /// Returns `nil` until the SDK shell is wired to the runtime
    /// auth FFI (separate sit). Marked deprecated to flag the gap.
    @available(*, deprecated, message: "Stub — wire to runtime auth FFI.")
    public func getCurrentToken() -> AuthTokenStub? {
        return nil
    }

    /// Revoke all consent. The pre-migration SDK called the auth
    /// service directly; the runtime now owns this. Wires to
    /// `revokeAll()` so the in-process snapshot stays consistent
    /// with the user's intent until the runtime revoke FFI lands.
    public func revokeConsent() throws {
        Task { try? await self.revokeAll() }
    }

    /// Install a request-signing closure used by the auth-aware
    /// HTTP layer. The pre-migration SDK plumbed this through
    /// `synheart-auth-swift`; restore that wiring in a follow-on sit.
    @available(*, deprecated, message: "Stub — wire to synheart-auth-swift signer.")
    public func setDeviceSigner(
        _ signer: @escaping (String, String, Data?) throws -> [String: String]
    ) {
        // Hold the closure so future code can invoke it; for now
        // it's intentionally not called by anything in the SDK.
        _deviceSigner = signer
    }

    private var _deviceSigner: ((String, String, Data?) throws -> [String: String])?

    // MARK: - Platform-specific: Keychain device ID

    func getOrGenerateDeviceId() async throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.deviceIdKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let existingId = String(data: data, encoding: .utf8), !existingId.isEmpty {
            return existingId
        }

        let deviceId = UUID().uuidString

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.deviceIdKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: Self.deviceIdKey,
            kSecValueData as String: Data(deviceId.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)

        SynheartLogger.log("[ConsentModule] Generated new device ID: \(deviceId)")
        return deviceId
    }

    // MARK: - Private

    private func notifyListeners(_ consent: ConsentSnapshot) {
        for listener in listeners {
            listener(consent)
        }
    }

    // MARK: - Module Lifecycle

    override public func onInitialize() async throws {
        let defaultConsent = ConsentSnapshot.none()
        currentConsent = defaultConsent
        consentSubject.send(defaultConsent)
    }

    override public func onDispose() async throws {
        consentSubject.send(nil)
        listeners.removeAll()
        currentConsent = nil
    }
}
