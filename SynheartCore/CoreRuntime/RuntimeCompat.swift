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

    /// The runtime release these bindings were written and tested against.
    /// Bump it in the same change that adopts a new symbol or a moved shape.
    public static let writtenAgainst = "0.31.1"

    /// Oldest runtime the bindings are known to load and behave on. Below this
    /// the SDK refuses to initialise rather than run with entrypoints that no
    /// longer mean what the code assumes. `0.20.0` is the baseline of the
    /// runtime's `SDK-CONTRACT-CHANGES.md`.
    public static let minimum = "0.20.0"

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

    /// Evaluate the linked runtime's `build_info` against ``minimum`` and
    /// ``writtenAgainst``.
    public static func check(buildInfo: [String: Any]?) -> RuntimeCompatResult {
        let raw = (buildInfo?["core_runtime"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let version = raw, !version.isEmpty else {
            return RuntimeCompatResult(
                version: nil,
                status: .unknown,
                message: "[Synheart] runtime version unknown — build_info carried no "
                    + "core_runtime; bindings assume \(writtenAgainst). Expect silent "
                    + "divergence if the linked library is older."
            )
        }
        if compare(version, minimum) < 0 {
            return RuntimeCompatResult(
                version: version,
                status: .tooOld,
                message: "[Synheart] runtime \(version) is below the minimum \(minimum) these "
                    + "bindings support — refusing to initialise. Update the linked "
                    + "runtime with `synheart install runtime`."
            )
        }
        if compare(version, writtenAgainst) < 0 {
            return RuntimeCompatResult(
                version: version,
                status: .older,
                message: "[Synheart] runtime \(version) is older than \(writtenAgainst), which "
                    + "these bindings were written against. Newer symbols fall back "
                    + "(buffered HSI, context fan-in, secure-storage marker …) and "
                    + "behaviour documented for \(writtenAgainst) may not hold. Update "
                    + "the linked runtime with `synheart install runtime`."
            )
        }
        return RuntimeCompatResult(
            version: version,
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
    /// Below ``RuntimeCompat/minimum``; initialisation is refused.
    case tooOld
    /// `build_info` did not report a version.
    case unknown
}

public struct RuntimeCompatResult: Equatable, Sendable {
    public let version: String?
    public let status: RuntimeCompatStatus
    public let message: String

    public var isAcceptable: Bool { status != .tooOld }
}
