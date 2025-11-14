import Foundation

/// Raw signal data collected from various sources
public struct SignalData: Codable {
    public let type: SignalType
    public let value: Float
    public let timestamp: Date
    public let source: SignalSource
    public let metadata: [String: Any]?
    
    public enum SignalType: String, Codable {
        case heartRate = "heart_rate"
        case heartRateVariability = "hrv"
        case motion = "motion"
        case sleep = "sleep"
        case typing = "typing"
        case scrolling = "scrolling"
        case appSwitch = "app_switch"
        case context = "context"
    }
    
    public enum SignalSource: String, Codable {
        case wearSDK = "wear_sdk"
        case phoneSDK = "phone_sdk"
        case healthKit = "healthkit"
        case coreMotion = "coremotion"
        case contextAdapter = "context_adapter"
    }
    
    public init(type: SignalType,
                value: Float,
                timestamp: Date = Date(),
                source: SignalSource,
                metadata: [String: Any]? = nil) {
        self.type = type
        self.value = value
        self.timestamp = timestamp
        self.source = source
        self.metadata = metadata
    }
}

// Custom encoding/decoding for metadata dictionary
extension SignalData {
    enum CodingKeys: String, CodingKey {
        case type, value, timestamp, source, metadata
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(SignalType.self, forKey: .type)
        value = try container.decode(Float.self, forKey: .value)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decode(SignalSource.self, forKey: .source)
        
        // Decode metadata as JSON
        if let metadataData = try? container.decodeIfPresent(Data.self, forKey: .metadata),
           let json = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
            metadata = json
        } else {
            metadata = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
        
        // Encode metadata as JSON
        if let metadata = metadata,
           let jsonData = try? JSONSerialization.data(withJSONObject: metadata) {
            try container.encode(jsonData, forKey: .metadata)
        }
    }
}

