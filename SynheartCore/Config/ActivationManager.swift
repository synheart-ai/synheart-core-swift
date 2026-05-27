import Foundation

/// Internal manager that tracks which features the developer has activated.
///
/// Part of the four-authority activation model:
/// ```
/// FeatureOperational = Activation AND Consent AND Capability AND SessionActive
/// ```
final class ActivationManager {
    private var activated: Set<SynheartFeature> = []

    /// Activate a feature (add to set).
    func activate(_ feature: SynheartFeature) {
        activated.insert(feature)
    }

    /// Deactivate a feature (remove from set).
    func deactivate(_ feature: SynheartFeature) {
        activated.remove(feature)
    }

    /// Check if a feature is activated.
    func isActivated(_ feature: SynheartFeature) -> Bool {
        activated.contains(feature)
    }

    /// Return a copy of all activated features.
    func activatedFeatures() -> Set<SynheartFeature> {
        activated
    }

    /// Bulk-activate features based on SynheartConfig.
    ///
    /// Maps config objects to the corresponding feature activations:
    /// - `cloudConfig != nil` → `.cloud`
    func activateFromConfig(_ config: SynheartConfig) {
        if config.cloudConfig != nil {
            activated.insert(.cloud)
        }
    }
}
