import Foundation

/// High-level sync orchestrator (RFC-CORE-0005).
public class SyncModule {
    private let auth: AuthModule
    private let storage: StorageManager
    private let engine: SyncEngine
    private let baseUrl: String
    private var urk: URK?
    private var smk: SMK?
    private(set) var enabled = false

    private static let maxRetries = 3
    private static let initialBackoffSeconds: UInt64 = 1

    init(auth: AuthModule, storage: StorageManager, smk: SMK?, baseUrl: String) {
        self.auth = auth
        self.storage = storage
        self.smk = smk
        self.baseUrl = baseUrl
        self.engine = SyncEngine(storage: storage, baseUrl: baseUrl)
    }

    /// Enable or disable sync.
    public func setSyncEnabled(_ enabled: Bool) async throws {
        self.enabled = enabled
        try storage.setSyncState(key: "sync_enabled", value: enabled ? "true" : "false")

        if enabled && urk == nil && auth.isAuthenticated {
            try await provisionURK()
        }
    }

    /// Execute a sync cycle (push + pull) with retry and exponential backoff.
    public func syncNow() async throws -> SyncResult {
        guard enabled, auth.isAuthenticated else {
            return SyncResult()
        }

        engine.accessToken = auth.accessToken

        if urk == nil {
            urk = try URK.unwrap()
            if urk == nil {
                try await provisionURK()
            }
        }

        guard let urk = urk, let smk = smk else {
            return SyncResult(errors: ["URK or SMK unavailable"])
        }

        var errors: [String] = []
        var pushed = 0
        var pulled = 0

        // Push with retry
        var didRefreshForPush = false
        for attempt in 0..<SyncModule.maxRetries {
            do {
                pushed = try await engine.push(urk: urk.bytes)
                break
            } catch let error as AuthError {
                if !didRefreshForPush {
                    didRefreshForPush = true
                    do {
                        try await auth.refreshToken()
                        engine.accessToken = auth.accessToken
                    } catch {
                        errors.append("Push failed: auth refresh failed: \(error)")
                        break
                    }
                } else {
                    errors.append("Push failed: \(error)")
                    break
                }
            } catch {
                if attempt == SyncModule.maxRetries - 1 {
                    errors.append("Push failed: \(error)")
                } else {
                    let backoff = SyncModule.initialBackoffSeconds << UInt64(attempt)
                    try await Task.sleep(nanoseconds: backoff * 1_000_000_000)
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
                    subjectId: auth.subjectId ?? "",
                    cursor: cursor
                )
                break
            } catch let error as AuthError {
                if !didRefreshForPull {
                    didRefreshForPull = true
                    do {
                        try await auth.refreshToken()
                        engine.accessToken = auth.accessToken
                    } catch {
                        errors.append("Pull failed: auth refresh failed: \(error)")
                        break
                    }
                } else {
                    errors.append("Pull failed: \(error)")
                    break
                }
            } catch {
                if attempt == SyncModule.maxRetries - 1 {
                    errors.append("Pull failed: \(error)")
                } else {
                    let backoff = SyncModule.initialBackoffSeconds << UInt64(attempt)
                    try await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                }
            }
        }

        if errors.isEmpty {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            try storage.setSyncState(key: "last_sync_ms", value: String(nowMs))
        }

        return SyncResult(pushed: pushed, pulled: pulled, errors: errors)
    }

    /// Get current sync status.
    public func getStatus() throws -> SyncStatus {
        let cursor = try storage.getSyncStateValue(key: "cursor")
        let lastSyncStr = try storage.getSyncStateValue(key: "last_sync_ms")
        let pendingCount = try storage.getUnsyncedCount()

        return SyncStatus(
            enabled: enabled,
            lastSuccessMs: lastSyncStr.flatMap { Int64($0) },
            pendingUploadCount: pendingCount,
            cursor: cursor
        )
    }

    private func provisionURK() async throws {
        guard let sessionSecret = auth.sessionSecret,
              let subjectId = auth.subjectId,
              let token = auth.accessToken else { return }

        // 1. Try to fetch existing bundle from server
        let bundleUrl = URL(string: "\(baseUrl)/v1/sync/urk-bundle")!
        var getRequest = URLRequest(url: bundleUrl)
        getRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (getData, getResponse) = try await URLSession.shared.data(for: getRequest)

        if let httpResponse = getResponse as? HTTPURLResponse, httpResponse.statusCode == 200,
           let body = try? JSONSerialization.jsonObject(with: getData) as? [String: Any] {
            // Found existing bundle — decrypt it
            let existingUrk = try URK.decryptBundle(bundle: body, sessionSecret: sessionSecret, subjectId: subjectId)
            try existingUrk.wrapAndStore()
            self.urk = existingUrk
            auth.markSyncReady()
            return
        }

        // 2. No existing bundle — generate new URK
        let newUrk = URK.generate()
        let bundle = try URK.encryptBundle(urk: newUrk.bytes, sessionSecret: sessionSecret, subjectId: subjectId)

        // 3. Upload bundle to server
        var putRequest = URLRequest(url: bundleUrl)
        putRequest.httpMethod = "PUT"
        putRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        putRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        putRequest.httpBody = try JSONSerialization.data(withJSONObject: bundle)

        let (_, putResponse) = try await URLSession.shared.data(for: putRequest)
        guard let putHttp = putResponse as? HTTPURLResponse,
              putHttp.statusCode == 200 || putHttp.statusCode == 201 else {
            throw NSError(domain: "SyncModule", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to upload URK bundle"])
        }

        // 4. Wrap and store locally
        try newUrk.wrapAndStore()
        self.urk = newUrk
        auth.markSyncReady()
    }

    func dispose() {
        urk = nil
        enabled = false
    }
}
