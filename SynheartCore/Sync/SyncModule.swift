import Foundation

/// High-level sync orchestrator (RFC-CORE-0005).
///
/// Uses ConsentModule for access tokens (scoped JWT from consent-service).
/// session_secret and subjectId are provided directly by the Synheart entry point.
public class SyncModule {
    private let consent: ConsentModule
    private let storage: StorageManager
    private let engine: SyncEngine

    private var urk: URK?
    private var smk: SMK?
    private let subjectId: String?
    private let sessionSecret: String?
    private(set) var enabled = false
    private(set) var syncReady = false

    init(consent: ConsentModule, storage: StorageManager, smk: SMK?, baseUrl: String,
         subjectId: String? = nil, sessionSecret: String? = nil) {
        self.consent = consent
        self.storage = storage
        self.smk = smk
        self.subjectId = subjectId
        self.sessionSecret = sessionSecret
        self.engine = SyncEngine(storage: storage, baseUrl: baseUrl)
    }

    /// Get the current access token from ConsentModule.
    private var accessToken: String? {
        consent.getCurrentToken()?.token
    }

    /// Check if we have a valid consent token.
    private var hasValidToken: Bool {
        consent.getCurrentToken() != nil
    }

    /// Enable or disable sync.
    func setSyncEnabled(_ enabled: Bool) async {
        self.enabled = enabled
        try? storage.setSyncStateValue(key: "sync_enabled", value: enabled ? "true" : "false")

        if enabled && urk == nil && hasValidToken {
            await provisionURK()
        }
    }

    static let maxRetries = 3
    static let initialBackoffSeconds: UInt64 = 1

    /// Execute a sync cycle (push + pull) with retry.
    func syncNow() async -> SyncResult {
        guard enabled, hasValidToken else {
            return SyncResult()
        }

        engine.accessToken = accessToken

        if urk == nil {
            urk = try? URK.unwrap()
            if urk == nil {
                await provisionURK()
            }
        }

        guard let urk = urk else { return SyncResult(errors: ["URK unavailable"]) }
        guard let smk = smk else { return SyncResult(errors: ["SMK unavailable"]) }

        var pushed = 0
        var pulled = 0
        var errors: [String] = []

        // Push with retry
        var didRefreshForPush = false
        for attempt in 0..<SyncModule.maxRetries {
            do {
                pushed = try await engine.push(urk: urk.bytes)
                break
            } catch let error as AuthError {
                if !didRefreshForPush {
                    didRefreshForPush = true
                    _ = await consent.refreshTokenIfNeeded()
                    engine.accessToken = accessToken
                } else {
                    errors.append("Push failed: \(error)")
                    break
                }
            } catch {
                if attempt == SyncModule.maxRetries - 1 {
                    errors.append("Push failed: \(error)")
                } else {
                    let backoff = SyncModule.initialBackoffSeconds << UInt64(attempt)
                    try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                }
            }
        }

        // Pull with retry
        var didRefreshForPull = false
        for attempt in 0..<SyncModule.maxRetries {
            do {
                let cursor = try storage.getSyncStateValue(key: "cursor")
                pulled = try await engine.pull(
                    urk: urk.bytes,
                    smk: smk,
                    subjectId: subjectId ?? "",
                    cursor: cursor
                )
                break
            } catch let error as AuthError {
                if !didRefreshForPull {
                    didRefreshForPull = true
                    _ = await consent.refreshTokenIfNeeded()
                    engine.accessToken = accessToken
                } else {
                    errors.append("Pull failed: \(error)")
                    break
                }
            } catch {
                if attempt == SyncModule.maxRetries - 1 {
                    errors.append("Pull failed: \(error)")
                } else {
                    let backoff = SyncModule.initialBackoffSeconds << UInt64(attempt)
                    try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                }
            }
        }

        if errors.isEmpty {
            let nowMs = Int(Date().timeIntervalSince1970 * 1000)
            try? storage.setSyncStateValue(key: "last_sync_ms", value: "\(nowMs)")
        }

        return SyncResult(pushed: pushed, pulled: pulled, errors: errors)
    }

    /// Get current sync status.
    func getStatus() -> SyncStatus {
        let cursor = try? storage.getSyncStateValue(key: "cursor")
        let lastSyncStr = try? storage.getSyncStateValue(key: "last_sync_ms")
        let pendingCount = (try? storage.getUnsyncedCount()) ?? 0

        return SyncStatus(
            enabled: enabled,
            lastSuccessMs: lastSyncStr.flatMap { Int($0) },
            pendingUploadCount: pendingCount,
            cursor: cursor
        )
    }

    private func provisionURK() async {
        guard let sessionSecret = sessionSecret, let subjectId = subjectId else { return }
        guard let token = accessToken else { return }

        // Try to fetch existing URK bundle from server
        do {
            var request = URLRequest(url: URL(string: "\(engine.baseUrl)/sync/v1/urk-bundle")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let bundle = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                let restored = try URK.decryptBundle(bundle: bundle, sessionSecret: sessionSecret, subjectId: subjectId)
                try restored.wrapAndStore()
                self.urk = restored
                syncReady = true
                return
            }
        } catch {
            // Fall through to generate new URK
        }

        // Generate new URK
        let newUrk = URK.generate()
        do {
            let bundle = try URK.encryptBundle(urk: newUrk.bytes, sessionSecret: sessionSecret, subjectId: subjectId)
            var request = URLRequest(url: URL(string: "\(engine.baseUrl)/sync/v1/urk-bundle")!)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: bundle)
            let _ = try await URLSession.shared.data(for: request)
        } catch {
            // Upload failed — URK still usable locally
        }

        try? newUrk.wrapAndStore()
        self.urk = newUrk
        syncReady = true
    }

    func dispose() {
        urk = nil
        enabled = false
    }
}
