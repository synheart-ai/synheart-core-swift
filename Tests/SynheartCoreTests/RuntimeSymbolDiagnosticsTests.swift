import XCTest
@testable import SynheartCore

final class RuntimeSymbolDiagnosticsTests: XCTestCase {
    func testRuntimeVersionPrefersAuthoritativeBuildInfo() {
        let version = RuntimeVersionResolver.resolve(
            buildInfo: ["core_runtime": "0.21.1"],
            diagnostics: ["version": "0.20.0"]
        )

        XCTAssertEqual(version, "0.21.1")
    }

    func testRuntimeVersionFallsBackToDiagnosticsForOlderRuntime() {
        let version = RuntimeVersionResolver.resolve(
            buildInfo: nil,
            diagnostics: ["version": "0.16.4"]
        )

        XCTAssertEqual(version, "0.16.4")
    }

    func testRuntimeVersionRejectsEmptyMetadata() {
        let version = RuntimeVersionResolver.resolve(
            buildInfo: ["core_runtime": "  "],
            diagnostics: [:]
        )

        XCTAssertNil(version)
    }

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
            "synheart_core_abort_session",
            "synheart_core_is_lab_available",
            "synheart_core_close_orphan_session",
            "synheart_core_srm_push_wearable_daily",
            "synheart_core_srm_trigger_wearable_recompute",
            "synheart_core_stop_session_v2",
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

    func testStructuredStopSymbolsRemainOptionalForLegacyRuntimeCompatibility() {
        let symbols: Set<String> = [
            "synheart_core_abort_session",
            "synheart_core_stop_session_v2",
        ]

        XCTAssertTrue(symbols.isSubset(of: RuntimeSymbolManifest.optional))
        XCTAssertTrue(symbols.isDisjoint(with: RuntimeSymbolManifest.required))
    }

    func testConsentAuthoritySymbolsAreRequired() {
        let consentAuthority: Set<String> = [
            "synheart_core_current_consent",
            "synheart_core_grant_consent",
            "synheart_core_revoke_consent",
            "synheart_core_has_consent",
            "synheart_core_consent_clear_stored",
            "synheart_core_consent_effective_state",
        ]

        XCTAssertTrue(consentAuthority.isSubset(of: RuntimeSymbolManifest.required))
        XCTAssertTrue(consentAuthority.isDisjoint(with: RuntimeSymbolManifest.optional))
    }

    func testStableRuntimeRequiresHostONNXEntrypoint() {
        let result = RuntimeDependencyManifest.audit(
            runtimeEntrypointFound: true,
            edgeRuntimeFound: false,
            onnxRuntimeEntrypointFound: false
        )

        XCTAssertTrue(result.requiresExternalONNXRuntime)
        XCTAssertFalse(result.onnxRuntimeEntrypointFound)
        XCTAssertFalse(result.isCompatible)
        XCTAssertEqual(
            result.missingRequiredDependencies,
            [RuntimeDependencyManifest.onnxRuntimeDependency]
        )
    }

    func testStableRuntimeIsCompatibleWhenHostONNXIsLinked() {
        let result = RuntimeDependencyManifest.audit(
            runtimeEntrypointFound: true,
            edgeRuntimeFound: false,
            onnxRuntimeEntrypointFound: true
        )

        XCTAssertTrue(result.requiresExternalONNXRuntime)
        XCTAssertTrue(result.isCompatible)
        XCTAssertTrue(result.missingRequiredDependencies.isEmpty)
    }

    func testEdgeRuntimeDoesNotRequireHostONNX() {
        let result = RuntimeDependencyManifest.audit(
            runtimeEntrypointFound: true,
            edgeRuntimeFound: true,
            onnxRuntimeEntrypointFound: false
        )

        XCTAssertFalse(result.requiresExternalONNXRuntime)
        XCTAssertTrue(result.isCompatible)
        XCTAssertTrue(result.missingRequiredDependencies.isEmpty)
    }

    func testMissingRuntimeDoesNotReportAnInferredHostDependency() {
        let result = RuntimeDependencyManifest.audit(
            runtimeEntrypointFound: false,
            edgeRuntimeFound: false,
            onnxRuntimeEntrypointFound: false
        )

        XCTAssertFalse(result.requiresExternalONNXRuntime)
        XCTAssertTrue(result.isCompatible)
        XCTAssertTrue(result.missingRequiredDependencies.isEmpty)
    }
}
