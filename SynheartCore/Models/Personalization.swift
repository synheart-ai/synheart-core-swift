import Foundation

public enum TaskType: Int32, CaseIterable, Sendable {
    case unknown = 0
    case focus = 1
    case recovery = 2
    case movement = 3
    case conversation = 4

    static func decode(_ value: Int32) -> TaskType { TaskType(rawValue: value) ?? .unknown }
}

public enum FocusKind: Int32, CaseIterable, Sendable {
    case unknown = 0
    case easy = 1
    case medium = 2
    case hard = 3

    static func decode(_ value: Int32) -> FocusKind { FocusKind(rawValue: value) ?? .unknown }
}

public enum WorkoutKind: Int32, CaseIterable, Sendable {
    case unknown = 0
    case cardio = 1
    case strength = 2
    case hiit = 3
    case lowIntensity = 4
    case sport = 5

    static func decode(_ value: Int32) -> WorkoutKind { WorkoutKind(rawValue: value) ?? .unknown }
}

public struct WorkoutEvent: Sendable {
    public let startTime: Date
    public let endTime: Date
    public let kind: WorkoutKind
    public let source: String
    public let vendorStrain: Double?
    public let vendorRecovery: Double?
    public let providerActivityId: String?

    public init(
        startTime: Date,
        endTime: Date,
        kind: WorkoutKind,
        source: String,
        vendorStrain: Double? = nil,
        vendorRecovery: Double? = nil,
        providerActivityId: String? = nil
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.kind = kind
        self.source = source
        self.vendorStrain = vendorStrain
        self.vendorRecovery = vendorRecovery
        self.providerActivityId = providerActivityId
    }

    var strainForRuntime: Double {
        guard let vendorStrain, (0...1).contains(vendorStrain) else { return -1 }
        return vendorStrain
    }

    var recoveryForRuntime: Double {
        guard let vendorRecovery, (0...1).contains(vendorRecovery) else { return -1 }
        return vendorRecovery
    }
}
