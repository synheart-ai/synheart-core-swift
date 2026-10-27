import Foundation

/// How the host samples over time, declared to the runtime as `sensing.mode`.
public enum SensingMode: String, CaseIterable, Codable, Sendable {
    /// Streams run for the whole session; windows close on the clock.
    case continuous
    /// Streams run only around discrete interactions; windows between them are
    /// expected to be empty and are not scored as absence.
    case episodic
}

/// Which streams the host actually feeds. `nil` means *undeclared*, which the
/// runtime treats differently from an explicit `false`.
public struct SensingStreams: Equatable, Sendable {
    public var cardiac: Bool?
    public var accelerometer: Bool?
    public var keystrokes: Bool?
    public var pointer: Bool?
    public var appFocus: Bool?
    public var notificationArrivals: Bool?
    public var notificationResponses: Bool?
    public var screenState: Bool?

    public init(
        cardiac: Bool? = nil,
        accelerometer: Bool? = nil,
        keystrokes: Bool? = nil,
        pointer: Bool? = nil,
        appFocus: Bool? = nil,
        notificationArrivals: Bool? = nil,
        notificationResponses: Bool? = nil,
        screenState: Bool? = nil
    ) {
        self.cardiac = cardiac
        self.accelerometer = accelerometer
        self.keystrokes = keystrokes
        self.pointer = pointer
        self.appFocus = appFocus
        self.notificationArrivals = notificationArrivals
        self.notificationResponses = notificationResponses
        self.screenState = screenState
    }

    public func toJSON() -> [String: Any] {
        var out: [String: Any] = [:]
        if let v = cardiac { out["cardiac"] = v }
        if let v = accelerometer { out["accelerometer"] = v }
        if let v = keystrokes { out["keystrokes"] = v }
        if let v = pointer { out["pointer"] = v }
        if let v = appFocus { out["app_focus"] = v }
        if let v = notificationArrivals { out["notification_arrivals"] = v }
        if let v = notificationResponses { out["notification_responses"] = v }
        if let v = screenState { out["screen_state"] = v }
        return out
    }
}

/// The full `sensing` declaration: mode, optional lateness budget, and the
/// stream roster.
public struct SensingProfile: Equatable, Sendable {
    public var mode: SensingMode
    /// How long the runtime holds a closed window for late-arriving samples
    /// before emitting it. Omit to take the runtime default.
    public var latenessBudgetMs: Int?
    public var streams: SensingStreams?

    public init(mode: SensingMode, latenessBudgetMs: Int? = nil, streams: SensingStreams? = nil) {
        self.mode = mode
        self.latenessBudgetMs = latenessBudgetMs
        self.streams = streams
    }

    public func toJSON() -> [String: Any] {
        var out: [String: Any] = ["mode": mode.rawValue]
        if let v = latenessBudgetMs { out["lateness_budget_ms"] = v }
        if let s = streams { out["streams"] = s.toJSON() }
        return out
    }
}

/// The device class whose behaviour baselines the device teaches.
///
/// One baseline snapshot holds every class (runtime 0.42+), so changing it
/// starts that class from zero and keeps the others. Left `nil`, the SDK
/// sends `"auto"`: an undeclared class files behaviour baselines under
/// `unknown`.
public enum DeviceClass: String, CaseIterable, Codable, Sendable {
    case desktop
    case phone
    case tablet
    case watch
}

/// Which mask profile the runtime applies to its outputs.
public enum MaskProfile: String, CaseIterable, Codable, Sendable {
    case desktop
    case mobile
}

/// A host declaration value: the runtime's own auto-detection, or an explicit
/// declaration.
public enum HostDeclaration<Explicit: Equatable & Sendable>: Equatable, Sendable {
    /// Let the runtime choose (`"auto"` on the wire).
    case auto
    /// Declare explicitly.
    case explicit(Explicit)
}

/// Host declarations that change engine output — `sensing`, `device_class`,
/// `mask_profile`, `cfi_structural_components`.
///
/// Each field is spread into the runtime config as a top-level key; an absent
/// key means *undeclared*, which is a distinct state from a declared default,
/// so ``toJSON()`` emits nothing for `nil`. Two defaults are added when the
/// config is built: `device_class` `"auto"` and `input_observable` `false`
/// (see ``deviceClass`` and ``inputObservable``).
public struct HostDeclarations: Equatable, Sendable {
    public var sensing: HostDeclaration<SensingProfile>?
    public var deviceClass: HostDeclaration<DeviceClass>?
    public var maskProfile: HostDeclaration<MaskProfile>?
    /// Number of structural CFI components the host can supply.
    public var cfiStructuralComponents: Int?
    /// Whether a notification producer actually runs on this host, so that a
    /// window with no notifications is evidence of low demand rather than no
    /// evidence (runtime ≥ 0.32.0). `nil` sends nothing, and the runtime then
    /// resolves it from `platform`. A host whose listener is not running (not
    /// granted, not implemented) should declare `false`, or every quiet window
    /// reads as low demand. Older runtimes ignore the key.
    public var notificationsObservable: Bool?
    /// Whether this host's input capture is reported (runtime 0.42+), which
    /// decides when a still window counts as rest and can teach the resting
    /// heart rate and HRV.
    ///
    /// `nil` sends `false`: a quiet window's input is taken as none, so rest
    /// is learnable from stillness on every host. Declare `true` when the
    /// behaviour feature runs: the SDK then reports its in-app capture
    /// running while it collects and the app is active, and only those quiet
    /// windows count as input-free — a window in the background, where the
    /// person may be typing elsewhere, never does.
    public var inputObservable: Bool?

    public init(
        sensing: HostDeclaration<SensingProfile>? = nil,
        deviceClass: HostDeclaration<DeviceClass>? = nil,
        maskProfile: HostDeclaration<MaskProfile>? = nil,
        cfiStructuralComponents: Int? = nil,
        notificationsObservable: Bool? = nil,
        inputObservable: Bool? = nil
    ) {
        self.sensing = sensing
        self.deviceClass = deviceClass
        self.maskProfile = maskProfile
        self.cfiStructuralComponents = cfiStructuralComponents
        self.notificationsObservable = notificationsObservable
        self.inputObservable = inputObservable
    }

    /// Every declaration left to the runtime's auto-detection, with the
    /// standard four structural CFI components.
    public static let auto = HostDeclarations(
        sensing: .auto,
        deviceClass: .auto,
        maskProfile: .auto,
        cfiStructuralComponents: 4
    )

    public var isEmpty: Bool {
        sensing == nil && deviceClass == nil && maskProfile == nil
            && cfiStructuralComponents == nil && notificationsObservable == nil
            && inputObservable == nil
    }

    /// Top-level runtime config keys. Spread these into the config object.
    public func toJSON() -> [String: Any] {
        var out: [String: Any] = [:]
        if let sensing {
            switch sensing {
            case .auto: out["sensing"] = "auto"
            case .explicit(let p): out["sensing"] = p.toJSON()
            }
        }
        if let deviceClass {
            switch deviceClass {
            case .auto: out["device_class"] = "auto"
            case .explicit(let d): out["device_class"] = d.rawValue
            }
        }
        if let maskProfile {
            switch maskProfile {
            case .auto: out["mask_profile"] = "auto"
            case .explicit(let m): out["mask_profile"] = m.rawValue
            }
        }
        if let n = cfiStructuralComponents { out["cfi_structural_components"] = n }
        if let v = notificationsObservable { out["notifications_observable"] = v }
        if let v = inputObservable { out["input_observable"] = v }
        return out
    }
}

/// Opt-in kinematic heads, enabled through `extra_heads`.
///
/// Enabling one is necessary but not sufficient: the head also needs a
/// body-worn ``AccelPlacement`` before it produces anything.
public enum ExtraHead: String, CaseIterable, Codable, Sendable {
    case movementRegularity = "movement_regularity"
    case posturalState = "postural_state"
    case activityState = "activity_state"
    case locomotionState = "locomotion_state"
}
