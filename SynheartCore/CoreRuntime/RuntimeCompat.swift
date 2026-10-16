import Foundation

/// Runtime-version compatibility for the hand-written C ABI bindings.
///
/// The runtime's C surface is additive and stable — a binding written against
/// one version still *links* against a much newer one — so nothing fails loudly
/// when the two drift apart. What moves between versions is semantics, JSON
/// shapes, error-code vocabulary and which symbols a build exports, none of
/// which `dlsym` checks (an absent symbol merely resolves to `nil`). This is
/// the one place the SDK states which runtime its bindings assume and compares
/// it to what actually linked.
public enum RuntimeCompat {

    /// The newest runtime release these bindings were verified against, and the
    /// release every install hint recommends. Bump it when the bindings adopt a
    /// new symbol or a moved shape, or once they are verified on a newer
    /// release.
    public static let writtenAgainst = "0.38.0"

    /// Oldest runtime the bindings are known to load and behave on. Below this
    /// the SDK refuses to initialise rather than run with entrypoints that no
    /// longer mean what the code assumes. `0.20.0` is the baseline of the
    /// runtime's `SDK-CONTRACT-CHANGES.md`.
    public static let minimum = "0.20.0"

    /// The C ABI this SDK requires, as `MAJOR.MINOR`. The runtime bumps MAJOR on
    /// any removal, rename or signature change and MINOR on additions only, so a
    /// runtime is compatible when its MAJOR equals ``requiredAbiMajor`` and its
    /// MINOR is at least ``requiredAbiMinor``. This, not the release version, is
    /// the contract; the version checks only grade runtimes that satisfy it.
    public static let requiredAbi = "1.0"
    public static let requiredAbiMajor = 1
    public static let requiredAbiMinor = 0

    /// Newest ABI major the bindings also accept. ABI 2.0 only removed symbols
    /// these bindings never call, and its one addition
    /// (`synheart_core_last_error_json`) is looked up as optional, so runtimes on
    /// either major load. Raise it only after checking a new major's removals
    /// against the bindings.
    public static let maxAbiMajor = 2

    /// The accepted ABI range, for messages.
    public static var abiRange: String {
        maxAbiMajor == requiredAbiMajor
            ? "\(requiredAbiMajor).x"
            : "\(requiredAbi) to \(maxAbiMajor).x"
    }

    /// Installs the release the bindings were written against.
    public static let installCommand = "synheart install runtime --version \(writtenAgainst)"

    static var fix: String { "Install runtime \(writtenAgainst): \(installCommand)" }

    /// Whether a runtime reporting ABI `major.minor` can be used.
    public static func acceptsAbi(major: Int, minor: Int) -> Bool {
        if major < requiredAbiMajor || major > maxAbiMajor { return false }
        return major > requiredAbiMajor || minor >= requiredAbiMinor
    }

    /// Parse `MAJOR.MINOR` (extra components ignored); nil if malformed.
    public static func parseAbi(_ abi: String) -> (major: Int, minor: Int)? {
        let parts = abi.trimmingCharacters(in: .whitespaces)
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1].prefix { $0.isNumber })
        else { return nil }
        return (major, minor)
    }

    /// Compare two dotted numeric versions (`0.31.1`). Non-numeric suffixes are
    /// ignored; a missing component reads as `0`. Negative when `a < b`.
    public static func compare(_ a: String, _ b: String) -> Int {
        func parse(_ v: String) -> [Int] {
            v.split(separator: ".").map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
        }
        let pa = parse(a), pb = parse(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// Evaluate the linked runtime's `build_info`: its ABI against
    /// ``requiredAbi`` when it reports one (runtime 0.33.0+), otherwise its
    /// version against ``minimum``; then against ``writtenAgainst`` for status.
    public static func check(buildInfo: [String: Any]?) -> RuntimeCompatResult {
        let raw = (buildInfo?["core_runtime"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let version = (raw?.isEmpty ?? true) ? nil : raw
        let rawAbi = buildInfo?["abi"] as? String
        let parsedAbi = rawAbi.flatMap(parseAbi)
        let abi = parsedAbi == nil ? nil : rawAbi

        if let parsedAbi, !acceptsAbi(major: parsedAbi.major, minor: parsedAbi.minor) {
            return RuntimeCompatResult(
                version: version,
                abi: abi,
                status: .incompatibleAbi,
                message: "Core runtime \(version ?? "(unknown version)") (ABI \(abi ?? "")) is "
                    + "incompatible with SynheartCore \(SynheartCoreVersion.current) (needs ABI "
                    + "\(abiRange)). \(fix)"
            )
        }
        guard let version else {
            return RuntimeCompatResult(
                version: nil,
                abi: abi,
                status: .unknown,
                message: "[Synheart] runtime version unknown — build_info carried no "
                    + "core_runtime; bindings assume \(writtenAgainst). Expect silent "
                    + "divergence if the linked library is older."
            )
        }
        if compare(version, minimum) < 0 {
            return RuntimeCompatResult(
                version: version,
                abi: abi,
                status: .tooOld,
                message: "Core runtime \(version) is incompatible with SynheartCore "
                    + "\(SynheartCoreVersion.current) (needs runtime \(minimum) or newer). \(fix)"
            )
        }
        if compare(version, writtenAgainst) < 0 {
            return RuntimeCompatResult(
                version: version,
                abi: abi,
                status: .older,
                message: "[Synheart] runtime \(version) is older than \(writtenAgainst), which "
                    + "these bindings were verified against. Symbols added since then "
                    + "fall back, and behaviour documented for \(writtenAgainst) may not "
                    + "hold. Update the linked runtime with `synheart install runtime`."
            )
        }
        return RuntimeCompatResult(
            version: version,
            abi: abi,
            status: .ok,
            message: "[Synheart] runtime \(version) (bindings: \(writtenAgainst))"
        )
    }
}

public enum RuntimeCompatStatus: Equatable, Sendable {
    /// At or above ``RuntimeCompat/writtenAgainst``.
    case ok
    /// Links and works, but predates the version the bindings assume.
    case older
    /// Below ``RuntimeCompat/minimum`` on a runtime that reports no ABI;
    /// initialisation is refused.
    case tooOld
    /// The runtime's ABI is outside ``RuntimeCompat/abiRange``; initialisation
    /// is refused.
    case incompatibleAbi
    /// `build_info` did not report a version.
    case unknown
}

public struct RuntimeCompatResult: Equatable, Sendable {
    public let version: String?
    /// The runtime's ABI (`MAJOR.MINOR`); nil for runtimes before 0.33.0.
    public let abi: String?
    public let status: RuntimeCompatStatus
    public let message: String

    public init(version: String?, abi: String? = nil, status: RuntimeCompatStatus, message: String) {
        self.version = version
        self.abi = abi
        self.status = status
        self.message = message
    }

    public var isAcceptable: Bool { status != .tooOld && status != .incompatibleAbi }
}
