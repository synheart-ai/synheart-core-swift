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
        excludeFromBackup(directory)
        return directory.path
    }

    /// Keeps the runtime's data out of iCloud / iTunes backup and device
    /// migration (the flag covers everything inside the directory).
    ///
    /// Everything in it is sealed with keys held in Keychain items that never
    /// leave this device, so a restored copy can never be decrypted. Worse,
    /// it brings back the runtime's `.smk-provisioned-<subject>` markers
    /// without their key, and the runtime then refuses to mint a new storage
    /// master key (`ERR_SECURE_STORAGE_UNAVAILABLE`) on the new device.
    /// Best-effort: a failure is logged and the directory still works.
    static func excludeFromBackup(_ directory: URL) {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try url.setResourceValues(values)
        } catch {
            SynheartLogger.log(
                "[RuntimeDataDirectory] could not exclude \(directory.path) from backup: \(error)"
            )
        }
    }
}
