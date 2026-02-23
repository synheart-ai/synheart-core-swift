import Foundation

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Device and platform information
public struct DeviceInfo: Codable {
    public let platform: String
    public let osVersion: String
    public let deviceModel: String
    public let deviceId: String

    public init(platform: String = "iOS",
                osVersion: String? = nil,
                deviceModel: String? = nil,
                deviceId: String? = nil) {
        self.platform = platform

        #if os(iOS)
        self.osVersion = osVersion ?? UIDevice.current.systemVersion
        self.deviceModel = deviceModel ?? UIDevice.current.model
        self.deviceId = deviceId ?? UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        #elseif os(watchOS)
        self.osVersion = osVersion ?? WKInterfaceDevice.current().systemVersion
        self.deviceModel = deviceModel ?? WKInterfaceDevice.current().model
        self.deviceId = deviceId ?? "watch-\(WKInterfaceDevice.current().name.hashValue)"
        #else
        self.osVersion = osVersion ?? ProcessInfo.processInfo.operatingSystemVersionString
        self.deviceModel = deviceModel ?? "Unknown"
        self.deviceId = deviceId ?? "unknown"
        #endif
    }
}

