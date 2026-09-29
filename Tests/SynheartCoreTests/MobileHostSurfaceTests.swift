import XCTest
@testable import SynheartCore

/// The mobile-host surface: runtime config keys, host declarations, accelerometer
/// placement, and the optional-symbol contract behind the new calls.
final class MobileHostSurfaceTests: XCTestCase {

    // MARK: Config keys

    func testDefaultsEmitNoneOfTheNewKeys() {
        let map = RuntimeConfigBuilder.build(SynheartConfig(appId: "a", subjectId: "s"))
        for key in ["window_ms", "extra_heads", "emit_diagnostics", "research_baseline",
                    "sensing", "device_class", "mask_profile", "cfi_structural_components"] {
            XCTAssertNil(map[key], "\(key) must be absent unless the host asked for it")
        }
    }

    func testFlagsAreEmittedOnlyWhenTrue() {
        let map = RuntimeConfigBuilder.build(SynheartConfig(
            appId: "a", subjectId: "s",
            windowMs: 60_000,
            extraHeads: [.activityState, .locomotionState],
            emitDiagnostics: true,
            researchBaseline: true
        ))
        XCTAssertEqual(map["window_ms"] as? Int, 60_000)
        XCTAssertEqual(map["extra_heads"] as? [String], ["activity_state", "locomotion_state"])
        XCTAssertEqual(map["emit_diagnostics"] as? Bool, true)
        XCTAssertEqual(map["research_baseline"] as? Bool, true)
    }

    func testHostDeclarationsAreSpreadAsTopLevelKeys() throws {
        let profile = SensingProfile(
            mode: .continuous,
            latenessBudgetMs: 30_000,
            streams: SensingStreams(cardiac: true, accelerometer: true, pointer: false)
        )
        let map = RuntimeConfigBuilder.build(SynheartConfig(
            appId: "a", subjectId: "s",
            hostDeclarations: HostDeclarations(
                sensing: .explicit(profile),
                deviceClass: .explicit(.phone),
                maskProfile: .auto,
                cfiStructuralComponents: 4
            )
        ))
        let sensing = try XCTUnwrap(map["sensing"] as? [String: Any])
        XCTAssertEqual(sensing["mode"] as? String, "continuous")
        XCTAssertEqual(sensing["lateness_budget_ms"] as? Int, 30_000)
        let streams = try XCTUnwrap(sensing["streams"] as? [String: Bool])
        XCTAssertEqual(streams, ["cardiac": true, "accelerometer": true, "pointer": false])
        XCTAssertEqual(map["device_class"] as? String, "phone")
        XCTAssertEqual(map["mask_profile"] as? String, "auto")
        XCTAssertEqual(map["cfi_structural_components"] as? Int, 4)
    }

    func testAutoDeclarationsSpellAuto() {
        let json = HostDeclarations.auto.toJSON()
        XCTAssertEqual(json["sensing"] as? String, "auto")
        XCTAssertEqual(json["device_class"] as? String, "auto")
        XCTAssertEqual(json["mask_profile"] as? String, "auto")
        XCTAssertEqual(json["cfi_structural_components"] as? Int, 4)
        XCTAssertFalse(HostDeclarations.auto.isEmpty)
        XCTAssertTrue(HostDeclarations().isEmpty)
    }

    func testStreamsOmitUndeclaredEntries() {
        XCTAssertTrue(SensingStreams().toJSON().isEmpty)
        XCTAssertEqual(SensingStreams(screenState: false).toJSON() as? [String: Bool], ["screen_state": false])
    }

    // MARK: Validation

    func testWindowMsMustBePositive() {
        XCTAssertThrowsError(try SynheartConfig(appId: "a", subjectId: "s", windowMs: 0).validate())
        XCTAssertNoThrow(try SynheartConfig(appId: "a", subjectId: "s", windowMs: 30_000).validate())
    }

    func testCfiStructuralComponentsMustNotBeNegative() {
        let bad = SynheartConfig(appId: "a", subjectId: "s",
                                 hostDeclarations: HostDeclarations(cfiStructuralComponents: -1))
        XCTAssertThrowsError(try bad.validate())
    }

    // MARK: Placement

    func testPlacementCodesMatchTheAbi() {
        XCTAssertEqual(AccelPlacement.allCases.map(\.code), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(AccelPlacement.unknown.code, 0)
        XCTAssertEqual(AccelPlacement.waist.code, 5)
    }

    func testOnlyPocketAndWaistAreInsideTheValidatedEnvelope() {
        let inside = AccelPlacement.allCases.filter(\.isValidatedEnvelope)
        XCTAssertEqual(Set(inside), [.pocket, .waist])
    }

    // MARK: Symbol contract

    func testMobileHostSymbolsAreOptionalNotRequired() {
        let symbols = [
            "synheart_core_tick", "synheart_core_tick_all", "synheart_core_flush_pending",
            "synheart_core_push_behavior_event", "synheart_core_push_context_event",
            "synheart_core_push_speed", "synheart_core_set_accel_placement",
            "synheart_core_declare_rest_window", "synheart_core_push_wrist_accel",
            "synheart_core_roll_day", "synheart_core_export_session_state",
            "synheart_core_load_session_state", "synheart_core_config_id",
            "synheart_core_last_hsv", "synheart_core_attach_strain_score_json",
        ]
        for s in symbols {
            XCTAssertTrue(RuntimeSymbolManifest.optional.contains(s), "\(s) should be an optional capability")
            XCTAssertFalse(RuntimeSymbolManifest.required.contains(s), "\(s) must not gate initialization")
        }
        // A runtime missing every one of them is still compatible.
        let resolved = RuntimeSymbolManifest.required
        XCTAssertTrue(RuntimeSymbolManifest.audit(resolvedSymbols: resolved).isCompatible)
    }

    func testFacadeIsInertWithoutARuntime() {
        // Nothing initialized in this process: every call must degrade to
        // "unavailable" rather than trap or fabricate a result.
        XCTAssertTrue(Synheart.mobileHostAbiSupport.isEmpty)
        XCTAssertNil(Synheart.pushBehaviorEvent(.screenOn(1)))
        XCTAssertNil(Synheart.pushContextEvent(.keyboard(1, .enter)))
        XCTAssertNil(Synheart.tick(nowMs: 1))
        XCTAssertNil(Synheart.tickAll(nowMs: 1))
        XCTAssertNil(Synheart.flushPending(nowMs: 1))
        XCTAssertNil(Synheart.rollDay(1))
        XCTAssertNil(Synheart.exportSessionState())
        XCTAssertNil(Synheart.configId)
        XCTAssertNil(Synheart.lastHsv())
        XCTAssertNil(Synheart.attachStrainScoreJson())
        Synheart.setAccelPlacement(.pocket)
        Synheart.pushSpeed(tsMs: 1, speedMps: 1.2)
        Synheart.declareRestWindow(tsMs: 1)
        Synheart.pushWristAccel(tsMs: 1, x: 0, y: 0, z: 1.0)
        Synheart.pushWornAccel(tsMs: 1, x: 0, y: 0, z: 1.0, placement: .wrist)
    }

    func testNotificationsObservableIsEmittedOnlyWhenDeclared() {
        XCTAssertNil(HostDeclarations().toJSON()["notifications_observable"])
        XCTAssertTrue(HostDeclarations().isEmpty)
        let off = HostDeclarations(notificationsObservable: false)
        XCTAssertEqual(off.toJSON()["notifications_observable"] as? Bool, false)
        XCTAssertFalse(off.isEmpty)
        let map = RuntimeConfigBuilder.build(SynheartConfig(appId: "a", subjectId: "s", hostDeclarations: off))
        XCTAssertEqual(map["notifications_observable"] as? Bool, false)
    }
}
