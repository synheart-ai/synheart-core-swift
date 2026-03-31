import Foundation
import CryptoKit

/// Stateless HTTP client for platform session and metadata ingestion.
///
/// Can be used standalone (without full SDK init) — e.g. from a
/// background task — by providing hmacSecret, apiKey,
/// and consent token directly.
///
/// Uses a simpler HMAC signing scheme than the cloud connector:
/// `HMAC-SHA256(timestamp_bytes + body_bytes, secret)`
public class LabIngestClient {
    private let baseUrl: String
    private let timeout: TimeInterval
    private let maxRetries: Int
    private let session: URLSession

    public init(
        baseUrl: String = ApiEndpoints.defaultLabIngestBaseUrl,
        timeout: TimeInterval = 30,
        maxRetries: Int = 3,
        session: URLSession? = nil
    ) {
        self.baseUrl = baseUrl
        self.timeout = timeout
        self.maxRetries = maxRetries

        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = timeout
            config.timeoutIntervalForResource = timeout
            self.session = URLSession(configuration: config)
        }
    }

    /// POST a session payload to `/platform/v1/session/ingest`.
    public func ingestSession(
        payload: [String: Any],
        hmacSecret: String,
        apiKey: String,
        consentToken: String? = nil
    ) async -> LabIngestResponse {
        return await post(
            path: ApiEndpoints.labSessionIngestPath,
            payload: payload,
            hmacSecret: hmacSecret,
            apiKey: apiKey,
            consentToken: consentToken
        )
    }

    /// POST a metadata payload to `/platform/v1/metadata/ingest`.
    public func ingestMetadata(
        payload: [String: Any],
        hmacSecret: String,
        apiKey: String,
        consentToken: String? = nil
    ) async -> LabIngestResponse {
        return await post(
            path: ApiEndpoints.labMetadataIngestPath,
            payload: payload,
            hmacSecret: hmacSecret,
            apiKey: apiKey,
            consentToken: consentToken
        )
    }

    private func post(
        path: String,
        payload: [String: Any],
        hmacSecret: String,
        apiKey: String,
        consentToken: String?
    ) async -> LabIngestResponse {
        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload),
              let bodyJson = String(data: bodyData, encoding: .utf8) else {
            return LabIngestResponse(
                success: false,
                statusCode: 0,
                errorMessage: "Failed to serialize payload to JSON"
            )
        }

        var attempts = 0

        while attempts < maxRetries {
            attempts += 1
            do {
                guard let url = URL(string: "\(baseUrl)\(path)") else {
                    return LabIngestResponse(
                        success: false,
                        statusCode: 0,
                        errorMessage: "Invalid URL: \(baseUrl)\(path)"
                    )
                }

                let nonce = generateNonce()
                let timestamp = "\(Int(Date().timeIntervalSince1970))"
                let signature = computeSignature(
                    timestamp: timestamp,
                    bodyJson: bodyJson,
                    hmacSecret: hmacSecret
                )

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = bodyData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                request.setValue(signature, forHTTPHeaderField: "X-Synheart-Signature")
                request.setValue(timestamp, forHTTPHeaderField: "X-Synheart-Timestamp")
                request.setValue(nonce, forHTTPHeaderField: "X-Synheart-Nonce")

                if let consentToken = consentToken, !consentToken.isEmpty {
                    request.setValue(consentToken, forHTTPHeaderField: "X-Consent-Token")
                }

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    if attempts >= maxRetries {
                        return LabIngestResponse(
                            success: false,
                            statusCode: 0,
                            errorMessage: "Invalid response"
                        )
                    }
                    try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * (1 << attempts)))
                    continue
                }

                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    let parsedBody = tryParseJson(data)
                    return LabIngestResponse(
                        success: true,
                        statusCode: httpResponse.statusCode,
                        body: parsedBody
                    )
                }

                // 4xx — don't retry client errors
                if httpResponse.statusCode >= 400 && httpResponse.statusCode < 500 {
                    return LabIngestResponse(
                        success: false,
                        statusCode: httpResponse.statusCode,
                        body: tryParseJson(data),
                        errorMessage: "Client error: HTTP \(httpResponse.statusCode)"
                    )
                }

                // 5xx — retry with exponential backoff
                if attempts < maxRetries {
                    let delay = UInt64(1_000_000_000 * (1 << attempts))
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }

                return LabIngestResponse(
                    success: false,
                    statusCode: httpResponse.statusCode,
                    body: tryParseJson(data),
                    errorMessage: "Server error: HTTP \(httpResponse.statusCode)"
                )
            } catch {
                if attempts >= maxRetries {
                    return LabIngestResponse(
                        success: false,
                        statusCode: 0,
                        errorMessage: "Request failed after \(maxRetries) attempts: \(error.localizedDescription)"
                    )
                }
                do {
                    let delay = UInt64(1_000_000_000 * (1 << attempts))
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return LabIngestResponse(
                        success: false,
                        statusCode: 0,
                        errorMessage: "Request cancelled"
                    )
                }
            }
        }

        return LabIngestResponse(
            success: false,
            statusCode: 0,
            errorMessage: "Request failed: max retries exceeded"
        )
    }

    /// Compute HMAC-SHA256 signature for lab ingestion.
    ///
    /// Formula: `HMAC-SHA256(timestamp_bytes + body_bytes, secret)`
    private func computeSignature(
        timestamp: String,
        bodyJson: String,
        hmacSecret: String
    ) -> String {
        let timestampBytes = Array(timestamp.utf8)
        let bodyBytes = Array(bodyJson.utf8)
        let message = Data(timestampBytes + bodyBytes)

        let key = SymmetricKey(data: Data(hmacSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: message, using: key)

        return signature.map { String(format: "%02x", $0) }.joined()
    }

    /// Generate UUID v4 nonce.
    private func generateNonce() -> String {
        UUID().uuidString.lowercased()
    }

    private func tryParseJson(_ data: Data) -> [String: Any]? {
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
