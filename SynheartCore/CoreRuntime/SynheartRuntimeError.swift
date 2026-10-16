import Foundation

/// Why the native runtime could not be used.
public enum SynheartRuntimeErrorKind: String, Equatable, Sendable {
    /// No runtime was linked into the app.
    case notInstalled
    /// A library was found but was built for a different CPU architecture.
    case wrongArchitecture
    /// The runtime loaded, but its ABI or version does not fit this SDK.
    case incompatible
    /// The library exists but the loader rejected it, e.g. a damaged file.
    case loadFailed
}

/// The native runtime is unusable or incompatible with this SDK.
///
/// ``Synheart/initialize(userId:config:)`` throws it, with kind
/// ``SynheartRuntimeErrorKind/incompatible``, before the runtime handle is
/// created. Its ``installCommand`` is the fix.
public struct SynheartRuntimeError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    public let kind: SynheartRuntimeErrorKind

    /// One plain sentence naming the versions involved and the fix.
    public let message: String

    /// Linked runtime version, when it reported one.
    public let runtimeVersion: String?

    /// Linked runtime ABI (`MAJOR.MINOR`), when it reported one.
    public let runtimeAbi: String?

    /// ABI this SDK requires (`MAJOR.MINOR`; the runtime must match MAJOR and
    /// be at least this MINOR).
    public let requiredAbi: String

    /// Runtime release to install.
    public let recommendedVersion: String

    /// Exact shell command that installs ``recommendedVersion``.
    public let installCommand: String

    /// Raw diagnostic text, for support. Not meant for end users.
    public let cause: String?

    public init(
        kind: SynheartRuntimeErrorKind,
        message: String,
        runtimeVersion: String? = nil,
        runtimeAbi: String? = nil,
        requiredAbi: String = RuntimeCompat.requiredAbi,
        recommendedVersion: String = RuntimeCompat.writtenAgainst,
        installCommand: String = RuntimeCompat.installCommand,
        cause: String? = nil
    ) {
        self.kind = kind
        self.message = message
        self.runtimeVersion = runtimeVersion
        self.runtimeAbi = runtimeAbi
        self.requiredAbi = requiredAbi
        self.recommendedVersion = recommendedVersion
        self.installCommand = installCommand
        self.cause = cause
    }

    /// A library that links but does not report its build info: not a
    /// Synheart Core runtime, or a build without its C ABI.
    public static func unidentified(cause: String? = nil) -> SynheartRuntimeError {
        SynheartRuntimeError(
            kind: .incompatible,
            message: "The Core runtime library does not report its version, so it is "
                + "not a usable runtime build for SynheartCore. \(RuntimeCompat.fix)",
            cause: cause
        )
    }

    /// A linked runtime that `compat` refused.
    public static func incompatible(_ compat: RuntimeCompatResult) -> SynheartRuntimeError {
        SynheartRuntimeError(
            kind: .incompatible,
            message: compat.message,
            runtimeVersion: compat.version,
            runtimeAbi: compat.abi,
            cause: compat.version.map { v in
                "runtime \(v)" + (compat.abi.map { " abi \($0)" } ?? "")
            }
        )
    }

    public var errorDescription: String? { message }

    public var description: String { "SynheartRuntimeError(\(kind.rawValue)): \(message)" }
}
