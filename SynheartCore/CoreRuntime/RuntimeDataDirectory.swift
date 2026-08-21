import Foundation

/// Resolves and creates the durable directory owned by the native runtime.
enum RuntimeDataDirectory {
    static func prepare(
        using fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) throws -> String {
        guard let applicationSupport = applicationSupportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw SynheartCoreError.notConfigured("Application Support directory is unavailable")
        }

        let directory = applicationSupport
            .appendingPathComponent("SynheartCore", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.path
    }
}
