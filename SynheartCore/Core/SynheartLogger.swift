import Foundation
import os

/// Centralized logging for the Synheart SDK.
///
/// All library-internal logging goes through this class. Consumers can disable
/// SDK logs by setting ``enabled`` to `false`.
public final class SynheartLogger {
    /// When `false`, all log output is suppressed. Defaults to `true`.
    public static var enabled: Bool = true

    private static let subsystem = "ai.synheart.core"
    private static let logger = os.Logger(subsystem: subsystem, category: "SynheartCore")

    /// Log a message. No-op when ``enabled`` is `false`.
    public static func log(_ message: String) {
        guard enabled else { return }
        logger.log("\(message, privacy: .public)")
    }

    private init() {}
}
