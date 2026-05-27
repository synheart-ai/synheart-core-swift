// SPDX-License-Identifier: Apache-2.0
//
// Apple Health XML backfill sink — Swift bindings.
//
// Mirror of `synheart-core-flutter/lib/src/backfill/apple_xml_backfill_sink.dart`.
// Bridges the `AppleXmlIngestSink` protocol from `synheart-wear-swift`'s
// `AppleHealthXmlImport` orchestrator to the runtime's backfill SQLite
// ingest via three new C-ABI symbols:
//
//   - synheart_core_backfill_open
//   - synheart_core_backfill_insert_batch
//   - synheart_core_backfill_finalize
//
// We don't take a runtime dep on `synheart-wear-swift` here — apps
// adopt the bridge by writing a small adapter that forwards
// `AppleXmlIngestSink` calls to this sink. Keeps the FFI layer
// independently usable.

import Foundation

/// Result of a single batch insert.
public struct BackfillBatchResult: Equatable {
    public let inserted: Int
    public let skippedAsDuplicate: Int

    public init(inserted: Int, skippedAsDuplicate: Int) {
        self.inserted = inserted
        self.skippedAsDuplicate = skippedAsDuplicate
    }
}

/// Result of a complete import session.
public struct BackfillImportResult: Equatable {
    public let importId: String
    public let totalSamples: Int
    public let inserted: Int
    public let skippedAsDuplicate: Int
    public let durationMs: Int

    public init(
        importId: String,
        totalSamples: Int,
        inserted: Int,
        skippedAsDuplicate: Int,
        durationMs: Int
    ) {
        self.importId = importId
        self.totalSamples = totalSamples
        self.inserted = inserted
        self.skippedAsDuplicate = skippedAsDuplicate
        self.durationMs = durationMs
    }
}

/// All errors emitted by the runtime-backed sink.
public enum BackfillSinkError: Error, Equatable {
    case runtimeUnavailable
    case openFailed(message: String)
    case batchFailed(message: String)
    case finalizeFailed(message: String)
}

/// Bridges runtime FFI calls into the surface the synheart-wear
/// orchestrator expects.
///
/// Usage:
///
///     let sink = AppleXmlBackfillSink(dbPath: backfillURL.path)
///     try sink.open(importId: UUID().uuidString)
///     let r = try sink.insertBatchJson(samplesJson)
///     let final = try sink.finalize()
public final class AppleXmlBackfillSink {

    // MARK: - C aliases

    private typealias OpenFn = @convention(c) (
        UnsafePointer<CChar>?, UnsafePointer<CChar>?
    ) -> Int32
    private typealias InsertBatchFn = @convention(c) (
        UnsafePointer<CChar>?, UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    private typealias FinalizeFn = @convention(c) (
        UnsafePointer<CChar>?
    ) -> UnsafeMutablePointer<CChar>?
    private typealias FreeStringFn = @convention(c) (
        UnsafeMutablePointer<CChar>?
    ) -> Void

    private static func sym<T>(_ name: String) -> T? {
        let lib = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private static let _open:        OpenFn?         = sym("synheart_core_backfill_open")
    private static let _insertBatch: InsertBatchFn?  = sym("synheart_core_backfill_insert_batch")
    private static let _finalize:    FinalizeFn?     = sym("synheart_core_backfill_finalize")
    private static let _freeString:  FreeStringFn?   = sym("synheart_core_free_string")

    // MARK: - State

    public let dbPath: String
    private var activeImportId: String?

    public init(dbPath: String) {
        self.dbPath = dbPath
    }

    /// Whether the loaded runtime exposes the backfill symbols.
    public var isAvailable: Bool {
        Self._open != nil && Self._insertBatch != nil && Self._finalize != nil
    }

    /// Open a new import session. Throws [.openFailed] on duplicate id,
    /// missing symbol, or SQLite error.
    public func open(importId: String) throws {
        guard !importId.isEmpty else {
            throw BackfillSinkError.openFailed(message: "importId must not be empty")
        }
        guard isAvailable else { throw BackfillSinkError.runtimeUnavailable }

        let rc = dbPath.withCString { p in
            importId.withCString { id in
                Self._open?(p, id) ?? -1
            }
        }
        if rc != 0 {
            throw BackfillSinkError.openFailed(
                message: "runtime backfill_open returned \(rc) for importId=\(importId)"
            )
        }
        activeImportId = importId
    }

    /// Insert a batch of samples. `samplesAsJson` must be a JSON array
    /// of `AppleHealthSample`. Returns the inserted/skipped counts as
    /// reported by the runtime.
    public func insertBatchJson(_ samplesAsJson: String) throws -> BackfillBatchResult {
        guard isAvailable else { throw BackfillSinkError.runtimeUnavailable }
        guard let id = activeImportId else {
            throw BackfillSinkError.batchFailed(message: "insertBatch called before open")
        }

        let cstr: UnsafeMutablePointer<CChar>? = id.withCString { idPtr in
            samplesAsJson.withCString { jsonPtr in
                Self._insertBatch?(idPtr, jsonPtr)
            }
        }
        guard let cstr = cstr else {
            throw BackfillSinkError.batchFailed(
                message: "runtime backfill_insert_batch returned NULL"
            )
        }
        defer { Self._freeString?(cstr) }
        let raw = String(cString: cstr)
        guard
            let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let inserted = obj["inserted"] as? Int,
            let skipped = obj["skipped_as_duplicate"] as? Int
        else {
            throw BackfillSinkError.batchFailed(
                message: "could not parse insert_batch response: \(raw)"
            )
        }
        return BackfillBatchResult(inserted: inserted, skippedAsDuplicate: skipped)
    }

    /// Finalize and close. Throws [.finalizeFailed] if no session is
    /// open or the runtime returns NULL.
    public func finalize() throws -> BackfillImportResult {
        guard isAvailable else { throw BackfillSinkError.runtimeUnavailable }
        guard let id = activeImportId else {
            throw BackfillSinkError.finalizeFailed(message: "finalize called before open")
        }

        let cstr: UnsafeMutablePointer<CChar>? = id.withCString { idPtr in
            Self._finalize?(idPtr)
        }
        guard let cstr = cstr else {
            throw BackfillSinkError.finalizeFailed(
                message: "runtime backfill_finalize returned NULL"
            )
        }
        defer { Self._freeString?(cstr) }
        let raw = String(cString: cstr)
        guard
            let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let importId = obj["import_id"] as? String,
            let total = obj["total_samples"] as? Int,
            let inserted = obj["inserted"] as? Int,
            let skipped = obj["skipped_as_duplicate"] as? Int,
            let duration = obj["duration_ms"] as? Int
        else {
            throw BackfillSinkError.finalizeFailed(
                message: "could not parse finalize response: \(raw)"
            )
        }
        activeImportId = nil
        return BackfillImportResult(
            importId: importId,
            totalSamples: total,
            inserted: inserted,
            skippedAsDuplicate: skipped,
            durationMs: duration
        )
    }
}
