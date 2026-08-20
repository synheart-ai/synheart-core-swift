import Foundation

protocol NativeConsentManaging: AnyObject {
    func grantConsent(_ type: String) -> Bool
    func revokeConsent(_ type: String) -> Bool
    func currentConsent() -> [String: Any]?
    func clearStoredConsent() -> Bool
}

extension SynheartCoreShim: NativeConsentManaging {
    func clearStoredConsent() -> Bool {
        bridge?.consentClearStored() ?? false
    }
}

enum ConsentRuntimeCoordinator {
    private struct Mutation {
        let type: ConsentType
        let granted: Bool
    }

    static func apply(
        _ target: ConsentSnapshot,
        replacing current: ConsentSnapshot,
        through runtime: NativeConsentManaging
    ) -> SynheartError? {
        guard target.tier == current.tier,
              channelsEquivalent(target.channels, current.channels) else {
            return .invalidArgument(
                "Tier and channel consent must be updated through the native consent-form API"
            )
        }

        let mutations = [
            mutation(.biosignals, target.biosignals, current.biosignals),
            mutation(.behavior, target.behavior, current.behavior),
            mutation(.phoneContext, target.phoneContext, current.phoneContext),
            mutation(.cloudUpload, target.cloudUpload, current.cloudUpload),
            mutation(.syni, target.syni, current.syni),
            mutation(.focusEstimation, target.focusEstimation, current.focusEstimation),
            mutation(.emotionEstimation, target.emotionEstimation, current.emotionEstimation),
            mutation(.vendorSync, target.vendorSync, current.vendorSync),
        ].compactMap { $0 }

        var applied: [Mutation] = []
        for mutation in mutations {
            let succeeded = mutation.granted
                ? runtime.grantConsent(mutation.type.rawValue)
                : runtime.revokeConsent(mutation.type.rawValue)
            guard succeeded else {
                // The C ABI updates one category at a time. Compensate for any
                // earlier successful updates so a failed batch leaves both
                // native and Swift consent at the original snapshot.
                for completed in applied.reversed() {
                    if completed.granted {
                        _ = runtime.revokeConsent(completed.type.rawValue)
                    } else {
                        _ = runtime.grantConsent(completed.type.rawValue)
                    }
                }
                return .runtimeOperationFailed(
                    "Native runtime rejected \(mutation.type.rawValue) consent update"
                )
            }
            applied.append(mutation)
        }
        return nil
    }

    static func restore(
        from runtime: NativeConsentManaging,
        fallback: ConsentSnapshot = .none()
    ) -> ConsentSnapshot? {
        guard let map = runtime.currentConsent() else { return nil }
        func bool(_ snakeCase: String, _ camelCase: String? = nil) -> Bool {
            (map[snakeCase] as? Bool)
                ?? camelCase.flatMap { map[$0] as? Bool }
                ?? false
        }

        let timestamp: Date
        if let timestampMs = (map["timestamp_ms"] as? NSNumber)?.doubleValue {
            timestamp = Date(timeIntervalSince1970: timestampMs / 1_000)
        } else {
            timestamp = fallback.timestamp
        }

        return ConsentSnapshot(
            biosignals: bool("biosignals"),
            behavior: bool("behavior"),
            phoneContext: bool("phone_context", "phoneContext"),
            cloudUpload: bool("cloud_upload", "cloudUpload"),
            syni: bool("syni"),
            focusEstimation: fallback.focusEstimation,
            emotionEstimation: fallback.emotionEstimation,
            vendorSync: bool("vendor_sync", "vendorSync"),
            tier: fallback.tier,
            channels: fallback.channels,
            timestamp: timestamp,
            version: (map["version"] as? String) ?? fallback.version
        )
    }

    private static func mutation(
        _ type: ConsentType,
        _ target: Bool,
        _ current: Bool
    ) -> Mutation? {
        target == current ? nil : Mutation(type: type, granted: target)
    }

    private static func channelsEquivalent(
        _ lhs: ConsentChannels?,
        _ rhs: ConsentChannels?
    ) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        guard let lhsData = try? JSONEncoder().encode(lhs),
              let rhsData = try? JSONEncoder().encode(rhs) else { return false }
        return lhsData == rhsData
    }
}
