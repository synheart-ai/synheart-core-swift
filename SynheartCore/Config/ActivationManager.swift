import Foundation

/// Internal manager that tracks which features the developer has activated.
///
/// Part of the four-authority activation model (RFC-0005 Section 6):
/// ```
/// FeatureOperational = Activation AND Consent AND Capability AND SessionActive
/// ```
///
/// This class manages the **Activation** authority — the developer's explicit
/// intent to use a feature.
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

    /// Bulk-activate features based on SynheartConfig flags.
    ///
    /// Maps config booleans/objects to the corresponding feature activations:
    /// - `enableWear` → `.wear`
    /// - `enablePhone` → `.phoneContext`
    /// - `enableBehavior` → `.behavior`
    /// - `cloudConfig != nil` → `.cloud`
    func activateFromConfig(_ config: SynheartConfig) {
        if config.enableWear {
            activated.insert(.wear)
        }
        if config.enablePhone {
            activated.insert(.phoneContext)
        }
        if config.enableBehavior {
            activated.insert(.behavior)
        }
        if config.cloudConfig != nil {
            activated.insert(.cloud)
        }
    }
}
