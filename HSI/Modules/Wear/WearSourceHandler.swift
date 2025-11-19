import Foundation
import Combine

/// Types of wear data sources
public enum WearSourceType: String {
    case appleHealth
    case googleFit
    case whoop
    case garmin
    case mock
}

/// Raw wear sample from a data source
public struct WearSample {
    public let timestamp: Date
    public let hr: Double?
    public let hrvRmssd: Double?
    public let respRate: Double?
    public let motionLevel: Double?
    public let sleepStage: SleepStage?
    public let rrIntervals: [Double]?
    
    public init(
        timestamp: Date,
        hr: Double? = nil,
        hrvRmssd: Double? = nil,
        respRate: Double? = nil,
        motionLevel: Double? = nil,
        sleepStage: SleepStage? = nil,
        rrIntervals: [Double]? = nil
    ) {
        self.timestamp = timestamp
        self.hr = hr
        self.hrvRmssd = hrvRmssd
        self.respRate = respRate
        self.motionLevel = motionLevel
        self.sleepStage = sleepStage
        self.rrIntervals = rrIntervals
    }
}

/// Abstract handler for wearable data sources
///
/// Each vendor (Apple Health, Google Fit, WHOOP, etc.) implements this protocol
public protocol WearSourceHandler: AnyObject {
    /// Source type identifier
    var sourceType: WearSourceType { get }
    
    /// Whether this source is available on the current platform
    var isAvailable: Bool { get }
    
    /// Initialize the data source
    func initialize() async throws
    
    /// Stream of wear samples
    var sampleStream: AnyPublisher<WearSample, Error> { get }
    
    /// Stop and cleanup
    func dispose() async throws
}

