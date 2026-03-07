import Foundation
import CryptoKit

/// Core sync engine — handles push/pull with E2EE (RFC-CORE-0005).
class SyncEngine {
    private let storage: StorageManager
    private let baseUrl: String
    var accessToken: String?

    init(storage: StorageManager, baseUrl: String) {
        self.storage = storage
        self.baseUrl = baseUrl
    }

    /// Encrypt a local artifact for sync upload.
    func encryptForSync(urk: Data, record: ArtifactRecord) throws -> ArtifactEnvelope {
        let artKey = URK.deriveArtifactKey(urk: urk, artifactId: record.artifactId)
        let payload = record.payload

        let sha256Hex = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

        let sealedBox = try ChaChaPoly.seal(payload, using: artKey)
        let combined = sealedBox.combined
        let nonce = combined.prefix(12)
        let ctAndTag = combined.dropFirst(12)

        return ArtifactEnvelope(
            artifactId: record.artifactId,
            subjectId: record.subjectId,
            sessionId: record.sessionId,
            type: record.type,
            startMs: record.startMs,
            endMs: record.endMs,
            seq: record.seq,
            schemaName: record.schemaName,
            schemaVersion: record.schemaVersion,
            cryptoAlg: "CHACHA20POLY1305",
            nonceB64: nonce.base64EncodedString(),
            payloadSha256: sha256Hex,
            ciphertextB64: ctAndTag.base64EncodedString()
        )
    }

    /// Push unsynced artifacts to the server.
    func push(urk: Data) async throws -> Int {
        guard let token = accessToken else { return 0 }

        let artifacts = try storage.getUnsyncedArtifacts(limit: 50)
        if artifacts.isEmpty { return 0 }

        var envelopes: [[String: Any]] = []
        for art in artifacts {
            let env = try encryptForSync(urk: urk, record: art)
            envelopes.append(env.toJson())
        }

        let url = URL(string: "\(baseUrl)/v1/sync/push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["envelopes": envelopes])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return 0
        }

        for art in artifacts {
            try storage.markSynced(artifactId: art.artifactId)
        }
        return artifacts.count
    }

    /// Pull new artifacts from the server.
    func pull(urk: Data, smk: SMK, subjectId: String, cursor: String?) async throws -> Int {
        guard let token = accessToken else { return 0 }

        var totalPulled = 0
        var currentCursor = cursor

        while true {
            var components = URLComponents(string: "\(baseUrl)/v1/sync/pull")!
            var queryItems = [
                URLQueryItem(name: "subject_id", value: subjectId),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let c = currentCursor {
                queryItems.append(URLQueryItem(name: "cursor", value: c))
            }
            components.queryItems = queryItems

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { break }

            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawEnvelopes = body["envelopes"] as? [[String: Any]] else { break }

            for rawEnv in rawEnvelopes {
                let env = ArtifactEnvelope.fromJson(rawEnv)

                if try storage.isDeleted(artifactId: env.artifactId) { continue }
                if try storage.getArtifact(artifactId: env.artifactId) != nil { continue }

                // Decrypt
                let artKey = URK.deriveArtifactKey(urk: urk, artifactId: env.artifactId)
                guard let ctAndTag = Data(base64Encoded: env.ciphertextB64),
                      let nonce = Data(base64Encoded: env.nonceB64) else { continue }

                var combined = Data()
                combined.append(nonce)
                combined.append(ctAndTag)

                let plaintext: Data
                do {
                    let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
                    plaintext = try ChaChaPoly.open(sealedBox, using: artKey)
                } catch {
                    continue
                }

                // Verify integrity
                let digest = SHA256.hash(data: plaintext)
                let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()
                if sha256Hex != env.payloadSha256 { continue }

                // Merge conflict check: if a local artifact with the same
                // (session_id, type, start_ms, schema_version) exists and has
                // a lexicographically smaller artifact_id, skip the incoming one.
                if let sid = env.sessionId,
                   let existingId = try storage.findConflictingArtifactId(
                       sessionId: sid, type: env.type,
                       startMs: env.startMs, schemaVersion: env.schemaVersion),
                   existingId < env.artifactId {
                    continue
                }

                // Re-encrypt with SMK and store
                let localEncrypted = try ArtifactCrypto.encryptData(smk: smk, data: plaintext)
                // Build artifact record
                try storage.insertArtifact(ArtifactRecord(
                    artifactId: env.artifactId,
                    sessionId: env.sessionId,
                    subjectId: env.subjectId,
                    type: env.type,
                    schemaName: env.schemaName,
                    schemaVersion: env.schemaVersion,
                    startMs: env.startMs,
                    endMs: env.endMs,
                    seq: env.seq,
                    createdAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                    encAlg: ArtifactCrypto.encAlg,
                    payload: localEncrypted.ciphertext,
                    payloadSha256: localEncrypted.sha256,
                    syncState: "synced"
                ))
                totalPulled += 1
            }

            currentCursor = body["next_cursor"] as? String
            let hasMore = body["has_more"] as? Bool ?? false
            if !hasMore { break }
        }

        if let c = currentCursor {
            try storage.setSyncState(key: "cursor", value: c)
        }

        return totalPulled
    }
}
