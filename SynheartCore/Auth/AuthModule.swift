import Foundation

/// Authentication status (RFC-CORE-0008).
public struct AuthStatus {
    public let authenticated: Bool
    public let subjectId: String?
    public let provider: String?
    public let syncReady: Bool

    public static let unauthenticated = AuthStatus(
        authenticated: false, subjectId: nil, provider: nil, syncReady: false
    )
}

/// Result of an authentication attempt.
public struct AuthResult {
    public let subjectId: String
    public let accessToken: String?
    public let refreshToken: String?
    public let sessionSecret: String?
    public let syncReady: Bool
}

/// Auth errors.
public enum AuthError: Error {
    case authFailed(statusCode: Int)
    case authExpired
    case noRefreshToken
}

/// Manages authentication and token lifecycle (RFC-CORE-0008).
public class AuthModule {
    private(set) var status: AuthStatus = .unauthenticated
    private(set) var accessToken: String?
    private(set) var sessionSecret: String?

    private static let defaultExpirySeconds: TimeInterval = 3600

    private let tokenStorage: TokenStorage
    private let baseUrl: String
    private let appId: String
    private var refreshTask: Task<Void, Never>?

    public init(appId: String, baseUrl: String = "https://api.synheart.com", tokenStorage: TokenStorage? = nil) {
        self.appId = appId
        self.baseUrl = baseUrl
        self.tokenStorage = tokenStorage ?? TokenStorage()
    }

    public var subjectId: String? { status.subjectId }
    public var isAuthenticated: Bool { status.authenticated }

    /// Anonymous auth — generates a local subject_id, no sync capability.
    public func authenticateAnonymous() throws -> AuthResult {
        let id = "anon_\(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(16))"
        try tokenStorage.saveSubjectId(id)

        status = AuthStatus(authenticated: false, subjectId: id, provider: "anonymous", syncReady: false)
        return AuthResult(subjectId: id, accessToken: nil, refreshToken: nil, sessionSecret: nil, syncReady: false)
    }

    /// Token-based auth — exchanges a provider token for Synheart credentials.
    public func authenticate(provider: String, token: String) async throws -> AuthResult {
        let url = URL(string: "\(baseUrl)/v1/auth/exchange")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": provider,
            "token": token,
            "app_id": appId,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AuthError.authFailed(statusCode: code)
        }

        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.authFailed(statusCode: -1)
        }

        let sid = body["subject_id"] as! String
        let at = body["access_token"] as! String
        let rt = body["refresh_token"] as! String
        let ss = body["session_secret"] as? String

        accessToken = at
        sessionSecret = ss

        try tokenStorage.saveRefreshToken(rt)
        try tokenStorage.saveSubjectId(sid)
        if let ss = ss {
            try tokenStorage.saveSessionSecret(ss)
        }

        status = AuthStatus(authenticated: true, subjectId: sid, provider: provider, syncReady: false)

        let expiresIn = (body["expires_in"] as? TimeInterval) ?? Self.defaultExpirySeconds
        scheduleRefresh(expiresIn: expiresIn)

        return AuthResult(subjectId: sid, accessToken: at, refreshToken: rt, sessionSecret: ss, syncReady: false)
    }

    /// Refresh the access token.
    public func refreshToken() async throws {
        guard let rt = try tokenStorage.loadRefreshToken() else {
            throw AuthError.noRefreshToken
        }

        let url = URL(string: "\(baseUrl)/v1/auth/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": rt])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            status = AuthStatus(authenticated: false, subjectId: status.subjectId, provider: status.provider, syncReady: false)
            throw AuthError.authExpired
        }

        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.authExpired
        }

        accessToken = body["access_token"] as? String
        if let newRt = body["refresh_token"] as? String {
            try tokenStorage.saveRefreshToken(newRt)
        }

        let expiresIn = (body["expires_in"] as? TimeInterval) ?? Self.defaultExpirySeconds
        scheduleRefresh(expiresIn: expiresIn)
    }

    /// Schedule a proactive token refresh at 80% of the token lifetime.
    private func scheduleRefresh(expiresIn: TimeInterval) {
        refreshTask?.cancel()
        let delayNanoseconds = UInt64(expiresIn * 0.8 * 1_000_000_000)
        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
                try await self?.refreshToken()
            } catch {
                // Silent failure — token refresh will be retried on next API call.
            }
        }
    }

    /// Mark sync as ready (called after URK provisioning).
    func markSyncReady() {
        status = AuthStatus(
            authenticated: status.authenticated,
            subjectId: status.subjectId,
            provider: status.provider,
            syncReady: true
        )
    }

    /// Log out — clear tokens and reset state.
    public func logout() {
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        sessionSecret = nil
        tokenStorage.clearAll()
        status = .unauthenticated
    }

    /// Restore auth state from stored tokens.
    public func restoreSession() async -> Bool {
        guard let sid = try? tokenStorage.loadSubjectId() else { return false }

        let rt = try? tokenStorage.loadRefreshToken()
        sessionSecret = try? tokenStorage.loadSessionSecret()

        if rt != nil {
            status = AuthStatus(authenticated: true, subjectId: sid, provider: "restored", syncReady: false)
            do {
                try await refreshToken()
                return true
            } catch {
                return false
            }
        }

        status = AuthStatus(authenticated: false, subjectId: sid, provider: "anonymous", syncReady: false)
        return true
    }
}
