import Foundation

public struct Provenance: Codable {
    public let source: String
    public let deviceId: String
    public let appId: String
    public let runtimeVersion: String

    public init(source: String, deviceId: String, appId: String, runtimeVersion: String) {
        self.source = source
        self.deviceId = deviceId
        self.appId = appId
        self.runtimeVersion = runtimeVersion
    }

    enum CodingKeys: String, CodingKey {
        case source
        case deviceId = "device_id"
        case appId = "app_id"
        case runtimeVersion = "runtime_version"
    }
}

public struct WindowData: Codable {
    public let startMs: Int64
    public let endMs: Int64
    public let windowSizeMs: Int
    public let hsi: [String: AnyCodable]

    public init(startMs: Int64, endMs: Int64, windowSizeMs: Int = 30000, hsi: [String: AnyCodable]) {
        self.startMs = startMs
        self.endMs = endMs
        self.windowSizeMs = windowSizeMs
        self.hsi = hsi
    }

    enum CodingKeys: String, CodingKey {
        case startMs = "start_ms"
        case endMs = "end_ms"
        case windowSizeMs = "window_size_ms"
        case hsi
    }
}

/// 30-second HSI computation window.
public struct HSIWindowArtifact: Codable {
    public let header: ArtifactHeader
    public let window: WindowData
    public let provenance: Provenance

    public init(header: ArtifactHeader, window: WindowData, provenance: Provenance) {
        self.header = header
        self.window = window
        self.provenance = provenance
    }

    public static func create(
        subjectId: String,
        sessionId: String,
        startMs: Int64,
        endMs: Int64,
        hsi: [String: AnyCodable],
        source: String,
        deviceId: String,
        appId: String,
        runtimeVersion: String
    ) -> HSIWindowArtifact {
        let header = ArtifactHeader(
            type: "hsi_window",
            subjectId: subjectId,
            sessionId: sessionId,
            timeRange: TimeRange(startMs: startMs, endMs: endMs),
            schema: SchemaRef(name: "hsi_window", version: "1")
        )
        return HSIWindowArtifact(
            header: header,
            window: WindowData(startMs: startMs, endMs: endMs, hsi: hsi),
            provenance: Provenance(source: source, deviceId: deviceId, appId: appId, runtimeVersion: runtimeVersion)
        )
    }
}

/// Type-erased Codable wrapper for arbitrary JSON values.
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) { value = intVal }
        else if let doubleVal = try? container.decode(Double.self) { value = doubleVal }
        else if let stringVal = try? container.decode(String.self) { value = stringVal }
        else if let boolVal = try? container.decode(Bool.self) { value = boolVal }
        else if let arrayVal = try? container.decode([AnyCodable].self) { value = arrayVal.map { $0.value } }
        else if let dictVal = try? container.decode([String: AnyCodable].self) { value = dictVal.mapValues { $0.value } }
        else if container.decodeNil() { value = NSNull() }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [Any]: try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]: try container.encode(v.mapValues { AnyCodable($0) })
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }
}
