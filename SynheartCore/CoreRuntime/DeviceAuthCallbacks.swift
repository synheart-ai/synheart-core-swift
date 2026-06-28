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
    static let load: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? = { svc, key in
        guard let svc, let key,
              let service = String(validatingUTF8: svc),
              let account = String(validatingUTF8: key) else { return nil }
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return strdup(value)
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
