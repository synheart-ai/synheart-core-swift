import Foundation

enum SessionStartPolicy {
    static func operationalCollectionFeatures(
        consent: ConsentSnapshot,
        activated: Set<SynheartFeature>,
        capabilityAllowed: (SynheartFeature) -> Bool
    ) -> Set<SynheartFeature> {
        Set([SynheartFeature.wear, .behavior, .phoneContext].filter { feature in
            activated.contains(feature)
                && hasConsent(for: feature, consent: consent)
                && capabilityAllowed(feature)
        })
    }

    private static func hasConsent(
        for feature: SynheartFeature,
        consent: ConsentSnapshot
    ) -> Bool {
        switch feature {
        case .wear: return consent.biosignals
        case .behavior: return consent.behavior
        case .phoneContext: return consent.phoneContext
        case .cloud, .syni: return false
        }
    }
}
