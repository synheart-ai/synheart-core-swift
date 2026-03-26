import Foundation

/// REST client for consent service API
public class ConsentAPIClient {
    private let baseUrl: String
    private let appId: String
    private let appApiKey: String
    private let session: URLSession

    public init(
        baseUrl: String,
        appId: String,
        appApiKey: String,
        session: URLSession = .shared
    ) {
        self.baseUrl = baseUrl
        self.appId = appId
        self.appApiKey = appApiKey
        self.session = session
    }

    /// Fetch available consent profiles for this app
    ///
    /// GET /consent/v1/apps/{app_id}/consent-profiles?active_only=true
    public func getAvailableProfiles(activeOnly: Bool = true) async throws -> [ConsentProfile] {
        let path = ApiEndpoints.consentProfilesPath(appId: appId)
        guard var components = URLComponents(string: "\(baseUrl)\(path)") else {
            throw ConsentAPIError.networkError("Invalid URL")
        }
        components.queryItems = [URLQueryItem(name: "active_only", value: "\(activeOnly)")]

        guard let url = components.url else {
            throw ConsentAPIError.networkError("Invalid URL components")
        }

        SynheartLogger.log("[ConsentAPI] Fetching profiles from: \(url)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(appApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConsentAPIError.networkError("Invalid response")
        }

        SynheartLogger.log("[ConsentAPI] Response received: statusCode=\(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConsentAPIError.invalidResponse("Response is not a JSON object")
            }

            guard let profilesJson = body["profiles"] as? [[String: Any]] else {
                SynheartLogger.log("[ConsentAPI] WARNING: Response body does not contain \"profiles\" key")
                throw ConsentAPIError.invalidResponse("Missing \"profiles\" key in response")
            }

            SynheartLogger.log("[ConsentAPI] Found \(profilesJson.count) profiles in response")

            let decoder = JSONDecoder()
            let profiles = try profilesJson.map { dict -> ConsentProfile in
                let jsonData = try JSONSerialization.data(withJSONObject: dict)
                return try decoder.decode(ConsentProfile.self, from: jsonData)
            }

            SynheartLogger.log("[ConsentAPI] Successfully parsed \(profiles.count) profiles")
            return profiles

        case 401:
            SynheartLogger.log("[ConsentAPI] ERROR: 401 Unauthorized - Invalid app API key")
            throw ConsentAPIError.unauthorized

        case 404:
            SynheartLogger.log("[ConsentAPI] ERROR: 404 Not Found - App not found")
            throw ConsentAPIError.appNotFound

        default:
            SynheartLogger.log("[ConsentAPI] ERROR: Unexpected status code \(httpResponse.statusCode)")
            throw ConsentAPIError.requestFailed(httpResponse.statusCode)
        }
    }

    /// Issue SDK token after user consent
    ///
    /// POST /consent/v1/sdk/consent-token
    public func issueToken(
        deviceId: String,
        consentProfileId: String,
        platform: String,
        userId: String? = nil,
        region: String? = nil,
        ipAddress: String? = nil,
        userAgent: String? = nil
    ) async throws -> ConsentToken {
        let path = ApiEndpoints.consentTokenPath
        guard let url = URL(string: "\(baseUrl)\(path)") else {
            throw ConsentAPIError.networkError("Invalid URL")
        }

        var body: [String: Any] = [
            "app_id": appId,
            "device_id": deviceId,
            "platform": platform,
            "consent_profile_id": consentProfileId
        ]
        if let userId = userId { body["user_id"] = userId }
        if let region = region { body["region"] = region }
        if let ipAddress = ipAddress { body["ip_address"] = ipAddress }
        if let userAgent = userAgent { body["user_agent"] = userAgent }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(appApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConsentAPIError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200, 201:
            SynheartLogger.log("[ConsentAPI] Token response received: statusCode=\(httpResponse.statusCode)")

            guard let bodyJson = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConsentAPIError.invalidResponse("Token response is not a JSON object")
            }

            SynheartLogger.log("[ConsentAPI] Parsed response keys: \(bodyJson.keys.joined(separator: ", "))")

            let token = try ConsentToken.fromAPIResponse(bodyJson)
            SynheartLogger.log("[ConsentAPI] Successfully parsed consent token: profileId=\(token.profileId)")
            return token

        case 400:
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorBody["message"] as? String {
                throw ConsentAPIError.badRequest(message)
            }
            throw ConsentAPIError.badRequest("Invalid request")

        case 401:
            throw ConsentAPIError.unauthorized

        default:
            throw ConsentAPIError.requestFailed(httpResponse.statusCode)
        }
    }

    /// Revoke consent (notify cloud service)
    ///
    /// POST /consent/v1/sdk/consent-revoke
    public func revokeConsent(deviceId: String, profileId: String) async {
        let path = ApiEndpoints.consentRevokePath
        guard let url = URL(string: "\(baseUrl)\(path)") else { return }

        let body: [String: Any] = [
            "app_id": appId,
            "device_id": deviceId,
            "profile_id": profileId
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(appApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 && httpResponse.statusCode != 204 {
                SynheartLogger.log("[ConsentAPI] Failed to revoke consent: \(httpResponse.statusCode)")
            }
        } catch {
            SynheartLogger.log("[ConsentAPI] Error revoking consent: \(error)")
            // Don't throw - revocation is best-effort
        }
    }
}

/// Errors thrown by ConsentAPIClient
public enum ConsentAPIError: Error, LocalizedError {
    case unauthorized
    case appNotFound
    case badRequest(String)
    case invalidResponse(String)
    case requestFailed(Int)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "ConsentAPIError: Invalid app API key"
        case .appNotFound:
            return "ConsentAPIError: App not found"
        case .badRequest(let message):
            return "ConsentAPIError: \(message)"
        case .invalidResponse(let message):
            return "ConsentAPIError: Invalid response - \(message)"
        case .requestFailed(let statusCode):
            return "ConsentAPIError: Request failed with status \(statusCode)"
        case .networkError(let message):
            return "ConsentAPIError: Network error - \(message)"
        }
    }
}
