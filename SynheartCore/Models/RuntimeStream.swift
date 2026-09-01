import Foundation

public struct VendorStreamConfig: Sendable {
    public let host: String
    public let port: Int
    public let appId: String
    public let deviceId: String
    public let userId: String
    public let apiKey: String?
    public let useTLS: Bool
    public let providers: [String]
    public let eventTypes: [String]

    public init(
        host: String,
        port: Int,
        appId: String,
        deviceId: String,
        userId: String,
        apiKey: String? = nil,
        useTLS: Bool = true,
        providers: [String] = [],
        eventTypes: [String] = []
    ) {
        self.host = host
        self.port = port
        self.appId = appId
        self.deviceId = deviceId
        self.userId = userId
        self.apiKey = apiKey
        self.useTLS = useTLS
        self.providers = providers
        self.eventTypes = eventTypes
    }

    func jsonString() -> String? {
        guard !host.isEmpty, port > 0, !appId.isEmpty, !deviceId.isEmpty, !userId.isEmpty else { return nil }
        var map: [String: Any] = [
            "host": host,
            "port": port,
            "app_id": appId,
            "device_id": deviceId,
            "user_id": userId,
            "use_tls": useTLS,
            "providers": providers,
            "event_types": eventTypes,
        ]
        if let apiKey { map["api_key"] = apiKey }
        guard let data = try? JSONSerialization.data(withJSONObject: map) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public enum RuntimeLogging {
    /// Initializes the runtime's crash-safe pull-based logging buffer.
    @discardableResult
    public static func initialize(environmentFilter: String = "info") -> Int32 {
        CoreRuntimeBridge.initializeBufferedLogging(configJson: environmentFilter)
    }

    /// Removes and returns all currently buffered runtime log lines.
    public static func drain() -> String? { CoreRuntimeBridge.drainRuntimeLogs() }

    public static var droppedLineCount: UInt64 { CoreRuntimeBridge.droppedRuntimeLogLines }

    @discardableResult
    public static func shutdown() -> Int32 { CoreRuntimeBridge.shutdownRuntimeLogging() }
}
