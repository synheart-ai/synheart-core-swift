import Foundation

/// Where the accelerometer physically sits, for `synheart_core_set_accel_placement`.
///
/// Enabling a kinematic head via ``SynheartConfig/extraHeads`` is necessary but
/// not sufficient: the four kinematic axes stay withheld until a body-worn mount
/// is declared. ``unknown`` — the default — withholds all of them.
///
/// ## The validated envelope is `pocket` and `waist` only
///
/// ``wrist`` and ``chest`` are body-worn but outside the envelope the kinematic
/// heads were validated against; ``desk`` is not body-worn at all, and the
/// suppression that comes with it exists precisely so desk vibration does not
/// read as physiology-relevant motion.
///
/// ## Placement is dynamic, not a compile-time constant
///
/// There is no hand-held placement, and during exactly the interaction the
/// digital axes measure — typing, scrolling — the device is in the hand. So the
/// kinematic and behavioural axes are largely disjoint in time on a handheld,
/// and a fixed `pocket` declared once at startup is wrong the moment the person
/// picks the device up. Re-declare as the placement actually changes.
public enum AccelPlacement: Int32, CaseIterable, Codable, Sendable {
    case unknown = 0
    case pocket = 1
    case wrist = 2
    case chest = 3
    case desk = 4
    case waist = 5

    /// Discriminant the C ABI expects.
    public var code: Int32 { rawValue }

    /// Whether this placement is inside the validated envelope for the kinematic
    /// heads. `false` for everything but ``pocket`` and ``waist``.
    public var isValidatedEnvelope: Bool {
        self == .pocket || self == .waist
    }
}
