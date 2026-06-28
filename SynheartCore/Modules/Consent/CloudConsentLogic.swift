import Foundation

/// Pure decision logic for cloud-consent readiness, factored out of `Synheart`
/// so it can be unit-tested without the native runtime or a device. Each
/// function is a total, side-effect-free mapping over already-fetched state.
enum CloudConsentLogic {

    /// True when a loaded consent token's subject (its minted `user_id`) differs
    /// from the runtime's current subject. A consent token is subject-scoped:
    /// one issued for a previous subject (e.g. a different signed-in account)
    /// must be reissued for the current subject before use.
    ///
    /// Conservative: returns false (not stale) when the current subject is
    /// unknown, there is no token subject, or either side is blank — so a stable
    /// or legacy token is never needlessly reissued.
    static func isTokenSubjectStale(tokenUserId: String?, currentSubject: String?) -> Bool {
        let subject = currentSubject?.trimmingCharacters(in: .whitespaces)
        guard let subject = subject, !subject.isEmpty else { return false }
        let tokenSub = tokenUserId?.trimmingCharacters(in: .whitespaces)
        guard let tokenSub = tokenSub, !tokenSub.isEmpty else { return false }
        return tokenSub != subject
    }

    /// Whether a cloud consent token is already usable without reissuing it:
    /// granted + not-soon-to-expire + minted for the current subject.
    static func isReadyWithoutReissue(status: String?, needsRefresh: Bool, subjectStale: Bool) -> Bool {
        return status?.trimmingCharacters(in: .whitespaces).lowercased() == "granted"
            && !needsRefresh
            && !subjectStale
    }

    /// Whether a `submit_form` result represents a successfully issued token.
    /// The runtime returns `synced=false, token=null` (without `error`) when the
    /// cloud profile fetch or token-issue call failed; treating that as success
    /// would silently drop uploads for the session.
    static func submitIssuedToken(synced: Bool, hasToken: Bool) -> Bool {
        return synced && hasToken
    }
}
