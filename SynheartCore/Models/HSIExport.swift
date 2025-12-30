import Foundation

/// HSI 1.0 Export Extension
///
/// Converts internal HSV (Human State Vector) to HSI 1.0 canonical format.
///
/// HSI 1.0 is the language-agnostic JSON wire format for interoperability.
extension HumanStateVector {
    /// Convert HSV to HSI 1.0 format
    ///
    /// - Parameters:
    ///   - producerName: Name of the producer (e.g., "Synheart Core SDK")
    ///   - producerVersion: Version of the producer (e.g., "1.0.0")
    ///   - instanceId: Instance/device identifier
    /// - Returns: Dictionary representing HSI 1.0 payload
    public func toHSI10(
        producerName: String,
        producerVersion: String,
        instanceId: String
    ) -> [String: Any] {
        var hsi: [String: Any] = [:]

        // HSI 1.0 header
        hsi["hsi_version"] = "1.0"
        hsi["timestamp"] = Int(meta.timestamp.timeIntervalSince1970)
        hsi["window_type"] = "micro" // Default to micro, can be customized

        // Producer info
        hsi["producer"] = [
            "name": producerName,
            "version": producerVersion,
            "instance_id": instanceId
        ]

        // Subject info
        hsi["subject"] = [
            "subject_type": "pseudonymous_user",
            "subject_id": "anon_\(String(instanceId.prefix(8)))"
        ]

        // Privacy guarantees
        hsi["privacy"] = [
            "contains_pii": false,
            "derived_only": true,
            "aggregation_window_sec": 30
        ]

        // Device info
        hsi["device"] = [
            "platform": meta.device.platform,
            "os_version": meta.device.osVersion,
            "device_model": meta.device.deviceModel
        ]

        // State data
        var state: [String: Any] = [:]

        // Biosignals
        if let hr = heartRate {
            state["heart_rate_bpm"] = hr
        }
        if let hrv = heartRateVariability {
            state["hrv_rmssd_ms"] = hrv
        }
        if let rmssd = rmssd {
            state["hrv_rmssd_ms"] = rmssd
        }
        if let sdnn = sdnn {
            state["hrv_sdnn_ms"] = sdnn
        }

        // Behavior metrics
        if let behavior = behavior {
            var behaviorDict: [String: Any] = [:]
            if let typingRate = behavior.typingRate {
                behaviorDict["typing_rate"] = typingRate
            }
            if let scrollingRate = behavior.scrollingRate {
                behaviorDict["scrolling_rate"] = scrollingRate
            }
            if let appSwitchRate = behavior.appSwitchRate {
                behaviorDict["app_switch_rate"] = appSwitchRate
            }
            if let interactionIntensity = behavior.interactionIntensity {
                behaviorDict["interaction_intensity"] = interactionIntensity
            }
            if !behaviorDict.isEmpty {
                state["behavior"] = behaviorDict
            }
        }

        // Context
        if let context = context {
            var contextDict: [String: Any] = [:]

            contextDict["conversation"] = [
                "is_in_conversation": context.conversation.isInConversation,
                "conversation_duration": context.conversation.conversationDuration as Any,
                "last_interaction_time": context.conversation.lastInteractionTime?.timeIntervalSince1970 as Any
            ]

            contextDict["device_state"] = [
                "battery_level": context.device.batteryLevel as Any,
                "is_charging": context.device.isCharging,
                "screen_on": context.device.isScreenOn,
                "network_type": context.device.networkType as Any
            ]

            contextDict["patterns"] = [
                "time_of_day": context.patterns.timeOfDay,
                "day_of_week": context.patterns.dayOfWeek,
                "activity_pattern": context.patterns.activityPattern as Any
            ]

            state["context"] = contextDict
        }

        // Emotion state (if available)
        if let emotion = emotion {
            state["emotion"] = [
                "stress": emotion.stress,
                "calm": emotion.calm,
                "engagement": emotion.engagement,
                "activation": emotion.activation,
                "valence": emotion.valence
            ]
        }

        // Focus state (if available)
        if let focus = focus {
            state["focus"] = [
                "score": focus.score,
                "cognitive_load": focus.cognitiveLoad,
                "clarity": focus.clarity,
                "distraction": focus.distraction
            ]
        }

        // Embedding (if available)
        if let embedding = hsiEmbedding, !embedding.isEmpty {
            state["embedding"] = embedding
        }

        hsi["state"] = state

        // Metadata
        hsi["meta"] = [
            "session_id": meta.sessionId
        ]

        return hsi
    }
}
