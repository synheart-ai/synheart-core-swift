import Foundation
import Combine

protocol CapabilityTokenVerifying: AnyObject {
    func loadCapabilityToken(tokenJson: String, secret: String) -> Bool
}

extension CoreRuntimeBridge: CapabilityTokenVerifying {}

public class CapabilityModule: BaseSynheartModule, CapabilityProvider {
    private var capabilities: SDKCapabilities?
    private var token: CapabilityToken?
    private let capabilitiesSubject = CurrentValueSubject<SDKCapabilities?, Never>(nil)
    private weak var tokenVerifier: CapabilityTokenVerifying?

    public var capabilitiesStream: AnyPublisher<SDKCapabilities?, Never> {
        return capabilitiesSubject.eraseToAnyPublisher()
    }

    public init(bridge: CoreRuntimeBridge? = nil) {
        self.tokenVerifier = bridge
        super.init(moduleId: "capabilities")
    }

    init(tokenVerifier: CapabilityTokenVerifying?) {
        self.tokenVerifier = tokenVerifier
        super.init(moduleId: "capabilities")
    }

    @available(*, deprecated, message: "Use SynheartConfig.deviceAuthConfig for production capability enforcement")
    public func loadFromToken(_ token: CapabilityToken, secret: String) throws {
        try loadVerifiedToken(token, secret: secret)
    }

    func loadVerifiedToken(_ token: CapabilityToken, secret: String) throws {
        guard token.isValid else {
            throw CapabilityException("Capability token is expired or has an invalid validity window")
        }
        guard let tokenVerifier else {
            throw CapabilityException("Capability token verification is unavailable")
        }

        let tokenJson = try JSONEncoder().encode(token)
        let success = tokenVerifier.loadCapabilityToken(
            tokenJson: String(data: tokenJson, encoding: .utf8) ?? "{}",
            secret: secret
        )
        guard success else {
            throw CapabilityException("Invalid capability token signature")
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
