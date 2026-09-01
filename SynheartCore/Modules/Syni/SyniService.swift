import Foundation

public enum SyniServiceErrorCode: String, Sendable {
    case invalidInput, notFound, authentication, network
    case unsupported, unavailable, unknown
}

public struct SyniServiceError: Error, Sendable, CustomStringConvertible {
    public let code: SyniServiceErrorCode
    public let message: String
    public let rawError: String?

    public var deliveryUnknown: Bool { rawError?.lowercased().contains("delivery unknown") == true }
    public var quotaExceeded: Bool { rawError?.lowercased().contains("quota exceeded") == true }
    public var description: String { "SyniServiceError(\(code.rawValue)): \(message)" }

    static func decode(_ raw: String) -> SyniServiceError {
        let upper = raw.uppercased()
        let code: SyniServiceErrorCode
        if upper.hasPrefix("ERR_INVALID_INPUT") { code = .invalidInput }
        else if upper.hasPrefix("ERR_NOT_FOUND") { code = .notFound }
        else if upper.hasPrefix("ERR_AUTH") || upper.contains("REGISTERED DEVICE") { code = .authentication }
        else if upper.hasPrefix("ERR_NETWORK") { code = .network }
        else if upper.hasPrefix("ERR_UNSUPPORTED") { code = .unsupported }
        else if upper.hasPrefix("ERR_UNAVAILABLE") { code = .unavailable }
        else { code = .unknown }
        let message = raw.split(separator: ":", maxSplits: 1).last.map(String.init) ?? raw
        return SyniServiceError(code: code, message: message.trimmingCharacters(in: .whitespaces), rawError: raw)
    }
}

public struct SyniServiceChatResponse {
    public let sessionId: String
    public let reply: String
    public let model: [String: Any]?
    public let state: [String: Any]?
    public let raw: [String: Any]

    init(runtimeMap: [String: Any]) throws {
        guard let sessionId = runtimeMap["session_id"] as? String, !sessionId.isEmpty,
              let reply = runtimeMap["reply"] as? String else {
            throw SyniServiceError(
                code: .unknown,
                message: "Syni chat response is missing session_id or reply",
                rawError: nil
            )
        }
        self.sessionId = sessionId
        self.reply = reply
        model = runtimeMap["model"] as? [String: Any]
        state = runtimeMap["state"] as? [String: Any]
        raw = runtimeMap
    }
}

public struct SyniServiceSession {
    public let id: String
    public let createdAt: Date?
    public let updatedAt: Date?
    public let status: String?
    public let personaId: String?
    public let modelId: String?
    public let raw: [String: Any]

    init(runtimeMap: [String: Any]) throws {
        guard let id = (runtimeMap["id"] ?? runtimeMap["session_id"]) as? String, !id.isEmpty else {
            throw SyniServiceError(code: .unknown, message: "Syni session is missing id", rawError: nil)
        }
        self.id = id
        createdAt = Self.date(runtimeMap["created_at"])
        updatedAt = Self.date(runtimeMap["updated_at"])
        status = runtimeMap["status"] as? String
        personaId = runtimeMap["persona_id"] as? String
        modelId = runtimeMap["model_id"] as? String
        raw = runtimeMap
    }

    private static func date(_ value: Any?) -> Date? {
        if let value = value as? String { return ISO8601DateFormatter().date(from: value) }
        if let value = value as? NSNumber { return Date(timeIntervalSince1970: value.doubleValue / 1_000) }
        return nil
    }
}

public struct SyniServiceMessage {
    public let id: String?
    public let role: String
    public let content: String
    public let createdAt: Date?
    public let raw: [String: Any]

    init(runtimeMap: [String: Any]) throws {
        guard let role = runtimeMap["role"] as? String,
              let content = (runtimeMap["content"] ?? runtimeMap["message"]) as? String else {
            throw SyniServiceError(code: .unknown, message: "Syni message is missing role or content", rawError: nil)
        }
        id = (runtimeMap["id"] ?? runtimeMap["message_id"]) as? String
        self.role = role
        self.content = content
        if let rawDate = runtimeMap["created_at"] as? String {
            createdAt = ISO8601DateFormatter().date(from: rawDate)
        } else {
            createdAt = nil
        }
        raw = runtimeMap
    }
}

public struct SyniServiceMessagesPage {
    public let sessionId: String
    public let messages: [SyniServiceMessage]
    public let count: Int
    public let raw: [String: Any]

    init(runtimeMap: [String: Any]) throws {
        guard let sessionId = runtimeMap["session_id"] as? String, !sessionId.isEmpty else {
            throw SyniServiceError(code: .unknown, message: "Syni messages response is missing session_id", rawError: nil)
        }
        self.sessionId = sessionId
        messages = try (runtimeMap["messages"] as? [[String: Any]] ?? []).map(SyniServiceMessage.init(runtimeMap:))
        count = (runtimeMap["count"] as? NSNumber)?.intValue ?? messages.count
        raw = runtimeMap
    }
}

/// Device-signed, non-streaming Syni cloud client backed by Core Runtime.
public actor SyniServiceClient {
    private let bridge: CoreRuntimeBridge
    private var currentSessionId: String?

    init(bridge: CoreRuntimeBridge) {
        self.bridge = bridge
    }

    public var isAvailable: Bool { bridge.isSyniServiceAvailable }
    public var sessionId: String? { currentSessionId }

    public func useSession(_ sessionId: String?) throws {
        if let sessionId { try Self.validateSessionId(sessionId) }
        currentSessionId = sessionId
    }

    public func startNewSession() { currentSessionId = nil }

    public func chat(
        _ message: String,
        sessionId: String? = nil,
        personaId: String? = nil,
        persona: String? = nil,
        modelId: String? = nil,
        includeState: Bool = false,
        context: [String: Any]? = nil
    ) async throws -> SyniServiceChatResponse {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SyniServiceError(code: .invalidInput, message: "message must not be empty", rawError: nil)
        }
        let effectiveSession = sessionId ?? currentSessionId
        if let effectiveSession { try Self.validateSessionId(effectiveSession) }
        var request: [String: Any] = ["message": message]
        if let effectiveSession { request["session_id"] = effectiveSession }
        if let personaId { request["persona_id"] = personaId }
        else if let persona { request["persona"] = persona }
        if let modelId { request["model_id"] = modelId }
        if includeState { request["include_state"] = true }
        if let context { request["context"] = context }
        let data = try JSONSerialization.data(withJSONObject: request)
        let requestJson = String(decoding: data, as: UTF8.self)
        guard let response = await RuntimeWorkExecutor.run({ self.bridge.syniChat(requestJson: requestJson) }) else {
            throw SyniServiceError(code: .unsupported, message: "Syni service requires Core Runtime 0.21.0 or newer", rawError: nil)
        }
        try Self.throwRuntimeError(response)
        let parsed = try SyniServiceChatResponse(runtimeMap: response)
        currentSessionId = parsed.sessionId
        return parsed
    }

    public func listSessions(limit: Int32 = 0) async throws -> [SyniServiceSession] {
        let response = await RuntimeWorkExecutor.run { self.bridge.syniListSessions(limit: limit) }
        guard let response else { throw Self.unsupported() }
        try Self.throwRuntimeError(response)
        return try (response["sessions"] as? [[String: Any]] ?? []).map(SyniServiceSession.init(runtimeMap:))
    }

    public func getSession(_ sessionId: String) async throws -> SyniServiceSession {
        try Self.validateSessionId(sessionId)
        guard let response = await RuntimeWorkExecutor.run({ self.bridge.syniGetSession(sessionId: sessionId) }) else {
            throw Self.unsupported()
        }
        try Self.throwRuntimeError(response)
        return try SyniServiceSession(runtimeMap: response)
    }

    public func messages(_ sessionId: String, limit: Int32 = 0) async throws -> SyniServiceMessagesPage {
        try Self.validateSessionId(sessionId)
        guard let response = await RuntimeWorkExecutor.run({
            self.bridge.syniGetSessionMessages(sessionId: sessionId, limit: limit)
        }) else { throw Self.unsupported() }
        try Self.throwRuntimeError(response)
        return try SyniServiceMessagesPage(runtimeMap: response)
    }

    public func closeSession(_ sessionId: String) async throws {
        try Self.validateSessionId(sessionId)
        guard let response = await RuntimeWorkExecutor.run({ self.bridge.syniCloseSession(sessionId: sessionId) }) else {
            throw Self.unsupported()
        }
        try Self.throwRuntimeError(response)
        if currentSessionId == sessionId { currentSessionId = nil }
    }

    private static func validateSessionId(_ value: String) throws {
        if value.isEmpty || value.rangeOfCharacter(from: CharacterSet(charactersIn: "/ \t\n?#")) != nil {
            throw SyniServiceError(code: .invalidInput, message: "session_id contains an invalid character", rawError: nil)
        }
    }

    private static func throwRuntimeError(_ map: [String: Any]) throws {
        if let error = map["error"] as? String, !error.isEmpty { throw SyniServiceError.decode(error) }
    }

    private static func unsupported() -> SyniServiceError {
        SyniServiceError(code: .unsupported, message: "Syni service requires Core Runtime 0.21.0 or newer", rawError: nil)
    }
}
