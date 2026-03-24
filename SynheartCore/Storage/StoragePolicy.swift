import Foundation

/// Controls what may be persisted based on the current operational mode.
///
/// See RFC-CORE-0003 Section 6.
public protocol StoragePolicy {
    func canPersistArtifact(_ type: String) -> Bool
    func canPersistStream(_ streamType: String) -> Bool
    func canIncludeMetrics() -> Bool
    func canPersistWearableEvent() -> Bool
}

public func storagePolicyForMode(_ mode: SynheartMode) -> StoragePolicy {
    switch mode {
    case .personal: return PersonalPolicy()
    case .insight:  return InsightPolicy()
    case .research: return ResearchPolicy()
    }
}

private struct PersonalPolicy: StoragePolicy {
    func canPersistArtifact(_ type: String) -> Bool {
        type == "hsi_window" || type == "session_summary" ||
        type == "baseline_snapshot" || type == "tombstone"
    }

    func canPersistStream(_ streamType: String) -> Bool {
        streamType == "hsi.snapshot"
    }

    func canIncludeMetrics() -> Bool { false }

    func canPersistWearableEvent() -> Bool { true }
}

private struct InsightPolicy: StoragePolicy {
    func canPersistArtifact(_ type: String) -> Bool {
        type == "hsi_window" || type == "session_summary" ||
        type == "baseline_snapshot" || type == "tombstone"
    }

    func canPersistStream(_ streamType: String) -> Bool {
        streamType == "hsi.snapshot" || streamType == "app.metrics" ||
        streamType == "behavior.events"
    }

    func canIncludeMetrics() -> Bool { true }

    func canPersistWearableEvent() -> Bool { true }
}

private struct ResearchPolicy: StoragePolicy {
    func canPersistArtifact(_ type: String) -> Bool { true }
    func canPersistStream(_ streamType: String) -> Bool { true }
    func canIncludeMetrics() -> Bool { true }
    func canPersistWearableEvent() -> Bool { true }
}
