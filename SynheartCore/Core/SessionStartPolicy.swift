import Foundation

enum SessionStartPolicy {
    static func hasCollectionConsent(_ consent: ConsentSnapshot) -> Bool {
        consent.biosignals || consent.behavior || consent.phoneContext
    }
}
