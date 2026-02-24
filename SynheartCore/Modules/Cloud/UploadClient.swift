import Foundation

/// HTTP client for uploading HSI 1.1 snapshots to Synheart Platform
///
/// Features:
/// - HMAC-SHA256 authentication
/// - Exponential backoff retry (1s, 2s, 4s)
/// - Max 3 retry attempts
/// - Specific error handling per status code
public class UploadClient {
    private let baseUrl: String
    private let session: URLSession

    public init(baseUrl: String, session: URLSession = .shared) {
        self.baseUrl = baseUrl
        self.session = session
    }

    /// Upload HSI 1.1 snapshots to the platform
    ///
    /// - Parameters:
    ///   - payload: Upload request containing subject and snapshots
    ///   - signer: HMAC signer instance
    ///   - tenantId: Tenant identifier
    /// - Returns: UploadResponse on success
    /// - Throws: CloudConnectorError on failure
    public func upload(
        payload: UploadRequest,
        signer: HMACSigner,
        tenantId: String
    ) async throws -> UploadResponse {
        let method = "POST"
        let path = "/v1/ingest/hsi"

        // Serialize payload
        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(payload)
        let bodyJson = String(data: bodyData, encoding: .utf8)!

        // Upload with retry logic
        return try await uploadWithRetry(
            method: method,
            path: path,
            bodyJson: bodyJson,
            bodyData: bodyData,
            signer: signer,
            tenantId: tenantId,
            maxAttempts: 3
        )
    }

    /// Upload with exponential backoff retry
    private func uploadWithRetry(
        method: String,
        path: String,
        bodyJson: String,
        bodyData: Data,
        signer: HMACSigner,
        tenantId: String,
        maxAttempts: Int
    ) async throws -> UploadResponse {
        var attempts = 0
        let baseDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds

        while attempts < maxAttempts {
            attempts += 1

            do {
                // Generate fresh nonce and timestamp for each attempt
                let nonce = signer.generateNonce()
                let timestamp = Int(Date().timeIntervalSince1970)
                let signature = signer.computeSignature(
                    method: method,
                    path: path,
                    tenantId: tenantId,
                    timestamp: timestamp,
                    nonce: nonce,
                    bodyJson: bodyJson
                )

                // Build request
                guard let url = URL(string: "\(baseUrl)\(path)") else {
                    throw CloudConnectorError.networkError("Invalid URL")
                }

                var request = URLRequest(url: url)
                request.httpMethod = method
                request.httpBody = bodyData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(tenantId, forHTTPHeaderField: "X-Synheart-Tenant")
                request.setValue(signature, forHTTPHeaderField: "X-Synheart-Signature")
                request.setValue(nonce, forHTTPHeaderField: "X-Synheart-Nonce")
                request.setValue("\(timestamp)", forHTTPHeaderField: "X-Synheart-Timestamp")
                request.setValue("1.0.0", forHTTPHeaderField: "X-Synheart-SDK-Version")

                // Execute request
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw CloudConnectorError.networkError("Invalid response")
                }

                if httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    return try decoder.decode(UploadResponse.self, from: data)
                }

                // Parse error response
                let decoder = JSONDecoder()
                let error = try decoder.decode(UploadErrorResponse.self, from: data)

                // Handle specific errors (non-retryable)
                switch (httpResponse.statusCode, error.code) {
                case (401, "invalid_signature"):
                    throw CloudConnectorError.invalidSignature
                case (403, "invalid_tenant"):
                    throw CloudConnectorError.invalidTenant
                case (400, "schema_validation_failed"):
                    throw CloudConnectorError.schemaValidation
                case (429, _):
                    throw CloudConnectorError.rateLimitExceeded(
                        retryAfter: error.retryAfter ?? 60
                    )
                default:
                    // Generic error - retry if attempts remaining
                    if attempts >= maxAttempts {
                        throw CloudConnectorError.generic("Upload failed: \(error.message)")
                    }
                }

            } catch let error as CloudConnectorError {
                // Don't retry on known exceptions
                throw error
            } catch {
                // Network or parsing error - retry if attempts remaining
                if attempts >= maxAttempts {
                    throw CloudConnectorError.networkError(
                        "Upload failed after \(maxAttempts) attempts: \(error.localizedDescription)"
                    )
                }
            }

            // Exponential backoff: 1s, 2s, 4s
            if attempts < maxAttempts {
                let delay = baseDelay * UInt64(1 << (attempts - 1))
                try await Task.sleep(nanoseconds: delay)
            }
        }

        throw CloudConnectorError.networkError("Upload failed after \(maxAttempts) attempts")
    }
}
