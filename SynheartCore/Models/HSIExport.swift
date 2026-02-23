import Foundation
import CryptoKit

/// Minimal access context used to produce explicit null-with-reason readings.
///
/// NOTE: HSI 1.0 schema restricts `meta` to primitive values only, so this is
/// flattened into primitive meta fields and `notes` strings on individual readings.
public struct HSIExportAccessContext {
    public let capabilityHsi: String
    public let capabilityCloud: String
    public let consentBiosignals: Bool
    public let consentPhoneContext: Bool
    public let consentBehavior: Bool
    public let consentCloudUpload: Bool
    public let consentEmotionEstimation: Bool
    public let consentFocusEstimation: Bool

    public init(
        capabilityHsi: String,
        capabilityCloud: String,
        consentBiosignals: Bool,
        consentPhoneContext: Bool,
        consentBehavior: Bool,
        consentCloudUpload: Bool,
        consentEmotionEstimation: Bool,
        consentFocusEstimation: Bool
    ) {
        self.capabilityHsi = capabilityHsi
        self.capabilityCloud = capabilityCloud
        self.consentBiosignals = consentBiosignals
        self.consentPhoneContext = consentPhoneContext
        self.consentBehavior = consentBehavior
        self.consentCloudUpload = consentCloudUpload
        self.consentEmotionEstimation = consentEmotionEstimation
        self.consentFocusEstimation = consentFocusEstimation
    }
}

// MARK: - HSI Snapshot

/// HSI Snapshot — Versioned JSON snapshot derived from HSV.
///
/// This is the serializable, transport-safe, cloud-ingestable representation
/// of human state. It is the ONLY type that may be:
/// - Exposed to external consumers
/// - Transmitted to cloud
/// - Serialized for transport
///
/// HSI 1.0 is the canonical JSON wire format for interoperability.
/// See: synheart/hsi/schema/hsi-1.0.schema.json
public struct HSISnapshot {
    /// The complete HSI 1.0 payload as a JSON-compatible dictionary
    public let payload: [String: Any]

    /// HSI version (always "1.0")
    public var hsiVersion: String {
        payload["hsi_version"] as? String ?? "1.0"
    }

    /// When the human state was observed
    public var observedAtUtc: String? {
        payload["observed_at_utc"] as? String
    }

    /// When this payload was computed
    public var computedAtUtc: String? {
        payload["computed_at_utc"] as? String
    }

    /// Axes readings (affect, engagement, behavior)
    public var axes: [String: Any]? {
        payload["axes"] as? [String: Any]
    }

    /// Embedding vectors
    public var embeddings: [[String: Any]]? {
        payload["embeddings"] as? [[String: Any]]
    }

    /// Privacy assertions
    public var privacy: [String: Any]? {
        payload["privacy"] as? [String: Any]
    }

    /// Additional metadata
    public var meta: [String: Any]? {
        payload["meta"] as? [String: Any]
    }
}

// MARK: - FluxBridge

/// FluxBridge — Single source of truth for HSI generation.
///
/// Aligned with synheart-flux:
/// - Accepts `ExportPolicy` to control domain filtering and confidence thresholds
/// - Exports physiology domain readings from `PhysiologyState` with per-axis confidence
/// - Uses `StateQuality.overallConfidence` for behavioral/context readings
///
/// Converts internal HSV (Human State Vector) to HSI (Human State Interface)
/// snapshots. This is the ONLY path through which HSI may be generated.
///
/// Per AGENTS.md invariant: "HSI is generated only in the runtime pipeline."
public final class FluxBridge {

    /// Export HSV as an HSI 1.0 snapshot.
    ///
    /// - Parameters:
    ///   - hsv: Internal human state vector (non-serializable)
    ///   - producerName: Name of the producer (e.g., "Synheart Core SDK")
    ///   - producerVersion: Version of the producer (e.g., "1.0.0")
    ///   - instanceId: Producer instance identifier (UUID string)
    ///   - windowLabel: Canonical label for the time window (e.g., "micro", "short")
    ///   - windowDurationSeconds: Duration of the window in seconds
    ///   - computedAtUtc: Processing-time for this payload (defaults to now)
    ///   - access: Optional access context for consent/capability gating
    ///   - policy: Controls which domains/axes appear in the export (defaults to all)
    /// - Returns: Schema-valid HSI 1.0 snapshot
    public static func export(
        hsv: HumanStateVector,
        producerName: String,
        producerVersion: String,
        instanceId: String,
        windowLabel: String = "micro",
        windowDurationSeconds: Int = 30,
        computedAtUtc: Date = Date(),
        access: HSIExportAccessContext? = nil,
        policy: ExportPolicy = .default
    ) -> HSISnapshot {
        let observedAtUtc = hsv.meta.timestamp
        let windowEnd = observedAtUtc
        let windowStart = observedAtUtc.addingTimeInterval(-Double(windowDurationSeconds))
        let windowId = "w1"

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let embeddingVectors = policy.includeEmbedding
            ? exportableEmbedding(hsv: hsv, access: access)
            : nil

        var hsi: [String: Any] = [:]

        // Required top-level fields
        hsi["hsi_version"] = "1.0"
        hsi["observed_at_utc"] = iso.string(from: observedAtUtc)
        hsi["computed_at_utc"] = iso.string(from: computedAtUtc)

        hsi["producer"] = [
            "name": producerName,
            "version": producerVersion,
            "instance_id": instanceId
        ]

        hsi["window_ids"] = [windowId]

        hsi["windows"] = [
            windowId: [
                "start": iso.string(from: windowStart),
                "end": iso.string(from: windowEnd),
                "label": windowLabel
            ] as [String: Any]
        ]

        // Optional axes (HSI schema: affect/engagement/behavior domains only)
        let axes = buildAxes(hsv: hsv, windowId: windowId, access: access, policy: policy)
        if !axes.isEmpty {
            hsi["axes"] = axes
        }

        // Optional embeddings (gated by ExportPolicy)
        if let vectors = embeddingVectors {
            let vectorHash = sha256Hex(vectors.map { String($0) }.joined(separator: ","))
            hsi["embeddings"] = [[
                "window_id": windowId,
                "dimension": vectors.count,
                "encoding": "float32",
                "confidence": 0.85,
                "vector": vectors,
                "vector_hash": "sha256:\(vectorHash)",
                "model": "hsi-fusion-v1"
            ] as [String: Any]]
        }

        // Required privacy block
        hsi["privacy"] = [
            "contains_pii": false,
            "raw_biosignals_allowed": false,
            "derived_metrics_allowed": true,
            "embedding_allowed": embeddingVectors != nil,
            "consent": "explicit"
        ] as [String: Any]

        // Optional meta (HSI schema allows only primitive values)
        if policy.includeMeta {
            var metaDict: [String: Any] = [
                "sdk_version": producerVersion,
                "session_id": hsv.meta.sessionId,
                "platform": hsv.meta.device.platform,
                "os_version": hsv.meta.device.osVersion,
                "modality_count": hsv.stateQuality.modalityCount,
                "overall_confidence": hsv.stateQuality.overallConfidence
            ]

            if !hsv.provenance.vendors.isEmpty {
                metaDict["vendors"] = hsv.provenance.vendors.joined(separator: ",")
            }

            if let access = access {
                metaDict["capability_hsi"] = access.capabilityHsi.lowercased()
                metaDict["capability_cloud"] = access.capabilityCloud.lowercased()
                metaDict["consent_biosignals"] = access.consentBiosignals
                metaDict["consent_phone_context"] = access.consentPhoneContext
                metaDict["consent_behavior"] = access.consentBehavior
                metaDict["consent_emotion"] = access.consentEmotionEstimation
                metaDict["consent_focus"] = access.consentFocusEstimation
                metaDict["consent_cloud_upload"] = access.consentCloudUpload
            }

            hsi["meta"] = metaDict
        }

        return HSISnapshot(payload: hsi)
    }
}

// MARK: - Private Helpers

private func exportableEmbedding(hsv: HumanStateVector, access: HSIExportAccessContext?) -> [Float]? {
    guard let embedding = hsv.hsiEmbedding, !embedding.isEmpty else { return nil }

    // Best-effort export if no access context is provided.
    guard let access = access else {
        return l2Normalize(embedding)
    }

    // Access-control gating: capability AND consent.
    if access.capabilityHsi.lowercased() == "none" { return nil }
    if !(access.consentBiosignals || access.consentPhoneContext || access.consentBehavior) { return nil }

    // Core tier requires normalized embeddings.
    if access.capabilityHsi.lowercased() == "core" {
        return l2Normalize(embedding)
    }
    return embedding
}

private func buildAxes(hsv: HumanStateVector, windowId: String, access: HSIExportAccessContext?, policy: ExportPolicy = .default) -> [String: Any] {
    var affectReadings: [[String: Any]] = []
    var engagementReadings: [[String: Any]] = []
    var behaviorReadings: [[String: Any]] = []

    // Physiology-derived readings (from PhysiologyState) — synheart-flux
    if policy.includePhysiology {
        func addPhysioReading(_ axis: String, _ value: HsvAxisValue, direction: String = "higher_is_more") {
            if value.isPresent, value.confidence >= policy.minConfidence {
                affectReadings.append(axisReading(
                    axis: axis,
                    score: Double(value.score!),
                    windowId: windowId,
                    confidence: Double(value.confidence),
                    direction: direction
                ))
            }
        }

        addPhysioReading("sleep_efficiency", hsv.physiology.sleepEfficiency)
        addPhysioReading("recovery_score", hsv.physiology.recoveryScore)
        addPhysioReading("hrv_deviation", hsv.physiology.hrvDeviation, direction: "bidirectional")
        addPhysioReading("respiratory_rate", hsv.physiology.respiratoryRate)
        addPhysioReading("spo2", hsv.physiology.spo2)
        addPhysioReading("strain", hsv.physiology.strain)
    }

    let hsiDenied = access?.capabilityHsi.lowercased() == "none"

    // Emotion-derived axes (require interpretation consent + biosignals consent)
    let emotionAllowed = access == nil || (
        !hsiDenied && access!.consentEmotionEstimation && access!.consentBiosignals
    )

    affectReadings.append(axisReading(
        axis: "stress",
        score: emotionAllowed ? hsv.emotion.map { Double($0.stress) } : nil,
        windowId: windowId,
        direction: "higher_is_more",
        notes: emotionAllowed ? nil : denialNotes(
            reason: hsiDenied ? "capability_insufficient" : "consent_denied",
            dependsOn: "emotionEstimation+biosignals"
        )
    ))
    affectReadings.append(axisReading(
        axis: "calm",
        score: emotionAllowed ? hsv.emotion.map { Double($0.calm) } : nil,
        windowId: windowId,
        direction: "higher_is_more",
        notes: emotionAllowed ? nil : denialNotes(
            reason: hsiDenied ? "capability_insufficient" : "consent_denied",
            dependsOn: "emotionEstimation+biosignals"
        )
    ))
    affectReadings.append(axisReading(
        axis: "arousal",
        score: emotionAllowed ? hsv.emotion.map { Double($0.activation) } : nil,
        windowId: windowId,
        direction: "higher_is_more",
        notes: emotionAllowed ? nil : denialNotes(
            reason: hsiDenied ? "capability_insufficient" : "consent_denied",
            dependsOn: "emotionEstimation+biosignals"
        )
    ))
    affectReadings.append(axisReading(
        axis: "valence",
        score: emotionAllowed ? hsv.emotion.map { min(1.0, max(0.0, Double(($0.valence + 1.0) / 2.0))) } : nil,
        windowId: windowId,
        direction: "bidirectional",
        notes: emotionAllowed ? nil : denialNotes(
            reason: hsiDenied ? "capability_insufficient" : "consent_denied",
            dependsOn: "emotionEstimation+biosignals"
        )
    ))

    // Focus-derived axes (require interpretation consent + behavior consent)
    let focusAllowed = access == nil || (
        !hsiDenied && access!.consentFocusEstimation && access!.consentBehavior
    )

    engagementReadings.append(axisReading(
        axis: "focus_score",
        score: focusAllowed ? hsv.focus.map { Double($0.score) } : nil,
        windowId: windowId,
        notes: focusAllowed ? nil : denialNotes(
            reason: hsiDenied ? "capability_insufficient" : "consent_denied",
            dependsOn: "focusEstimation+behavior"
        )
    ))
    engagementReadings.append(axisReading(
        axis: "cognitive_load",
        score: focusAllowed ? hsv.focus.map { Double($0.cognitiveLoad) } : nil,
        windowId: windowId,
        notes: focusAllowed ? nil : denialNotes(
            reason: hsiDenied ? "capability_insufficient" : "consent_denied",
            dependsOn: "focusEstimation+behavior"
        )
    ))
    engagementReadings.append(axisReading(
        axis: "clarity",
        score: focusAllowed ? hsv.focus.map { Double($0.clarity) } : nil,
        windowId: windowId,
        notes: focusAllowed ? nil : denialNotes(
            reason: hsiDenied ? "capability_insufficient" : "consent_denied",
            dependsOn: "focusEstimation+behavior"
        )
    ))
    engagementReadings.append(axisReading(
        axis: "distraction",
        score: focusAllowed ? hsv.focus.map { Double($0.distraction) } : nil,
        windowId: windowId,
        notes: focusAllowed ? nil : denialNotes(
            reason: hsiDenied ? "capability_insufficient" : "consent_denied",
            dependsOn: "focusEstimation+behavior"
        )
    ))

    // Behavior axes (require behavior consent)
    let behaviorAllowed = access == nil || (!hsiDenied && access!.consentBehavior)

    behaviorReadings.append(axisReading(
        axis: "interaction_intensity",
        score: behaviorAllowed ? hsv.behavior?.interactionIntensity.map { Double($0) } : nil,
        windowId: windowId,
        notes: behaviorAllowed ? nil : denialNotes(
            reason: hsiDenied ? "capability_insufficient" : "consent_denied",
            dependsOn: "behavior"
        )
    ))

    // Build result (keep domains even if scores are null — explicit null readings are desired)
    var result: [String: Any] = [:]
    if !affectReadings.isEmpty {
        result["affect"] = ["readings": affectReadings]
    }
    if !engagementReadings.isEmpty {
        result["engagement"] = ["readings": engagementReadings]
    }
    if !behaviorReadings.isEmpty {
        result["behavior"] = ["readings": behaviorReadings]
    }
    return result
}

private func axisReading(
    axis: String,
    score: Double?,
    windowId: String,
    confidence: Double = 0.8,
    direction: String = "higher_is_more",
    notes: String? = nil
) -> [String: Any] {
    var reading: [String: Any] = [
        "axis": axis,
        "confidence": min(1.0, max(0.0, confidence)),
        "window_id": windowId,
        "direction": direction
    ]
    if let score = score {
        reading["score"] = min(1.0, max(0.0, score))
    } else {
        reading["score"] = NSNull()
    }
    if let notes = notes {
        reading["notes"] = notes
    }
    return reading
}

private func denialNotes(reason: String, dependsOn: String) -> String {
    return #"{"reason":"\#(reason)","depends_on":"\#(dependsOn)"}"#
}

private func l2Normalize(_ values: [Float]) -> [Float] {
    let sumSq = values.reduce(0.0) { $0 + Double($1) * Double($1) }
    guard sumSq > 0.0 else { return values }
    let norm = sumSq.squareRoot()
    return values.map { Float(Double($0) / norm) }
}

private func sha256Hex(_ input: String) -> String {
    let data = Data(input.utf8)
    let hash = SHA256.hash(data: data)
    return hash.map { String(format: "%02x", $0) }.joined()
}
