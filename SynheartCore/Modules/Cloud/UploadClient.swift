import Foundation

/// HTTP client for uploading HSI snapshots to Synheart Platform.
///
/// Auth model:
///   Authorization: Bearer {consentToken}   — standard JWT from ConsentModule
///   + device signature headers              — defense-in-depth (optional)
///
/// HMAC signing removed — device attestation at token issuance replaces it.
public class UploadClient {
    private let baseUrl: String
    private let session: URLSession

    public init(baseUrl: String, session: URLSession = .shared) {
        self.baseUrl = baseUrl
        self.session = session
    }

    public func upload(
        payload: UploadRequest,
        consentToken: ConsentToken?,
        deviceAuth: AuthProvider? = nil
    ) async throws -> UploadResponse {
        let method = "POST"
        let path = ApiEndpoints.ingestPath

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(payload)

        return try await uploadWithRetry(
            method: method,
            path: path,
            bodyData: bodyData,
            maxAttempts: 3,
            consentToken: consentToken,
            deviceAuth: deviceAuth
        )
    }

    private func uploadWithRetry(
        method: String,
        path: String,
        bodyData: Data,
        maxAttempts: Int,
        consentToken: ConsentToken?,
        deviceAuth: AuthProvider?
    ) async throws -> UploadResponse {
        var attempts = 0
        let baseDelay: UInt64 = 1_000_000_000

        while attempts < maxAttempts {
            attempts += 1

            do {
                guard let url = URL(string: "\(baseUrl)\(path)") else {
                    throw CloudConnectorError.networkError("Invalid URL")
                }

                var request = URLRequest(url: url)
                request.httpMethod = method
                request.httpBody = bodyData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                // Bearer token from consent module
                if let token = consentToken, token.isValid {
                    request.setValue("Bearer \(token.token)", forHTTPHeaderField: "Authorization")
                }

                // Device signature headers (defense-in-depth)
                if let deviceAuth = deviceAuth {
                    let deviceHeaders = try deviceAuth.signRequest(
                        method: method,
                        path: path,
                        bodyBytes: bodyData
                    )
                    for (key, value) in deviceHeaders {
                        request.setValue(value, forHTTPHeaderField: key)
                    }
                }

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CloudConnectorError.networkError("Invalid response")
                }

                if httpResponse.statusCode == 200 || httpResponse.statusCode == 202 {
                    let decoder = JSONDecoder()
                    return try decoder.decode(UploadResponse.self, from: data)
                }

                let error: UploadErrorResponse
                do {
                    error = try JSONDecoder().decode(UploadErrorResponse.self, from: data)
                } catch {
                    let bodyStr = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                    throw CloudConnectorError.networkError(
                        "Upload failed: \(httpResponse.statusCode) \(bodyStr)"
                    )
                }

                // Handle 401 with device auth retry
                if httpResponse.statusCode == 401, let deviceAuth = deviceAuth {
                    let responseHeaders = httpResponse.allHeaderFields as? [String: String] ?? [:]
                    let handled = deviceAuth.onAuthError(
                        statusCode: 401,
                        responseHeaders: responseHeaders
                    )
                    if handled && attempts < maxAttempts {
                        continue
                    }
                }

                switch (httpResponse.statusCode, error.code) {
                case (401, _):
                    throw CloudConnectorError.invalidSignature
                case (403, _):
                    throw CloudConnectorError.invalidTenant
                case (400, "schema_validation_failed"), (400, "hsi_schema_validation_failed"):
                    throw CloudConnectorError.schemaValidation
                case (429, _):
                    throw CloudConnectorError.rateLimitExceeded(retryAfter: error.retryAfter ?? 60)
                default:
                    if attempts >= maxAttempts {
                        throw CloudConnectorError.generic("Upload failed: \(error.message)")
                    }
                }

            } catch let error as CloudConnectorError {
                throw error
            } catch {
                if attempts >= maxAttempts {
                    throw CloudConnectorError.networkError(
                        "Upload failed after \(maxAttempts) attempts: \(error.localizedDescription)"
                    )
                }
            }

            if attempts < maxAttempts {
                let delay = baseDelay * UInt64(1 << (attempts - 1))
                try await Task.sleep(nanoseconds: delay)
            }
        }

        throw CloudConnectorError.networkError("Upload failed after \(maxAttempts) attempts")
    }
}
