import Foundation
import Combine
import Security

/// Consent Module
///
/// Single source of truth for user consent on the device.
/// Gates collection and export of biosignals, behavior, motion/context,
/// cloud upload, and Syni personalization.
///
/// Supports both local consent (on-device only) and cloud consent service
/// integration (with JWT tokens for cloud uploads).
public class ConsentModule: BaseSynheartModule, ConsentProvider {
    private let storage: ConsentStorage
    private let consentSubject = CurrentValueSubject<ConsentSnapshot?, Never>(nil)
    private var currentConsent: ConsentSnapshot?

    /// Callbacks for when consent changes
    private var listeners: [(ConsentSnapshot) -> Void] = []

    // Cloud consent service integration (optional)
    private var consentConfig: ConsentConfig?
    private var apiClient: ConsentAPIClient?
    private var tokenStorage: ConsentTokenStorage?
    private var currentToken: ConsentToken?
    private var tokenRefreshTask: Task<Void, Never>?

    // Device ID storage
    private static let deviceIdKey = "synheart_device_id"
    private let keychainService = "ai.synheart.hsi"

    public init(storage: ConsentStorage? = nil, consentConfig: ConsentConfig? = nil) {
        self.storage = storage ?? ConsentStorage()
        self.consentConfig = consentConfig
        super.init(moduleId: "consent")

        if consentConfig?.isConfigured == true {
            tokenStorage = ConsentTokenStorage()
            apiClient = ConsentAPIClient(
                baseUrl: consentConfig!.consentServiceUrl,
                appId: consentConfig!.appId!,
                appApiKey: consentConfig!.appApiKey!
            )
        }
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
            SynheartLogger.log(
                "[ConsentModule] Loaded consent from storage: biosignals=\(stored.biosignals), behavior=\(stored.behavior), phoneContext=\(stored.phoneContext), cloudUpload=\(stored.cloudUpload)"
            )
        } else {
            // No stored consent, use defaults (all denied for safety)
            let defaultConsent = ConsentSnapshot.none()
            currentConsent = defaultConsent
            consentSubject.send(defaultConsent)
            SynheartLogger.log(
                "[ConsentModule] No stored consent, using defaults (all denied - explicit consent required)"
            )
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
            phoneContext: type == .phoneContext ? granted : current.phoneContext,
            cloudUpload: type == .cloudUpload ? granted : current.cloudUpload,
            syni: type == .syni ? granted : current.syni,
            focusEstimation: type == .focusEstimation ? granted : current.focusEstimation,
            emotionEstimation: type == .emotionEstimation ? granted : current.emotionEstimation,
            timestamp: Date()
        )

        try await updateConsent(updated)
    }

    // MARK: - Cloud Consent Service Integration

    /// Get available consent profiles from cloud service
    ///
    /// Returns cached profiles if available and not expired, otherwise fetches from API.
    public func getAvailableProfiles() async throws -> [ConsentProfile] {
        SynheartLogger.log("[ConsentModule] getAvailableProfiles() called")

        guard let apiClient = apiClient else {
            SynheartLogger.log(
                "[ConsentModule] ERROR: API client not initialized. ConsentConfig missing or not configured."
            )
            throw NSError(domain: "ConsentModule", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Consent service not configured. Provide ConsentConfig with appId and appApiKey."
            ])
        }

        SynheartLogger.log(
            "[ConsentModule] API client configured: baseUrl=\(consentConfig?.consentServiceUrl ?? "nil"), appId=\(consentConfig?.appId ?? "nil")"
        )

        // Try to load from cache first
        SynheartLogger.log("[ConsentModule] Checking for cached profiles...")
        if let cached = tokenStorage?.loadCachedProfiles(), !cached.isEmpty {
            SynheartLogger.log("[ConsentModule] Using cached profiles (count: \(cached.count))")
            return cached
        }

        SynheartLogger.log("[ConsentModule] No valid cached profiles, fetching from API...")

        // Fetch from API
        let profiles = try await apiClient.getAvailableProfiles()

        SynheartLogger.log("[ConsentModule] Successfully fetched \(profiles.count) profiles from API")

        // Cache the profiles
        SynheartLogger.log("[ConsentModule] Caching profiles...")
        tokenStorage?.cacheProfiles(profiles)
        SynheartLogger.log("[ConsentModule] Profiles cached successfully")

        return profiles
    }

    /// Request consent by issuing a token for the selected profile
    ///
    /// This should be called after the user has selected a consent profile.
    public func requestConsent(_ profile: ConsentProfile) async throws -> ConsentToken {
        guard let apiClient = apiClient, let consentConfig = consentConfig else {
            throw NSError(domain: "ConsentModule", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Consent service not configured. Provide ConsentConfig with appId and appApiKey."
            ])
        }

        // Get or generate persistent device ID
        let deviceId: String
        if let configDeviceId = consentConfig.deviceId {
            deviceId = configDeviceId
        } else {
            deviceId = try await getOrGenerateDeviceId()
        }

        let token = try await apiClient.issueToken(
            deviceId: deviceId,
            consentProfileId: profile.id,
            platform: consentConfig.platform,
            userId: consentConfig.userId,
            region: consentConfig.region
        )

        // Store token
        try tokenStorage?.saveToken(token)
        currentToken = token

        // Update local consent snapshot based on profile
        try await updateConsentFromProfile(profile)

        // Start token refresh timer
        startTokenRefreshTimer()

        SynheartLogger.log("[ConsentModule] Consent token issued for profile: \(profile.id)")

        return token
    }

    /// Request consent token directly by profile id (without fetching profiles first).
    /// Useful when integrator already knows the consent_profile_id.
    public func requestConsentByProfileId(
        _ profileId: String,
        ipAddress: String? = nil,
        userAgent: String? = nil
    ) async throws -> ConsentToken {
        guard let apiClient = apiClient, let consentConfig = consentConfig else {
            throw NSError(domain: "ConsentModule", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Consent service not configured. Provide ConsentConfig with appId and appApiKey."
            ])
        }

        let deviceId: String
        if let configDeviceId = consentConfig.deviceId {
            deviceId = configDeviceId
        } else {
            deviceId = try await getOrGenerateDeviceId()
        }

        let token = try await apiClient.issueToken(
            deviceId: deviceId,
            consentProfileId: profileId,
            platform: consentConfig.platform,
            userId: consentConfig.userId,
            region: consentConfig.region,
            ipAddress: ipAddress,
            userAgent: userAgent
        )

        try tokenStorage?.saveToken(token)
        currentToken = token
        startTokenRefreshTimer()
        SynheartLogger.log("[ConsentModule] Consent token issued directly for profile: \(profileId)")
        return token
    }

    /// Check current consent status
    public func checkConsentStatus() -> ConsentStatus {
        if currentToken == nil {
            // Try to load from storage
            loadTokenFromStorage()
            if currentToken == nil {
                return .pending
            }
        }

        if currentToken!.isExpired {
            return .expired
        }

        return .granted
    }

    /// Get current valid consent token
    public func getCurrentToken() -> ConsentToken? {
        if currentToken == nil {
            loadTokenFromStorage()
        }

        if let token = currentToken, token.isValid {
            return token
        }

        return nil
    }

    /// Revoke consent (clears token and notifies cloud)
    public func revokeConsent() async throws {
        if let currentToken = currentToken, let apiClient = apiClient, let consentConfig = consentConfig {
            let deviceId: String
            if let configDeviceId = consentConfig.deviceId {
                deviceId = configDeviceId
            } else {
                deviceId = try await getOrGenerateDeviceId()
            }
            await apiClient.revokeConsent(
                deviceId: deviceId,
                profileId: currentToken.profileId
            )
        }

        // Clear token locally
        tokenStorage?.deleteToken()
        currentToken = nil
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil

        // Update consent snapshot to deny cloud upload
        if let current = currentConsent {
            try await updateConsent(
                current.copyWith(cloudUpload: false, timestamp: Date())
            )
        } else {
            try await updateConsent(ConsentSnapshot.none())
        }

        SynheartLogger.log("[ConsentModule] Consent revoked")
    }

    /// Mark consent as explicitly denied by user
    ///
    /// This should be called when user declines consent in the UI,
    /// to distinguish from "never asked" (pending) state.
    public func denyConsent() async throws {
        // Clear any existing token
        tokenStorage?.deleteToken()
        currentToken = nil
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil

        // Update consent snapshot to mark as denied
        try await updateConsent(ConsentSnapshot.none())

        SynheartLogger.log("[ConsentModule] Consent explicitly denied by user")
    }

    /// Refresh consent token if it's about to expire
    public func refreshTokenIfNeeded() async -> ConsentToken? {
        guard let currentToken = currentToken, apiClient != nil, consentConfig != nil else {
            return nil
        }

        // Only refresh if token expires soon
        guard currentToken.expiresSoon() else {
            return currentToken
        }

        do {
            let profileId = currentToken.profileId
            let profiles = try await getAvailableProfiles()
            guard let profile = profiles.first(where: { $0.id == profileId }) else {
                SynheartLogger.log("[ConsentModule] Profile \(profileId) not found for refresh")
                return nil
            }
            let newToken = try await requestConsent(profile)
            return newToken
        } catch {
            SynheartLogger.log("[ConsentModule] Error refreshing token: \(error)")
            return nil
        }
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
        let fields: [(String, Bool, Bool)] = [
            ("biosignals", old.biosignals, new.biosignals),
            ("behavior", old.behavior, new.behavior),
            ("phoneContext", old.phoneContext, new.phoneContext),
            ("focusEstimation", old.focusEstimation, new.focusEstimation),
            ("emotionEstimation", old.emotionEstimation, new.emotionEstimation),
            ("cloudUpload", old.cloudUpload, new.cloudUpload),
            ("syni", old.syni, new.syni),
        ]
        for (name, oldVal, newVal) in fields where oldVal != newVal {
            SynheartLogger.log("Consent changed: \(name) \(newVal ? "granted" : "revoked")")
        }
    }

    /// Update local consent snapshot from profile
    private func updateConsentFromProfile(_ profile: ConsentProfile) async throws {
        let snapshot = ConsentSnapshot(
            biosignals: profile.channels.biosignals.vitals || profile.channels.biosignals.sleep,
            behavior: profile.channels.behavior.enabled,
            phoneContext: profile.channels.phoneContext.motion || profile.channels.phoneContext.screenState,
            cloudUpload: profile.cloudEnabled,
            syni: false,
            focusEstimation: false,
            emotionEstimation: false,
            timestamp: Date()
        )

        try await updateConsent(snapshot)
    }

    /// Load token from storage
    private func loadTokenFromStorage() {
        guard let tokenStorage = tokenStorage else { return }
        if let token = tokenStorage.loadToken() {
            if token.isValid {
                currentToken = token
                startTokenRefreshTimer()
            } else {
                // Clean up expired token
                tokenStorage.deleteToken()
                currentToken = nil
            }
        }
    }

    /// Start token refresh timer
    ///
    /// Optimized to check at appropriate intervals based on token expiry time.
    /// Checks 5 minutes before expiry, then every minute if close to expiry.
    private func startTokenRefreshTimer() {
        tokenRefreshTask?.cancel()

        guard let currentToken = currentToken else { return }

        let timeUntilExpiry = currentToken.expiresAt.timeIntervalSinceNow
        let refreshThreshold: TimeInterval = 300 // 5 minutes

        // Calculate when to check next
        let checkInterval: TimeInterval
        if timeUntilExpiry <= refreshThreshold {
            // Close to expiry - check every minute
            checkInterval = 60
        } else {
            // Far from expiry - check 5 minutes before expiry
            let timeUntilRefresh = timeUntilExpiry - refreshThreshold
            // Cap at 1 hour max interval
            checkInterval = min(timeUntilRefresh, 3600)
        }

        SynheartLogger.log("[ConsentModule] Token refresh timer: checking in \(Int(checkInterval / 60)) minutes")

        tokenRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            } catch {
                return // Task was cancelled
            }

            guard let self = self else { return }

            let refreshed = await self.refreshTokenIfNeeded()
            if let refreshed = refreshed, refreshed.token != self.currentToken?.token {
                self.currentToken = refreshed
                self.startTokenRefreshTimer()
            } else if self.currentToken?.isExpired == true {
                SynheartLogger.log("[ConsentModule] Token expired and refresh failed")
                self.tokenRefreshTask?.cancel()
                self.tokenRefreshTask = nil
            } else {
                self.startTokenRefreshTimer()
            }
        }
    }

    /// Get or generate persistent device ID (UUID v4 format)
    ///
    /// Device ID is stored in Keychain and persists across app restarts.
    private func getOrGenerateDeviceId() async throws -> String {
        // Try to load existing device ID from Keychain
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

        // Generate new UUID
        let deviceId = UUID().uuidString

        // Store in Keychain
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

    // MARK: - Module Lifecycle

    override public func onInitialize() async throws {
        try await loadConsent()

        // Load token from storage if consent service is configured
        if tokenStorage != nil {
            loadTokenFromStorage()
        }
    }

    override public func onStart() async throws {
        // Start token refresh timer if we have a token
        if currentToken != nil {
            startTokenRefreshTimer()
        }
    }

    override public func onStop() async throws {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
    }

    override public func onDispose() async throws {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
        consentSubject.send(nil)
        listeners.removeAll()
        currentConsent = nil
        currentToken = nil
    }
}
