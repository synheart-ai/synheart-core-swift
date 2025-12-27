import Foundation

/// Metadata about the current state session
public struct MetaState: Codable {
    public let device: DeviceInfo
    public let sessionId: String
    public let timestamp: Date
    public let embeddings: [Float]?
    
    public init(device: DeviceInfo,
                sessionId: String = UUID().uuidString,
                timestamp: Date = Date(),
                embeddings: [Float]? = nil) {
        self.device = device
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.embeddings = embeddings
    }
}

