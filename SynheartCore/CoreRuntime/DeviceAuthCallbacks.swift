// SPDX-License-Identifier: Apache-2.0
//
// Host-provided callback tables the native runtime drives for device auth:
//   1. Crypto callbacks  — backed by synheart-auth-swift's Secure Enclave
//      P-256 / App Attest implementation (`synheart_native_*` symbols).
//   2. Secure-storage callbacks — Keychain-backed key/value used to persist
//      consent tokens and device records across launches.
//
// All callbacks are non-capturing `@convention(c)` so they can be handed to
// the runtime as plain C function pointers.

import Foundation
import Security
import SynheartAuth

/// Mirrors the runtime's `#[repr(C)] SynheartSdkCryptoCallbacks` — five C
/// function pointers, in declaration order.
struct RuntimeCryptoCallbacks {
    var generate_key: @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    var sign_bytes: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<UInt8>?, Int) -> UnsafeMutablePointer<CChar>?
    var get_attestation: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<UInt8>?, Int) -> UnsafeMutablePointer<CChar>?
    var key_exists: @convention(c) (UnsafePointer<CChar>?) -> Int32
    var delete_key: @convention(c) (UnsafePointer<CChar>?) -> Int32
}

enum DeviceAuthCallbacks {

    /// Crypto table populated from `synheart-auth-swift`'s exported native
    /// symbols (Secure Enclave keygen/sign, App Attest, key existence/delete).
    ///
    /// Each field wraps the native function in a non-capturing thunk rather than
    /// referencing it directly: a direct `@convention(c)` reference to an
    /// `@_cdecl` symbol re-emits that C symbol here and collides with the
    /// definition in SynheartAuth. The wrapping call still forces SynheartAuth's
    /// crypto object file to link so the symbols resolve.
    static func cryptoCallbacks() -> RuntimeCryptoCallbacks {
        RuntimeCryptoCallbacks(
            generate_key: { deviceId in synheart_native_generate_key(deviceId) },
            sign_bytes: { deviceId, data, len in synheart_native_sign_bytes(deviceId, data, len) },
            get_attestation: { deviceId, hash, len in synheart_native_get_attestation(deviceId, hash, len) },
            key_exists: { deviceId in synheart_native_key_exists(deviceId) },
            delete_key: { deviceId in synheart_native_delete_key(deviceId) }
        )
    }

    // MARK: - Secure storage (Keychain generic-password key/value)

    /// `store(service, key, value) -> 0 on success`.
    static let store: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32 = { svc, key, val in
        guard let svc, let key, let val,
              let service = String(validatingUTF8: svc),
              let account = String(validatingUTF8: key),
              let value = String(validatingUTF8: val) else { return 1 }
        let data = Data(value.utf8)
        var query = baseQuery(service: service, account: account)
        // Upsert: try update first, then add.
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return 0 }
        query[kSecValueData as String] = data
        let added = SecItemAdd(query as CFDictionary, nil)
        return added == errSecSuccess ? 0 : 1
    }

    /// `load(service, key) -> newly malloc'd C string, or null`. The runtime
    /// frees the returned pointer, so it must be `strdup`-allocated (matching
    /// the synheart-auth-swift native callbacks' contract).
    ///
    /// Returns NULL ONLY when the item is genuinely absent. The C signature
    /// has no error channel, so a failed read — Keychain locked before first
    /// unlock, `securityd` not ready, an I/O fault — is retried with a short
    /// bounded backoff and, if it still fails, ALSO returns NULL. On a runtime
    /// ≥ 0.31.1 the provisioning marker turns that NULL into
    /// `ERR_SECURE_STORAGE_UNAVAILABLE` (retryable) instead of a re-minted
    /// storage master key; on an older runtime the re-mint — which orphans
    /// every blob sealed so far — remains (SDK-CONTRACT-CHANGES §4.4).
    /// Previously every non-success status returned NULL on the first try and
    /// read as "fresh install".
    static let load: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? = { svc, key in
        guard let svc, let key,
              let service = String(validatingUTF8: svc),
              let account = String(validatingUTF8: key) else { return nil }
        switch keychainLoadWithRetry(service: service, account: account) {
        case .found(let value):
            return strdup(value)
        case .absent:
            // The only case NULL is meant to express: no such item.
            return nil
        case .unavailable(let status):
            SynheartLogger.log(
                "[DeviceAuthCallbacks] secure_load(\(service), \(account)): Keychain "
                + "unavailable (OSStatus \(status)) after \(keychainLoadMaxAttempts) "
                + "attempts — returning NULL, which the runtime cannot tell from absent")
            return nil
        }
    }

    /// Outcome of a Keychain read. Kept as three cases because the C callback
    /// can express only two (pointer or NULL) and the runtime reads NULL as
    /// "no such key": collapsing a *failed* read into NULL is what made a
    /// locked Keychain look like a fresh install.
    enum KeychainLoad: Equatable {
        case found(String)
        case absent
        case unavailable(OSStatus)
    }

    /// Bounded retry budget for a transiently unavailable Keychain. Total wait
    /// is ~1.5 s (100 + 200 + 400 + 800 ms): short enough to hold the runtime
    /// mutex during `set_storage_callbacks` without tripping a launch
    /// watchdog, long enough to ride out the unlock transition and the
    /// occasional `errSecNotAvailable` right after boot.
    static let keychainLoadMaxAttempts = 5
    private static let keychainLoadInitialBackoffMicros: UInt32 = 100_000

    static func keychainLoadOnce(service: String, account: String) -> KeychainLoad {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .absent }
        guard status == errSecSuccess, let data = item as? Data else {
            return .unavailable(status)
        }
        guard let value = String(data: data, encoding: .utf8) else {
            // The item exists but is not the UTF-8 the runtime wrote. Not
            // absent — reporting it as such would re-mint over a real, if
            // unreadable, key.
            return .unavailable(errSecDecode)
        }
        return .found(value)
    }

    /// Statuses worth waiting on: the item may well exist, the store just
    /// cannot serve it right now. Anything else (bad params, entitlement,
    /// decode) is reported immediately.
    static func keychainStatusIsTransient(_ status: OSStatus) -> Bool {
        switch status {
        case errSecInteractionNotAllowed,  // device locked / before first unlock
             errSecNotAvailable,           // securityd not ready
             errSecIO:
            return true
        default:
            return false
        }
    }

    /// `keychainLoadOnce` with a bounded backoff on transient failures. Never
    /// converts a failure into `.absent`.
    static func keychainLoadWithRetry(service: String, account: String) -> KeychainLoad {
        var backoff = keychainLoadInitialBackoffMicros
        for attempt in 1...keychainLoadMaxAttempts {
            let outcome = keychainLoadOnce(service: service, account: account)
            guard case .unavailable(let status) = outcome,
                  keychainStatusIsTransient(status),
                  attempt < keychainLoadMaxAttempts else {
                return outcome
            }
            SynheartLogger.log(
                "[DeviceAuthCallbacks] secure_load(\(service), \(account)): Keychain "
                + "transiently unavailable (OSStatus \(status)), retry \(attempt)/"
                + "\(keychainLoadMaxAttempts - 1)")
            usleep(backoff)
            backoff *= 2
        }
        // Unreachable: the loop returns on its last iteration.
        return .absent
    }

    /// `delete(service, key) -> 0 on success` (also success when absent).
    static let delete: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32 = { svc, key in
        guard let svc, let key,
              let service = String(validatingUTF8: svc),
              let account = String(validatingUTF8: key) else { return 1 }
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        return (status == errSecSuccess || status == errSecItemNotFound) ? 0 : 1
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        // Use the iOS-style data-protection keychain on macOS so the same
        // generic-password semantics apply across platforms.
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }
}
