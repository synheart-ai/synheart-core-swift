import Foundation

/// Callback type for presenting consent UI
///
/// Apps can provide their own UI implementation. The callback receives
/// available consent profiles and should return the selected profile,
/// or nil if user declined.
public typealias ConsentUIProvider = ([ConsentProfile]) async -> ConsentProfile?

/// Manager for consent UI hooks
///
/// Provides a flexible way for apps to implement their own consent UI
/// while the SDK handles the backend integration.
public class ConsentUIManager {
    /// Custom UI provider (set by app)
    public var customUIProvider: ConsentUIProvider?

    public init(customUIProvider: ConsentUIProvider? = nil) {
        self.customUIProvider = customUIProvider
    }

    /// Present consent flow to user
    ///
    /// If customUIProvider is set, it will be called. Otherwise,
    /// returns nil (app must handle UI separately).
    public func presentConsentFlow(_ profiles: [ConsentProfile]) async -> ConsentProfile? {
        guard !profiles.isEmpty else {
            SynheartLogger.log("[ConsentUI] No consent profiles available")
            return nil
        }

        if let provider = customUIProvider {
            do {
                let selected = await provider(profiles)
                if let selected = selected {
                    SynheartLogger.log("[ConsentUI] User selected profile: \(selected.id)")
                } else {
                    SynheartLogger.log("[ConsentUI] User declined consent")
                }
                return selected
            }
        }

        // No custom UI provider - app must handle UI separately
        SynheartLogger.log("[ConsentUI] No custom UI provider set. App must implement consent UI.")
        return nil
    }

    /// Get default profile from list (if available)
    public func getDefaultProfile(_ profiles: [ConsentProfile]) -> ConsentProfile? {
        profiles.first(where: { $0.isDefault })
    }
}
