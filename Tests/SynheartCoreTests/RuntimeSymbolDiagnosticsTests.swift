import XCTest
@testable import SynheartCore

final class RuntimeSymbolDiagnosticsTests: XCTestCase {
    func testAuditSeparatesRequiredAndOptionalSymbols() {
        let missingRequired = "synheart_core_start_session"
        let missingOptional = "synheart_core_diagnostics"
        let resolved = RuntimeSymbolManifest.all.subtracting([
            missingRequired,
            missingOptional,
        ])

        let result = RuntimeSymbolManifest.audit(resolvedSymbols: resolved)

        XCTAssertTrue(result.runtimeEntrypointFound)
        XCTAssertFalse(result.isCompatible)
        XCTAssertEqual(result.missingRequiredSymbols, [missingRequired])
        XCTAssertEqual(result.missingOptionalSymbols, [missingOptional])
    }

    func testAuditIsCompatibleWhenOnlyOptionalSymbolsAreMissing() {
        let result = RuntimeSymbolManifest.audit(
            resolvedSymbols: RuntimeSymbolManifest.required
        )

        XCTAssertTrue(result.runtimeEntrypointFound)
        XCTAssertTrue(result.isCompatible)
        XCTAssertTrue(result.missingRequiredSymbols.isEmpty)
        XCTAssertEqual(
            Set(result.missingOptionalSymbols),
            RuntimeSymbolManifest.optional
        )
    }

    func testManifestCategoriesDoNotOverlap() {
        XCTAssertTrue(
            RuntimeSymbolManifest.required
                .intersection(RuntimeSymbolManifest.optional)
                .isEmpty
        )
    }

    func testManifestUsesCurrentRuntimeSymbolNames() {
        let currentNames: Set<String> = [
            "synheart_core_is_lab_available",
            "synheart_core_close_orphan_session",
            "synheart_core_srm_push_wearable_daily",
            "synheart_core_srm_trigger_wearable_recompute",
            "synheart_core_wearable_reference_json",
        ]
        let retiredNames: Set<String> = [
            "synheart_core_lab_available",
            "synheart_core_push_wearable_daily_value",
            "synheart_core_trigger_wearable_recompute",
            "synheart_core_get_wearable_reference",
        ]

        XCTAssertTrue(currentNames.isSubset(of: RuntimeSymbolManifest.all))
        XCTAssertTrue(retiredNames.isDisjoint(with: RuntimeSymbolManifest.all))
    }

    func testConsentAuthoritySymbolsAreRequired() {
        let consentAuthority: Set<String> = [
            "synheart_core_current_consent",
            "synheart_core_grant_consent",
            "synheart_core_revoke_consent",
            "synheart_core_has_consent",
            "synheart_core_consent_clear_stored",
        ]

        XCTAssertTrue(consentAuthority.isSubset(of: RuntimeSymbolManifest.required))
        XCTAssertTrue(consentAuthority.isDisjoint(with: RuntimeSymbolManifest.optional))
    }
}
