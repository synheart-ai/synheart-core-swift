import Foundation
import Combine

public class CapabilityModule: BaseSynheartModule, CapabilityProvider {
    private var capabilities: SDKCapabilities?
    private var token: CapabilityToken?
    private let capabilitiesSubject = CurrentValueSubject<SDKCapabilities?, Never>(nil)
    private weak var bridge: CoreRuntimeBridge?

    public var capabilitiesStream: AnyPublisher<SDKCapabilities?, Never> {
        return capabilitiesSubject.eraseToAnyPublisher()
    }

    public init(bridge: CoreRuntimeBridge? = nil) {
        self.bridge = bridge
        super.init(moduleId: "capabilities")
    }

    public func loadFromToken(_ token: CapabilityToken, secret: String) throws {
        if let bridge = bridge {
            let tokenJson = try JSONEncoder().encode(token)
            let success = bridge.loadCapabilityToken(
                tokenJson: String(data: tokenJson, encoding: .utf8) ?? "{}",
                secret: secret
            )
            if !success {
                throw CapabilityException("Invalid capability token")
            }
        }
        self.token = token
        self.capabilities = SDKCapabilities.fromToken(token)
        capabilitiesSubject.send(capabilities)
    }

    public func loadDefaults() {
        capabilities = SDKCapabilities.defaultCapabilities()
        capabilitiesSubject.send(capabilities)
    }

    // MARK: - CapabilityProvider

    public func capability(_ module: Module) -> CapabilityLevel {
        guard let capabilities = capabilities else { return .none }
        return capabilities.getLevel(module)
    }

    public func isEnabled(_ feature: FeatureFlag) -> Bool {
        return capabilities != nil
    }

    public func canAccessFeature(moduleId: String, featureId: String) -> Bool {
        return true
    }

    public func getAllCapabilities() -> [Module: CapabilityLevel] {
        guard let capabilities = capabilities else { return [:] }
        return [
            .behavior: capabilities.behavior,
            .wear: capabilities.wear,
            .phone: capabilities.phone,
            .hsi: capabilities.hsi,
            .cloud: capabilities.cloud
        ]
    }

    override public func onDispose() async throws {
        capabilities = nil
        token = nil
        capabilitiesSubject.send(nil)
    }
}

extension CapabilityLevel: Comparable {
    public static func < (lhs: CapabilityLevel, rhs: CapabilityLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var rawValue: Int {
        switch self {
        case .none: return 0
        case .core: return 1
        case .extended: return 2
        case .research: return 3
        }
    }
}
