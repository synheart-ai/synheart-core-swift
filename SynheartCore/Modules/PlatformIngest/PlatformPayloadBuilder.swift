import Foundation

/// Builds platform ingestion payloads from SDK internal data.
///
/// Aggregates raw wear samples, behavior events, and phone context
/// into the structured format expected by the platform ingestion API.
public enum PlatformPayloadBuilder {

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func dateToIso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func msToIso(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        return dateToIso(date)
    }

    // MARK: - Metadata payload

    /// Build a metadata payload from SDK config and user-provided data.
    ///
    /// `userInfo` contains user-specific fields (birthdate, gender, etc.)
    /// that are not part of `SynheartConfig`.
    public static func buildMetadata(
        config: SynheartConfig,
        deviceId: String,
        platform: String,
        osVersion: String,
        userInfo: [String: Any?]? = nil,
        deviceExtra: [String: Any?]? = nil
    ) -> [String: Any?] {
        let now = dateToIso(Date())

        return [
            "app": [
                "created_at": now,
                "app_id": config.appId,
                "app_name": config.appName,
                "app_version": config.appVersion,
                "category": config.category,
                "developer": config.developer,
                "extra_data": config.additionalAppMetadata
            ] as [String: Any],
            "user": [
                "user_id": config.subjectId,
                "birthdate": (userInfo?["birthdate"] as? String) ?? "",
                "gender": (userInfo?["gender"] as? String) ?? "",
                "blood_type": userInfo?["blood_type"] as Any?,
                "skin_type": userInfo?["skin_type"] as Any?,
                "race": userInfo?["race"] as Any?,
                "extra_data": (userInfo?["extra_data"] ?? [String: Any]()) as Any
            ] as [String: Any?],
            "devices": [
                [
                    "created_at": now,
                    "device": [
                        "device_id": deviceId,
                        "device_type": (userInfo?["device_type"] as? String) ?? "Phone",
                        "device_model": (userInfo?["device_model"] as? String) ?? "",
                        "platform": platform,
                        "device_os_version": osVersion,
                        "extra_data": (deviceExtra ?? [String: Any?]()) as Any
                    ] as [String: Any]
                ] as [String: Any]
            ] as [[String: Any]]
        ]
    }

    // MARK: - Session payload

    /// Build a session payload from SDK internal data collected during a session.
    public static func buildSession(
        sessionId: String,
        deviceId: String,
        appId: String,
        userId: String,
        startedAtMs: Int64,
        endedAtMs: Int64,
        dataOnCloud: Bool,
        cohortId: String? = nil,
        extraData: [String: Any?]? = nil,
        failures: [[String: Any?]]? = nil,
        wearSamples: [WearSample],
        behaviorEvents: [BehaviorEvent],
        phoneDataPoints: [PhoneDataPoint],
        insightData: [String: Any?]? = nil,
        childWindows: [[String: Any?]]? = nil,
        previousSessionEndMs: Int64? = nil
    ) -> [String: Any?] {
        let startedAt = msToIso(startedAtMs)
        let endedAt = msToIso(endedAtMs)
        let durationMs = endedAtMs - startedAtMs

        var sessionMetadata: [String: Any?] = [
            "device_id": deviceId,
            "app_id": appId,
            "user_id": userId,
            "started_at": startedAt,
            "ended_at": endedAt,
            "data_on_cloud": dataOnCloud
        ]
        if let cohortId = cohortId { sessionMetadata["cohort_id"] = cohortId }
        if let extraData = extraData { sessionMetadata["extra_data"] = extraData }

        return [
            "id": sessionId,
            "session_metadata": sessionMetadata,
            "session_failure": failures ?? [[String: Any?]](),
            "session_window": [
                buildWindowNode(
                    windowId: sessionId,
                    parentId: nil,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    durationMs: durationMs,
                    wearSamples: wearSamples,
                    behaviorEvents: behaviorEvents,
                    phoneDataPoints: phoneDataPoints,
                    insightData: insightData,
                    children: childWindows ?? [],
                    previousSessionEndMs: previousSessionEndMs
                )
            ]
        ]
    }

    // MARK: - Window node builder

    private static func buildWindowNode(
        windowId: String,
        parentId: String?,
        startedAt: String,
        endedAt: String,
        durationMs: Int64,
        wearSamples: [WearSample],
        behaviorEvents: [BehaviorEvent],
        phoneDataPoints: [PhoneDataPoint],
        insightData: [String: Any?]? = nil,
        children: [[String: Any?]] = [],
        previousSessionEndMs: Int64? = nil
    ) -> [String: Any?] {
        return [
            "id": windowId,
            "parent_id": parentId,
            "window_metadata": [
                "started_at": startedAt,
                "ended_at": endedAt,
                "duration_ms": durationMs
            ] as [String: Any],
            "window_data": [
                "state_data": [
                    "wear_data": aggregateWearData(samples: wearSamples),
                    "behavior_data": aggregateBehaviorData(
                        events: behaviorEvents,
                        phonePoints: phoneDataPoints,
                        durationMs: durationMs,
                        previousSessionEndMs: previousSessionEndMs
                    )
                ] as [String: Any?],
                "insight_data": (insightData ?? [String: Any]()) as Any
            ] as [String: Any],
            "children": children
        ]
    }

    // MARK: - Wear data aggregation

    private static func aggregateWearData(samples: [WearSample]) -> [String: Any?] {
        if samples.isEmpty {
            return [
                "has_wear_data": false,
                "hr_mean": nil,
                "hrv_rmssd_mean": nil
            ]
        }

        let hrs = samples.compactMap { $0.hr }
        let hrvs = samples.compactMap { $0.hrvRmssd }

        let hrMean: Double? = hrs.isEmpty ? nil : hrs.reduce(0, +) / Double(hrs.count)
        let hrvMean: Double? = hrvs.isEmpty ? nil : hrvs.reduce(0, +) / Double(hrvs.count)
        var result: [String: Any?] = [
            "has_wear_data": true,
            "hr_mean": hrMean,
            "hrv_rmssd_mean": hrvMean
        ]
        if !hrs.isEmpty {
            result["hr_min"] = hrs.min()
            result["hr_max"] = hrs.max()
        }
        return result
    }

    // MARK: - Behavior data aggregation

    private static func aggregateBehaviorData(
        events: [BehaviorEvent],
        phonePoints: [PhoneDataPoint],
        durationMs: Int64,
        previousSessionEndMs: Int64? = nil
    ) -> [String: Any?] {
        let durationSec = Double(durationMs) / 1000.0
        if durationSec <= 0 { return zeroBehaviorData() }

        // Count event types
        var tapCount = 0
        var scrollCount = 0
        var keyDownCount = 0
        var appSwitchCount = 0
        var notifReceived = 0
        var notifOpened = 0

        var keyDownTimestamps = [Int64]()

        for e in events {
            switch e.type {
            case .tap:
                tapCount += 1
            case .scroll:
                scrollCount += 1
            case .keyDown:
                keyDownCount += 1
                keyDownTimestamps.append(Int64(e.timestamp.timeIntervalSince1970 * 1000))
            case .keyUp:
                break // counted but not used
            case .appSwitch:
                appSwitchCount += 1
            case .notificationReceived:
                notifReceived += 1
            case .notificationOpened:
                notifOpened += 1
            }
        }

        let totalEvents = events.count
        let notifIgnored = notifReceived - notifOpened
        let notifIgnoreRate = notifReceived > 0 ? Double(notifIgnored) / Double(notifReceived) : 0.0

        // Phone context aggregation
        let motionPoints = phonePoints.filter { $0.motionLevel != nil }
        let screenPoints = phonePoints.filter { $0.screenOn != nil }
        let appSwitchPoints = phonePoints.filter { $0.appSwitch == true }
        let notifPoints = phonePoints.filter { $0.notification == true }

        // Typing session analysis
        let typingAnalysis = analyzeTypingSessions(keyTimestamps: keyDownTimestamps, durationSec: durationSec)

        // Compute behavioral metrics
        let interactionIntensity = totalEvents > 0
            ? min(max(Double(totalEvents) / durationSec, 0.0), 1.0) : 0.0

        let taskSwitchRate = Double(appSwitchCount) / durationSec

        let idleRatio = computeIdleRatio(events: events, durationMs: durationMs)
        let activeTime = durationSec * (1.0 - idleRatio)
        let burstiness = computeBurstiness(events: events, durationMs: durationMs)

        let notifLoad = Double(notifReceived) / max(durationSec / 60.0, 1.0)
        let normalizedNotifLoad = min(max(notifLoad / 10.0, 0.0), 1.0)

        let distractionScore = computeDistractionScore(
            appSwitchCount: appSwitchCount,
            notifIgnored: notifIgnored,
            notifReceived: notifReceived,
            scrollCount: scrollCount,
            idleRatio: idleRatio
        )
        let focusHint = min(max(1.0 - distractionScore, 0.0), 1.0)

        let deepFocusBlocks = detectDeepFocusBlocks(events: events, durationMs: durationMs)

        // Session spacing
        var sessionSpacing = 0
        if let previousEnd = previousSessionEndMs, !events.isEmpty {
            let sessionStartMs = Int64(events.first!.timestamp.timeIntervalSince1970 * 1000)
            if sessionStartMs > 0 {
                sessionSpacing = max(0, Int((sessionStartMs - previousEnd) / 1000))
            }
        }

        let microSession = durationMs < 30000

        let scrollJitterRate = scrollCount > 0
            ? min(max(Double(scrollCount) / Double(max(totalEvents, 1)), 0.0), 1.0) : 0.0

        let correctionKeyCount = typingAnalysis["correction_key_count"] as! Int

        return [
            "micro_session": microSession,
            "session_spacing": sessionSpacing,
            "motion_state": buildMotionState(motionPoints: motionPoints),
            "device_context": buildDeviceContext(screenPoints: screenPoints),
            "activity_summary": [
                "total_events": totalEvents,
                "app_switch_count": appSwitchCount + appSwitchPoints.count
            ] as [String: Any],
            "notification_summary": [
                "notification_count": notifReceived + notifPoints.count,
                "notification_ignored": notifIgnored,
                "notification_ignore_rate": notifIgnoreRate,
                "notification_clustering_index": computeNotifClustering(events: events, durationMs: durationMs),
                "call_count": 0,
                "call_ignored": 0
            ] as [String: Any],
            "system_state": [
                "internet_state": true,
                "do_not_disturb": false,
                "charging": false
            ] as [String: Any],
            "typing_session_summary": typingAnalysis,
            "behavioral_metrics": [
                "correction_rate": correctionKeyCount > 0
                    ? Double(correctionKeyCount) / Double(max(keyDownCount, 1)) : 0.0,
                "editing_friction": (typingAnalysis["clipboard_activity_rate"] as! Double),
                "interaction_intensity": interactionIntensity,
                "task_switch_rate": taskSwitchRate,
                "task_switch_cost": 0,
                "idle_ratio": idleRatio,
                "active_interaction_time": activeTime,
                "burstiness": burstiness,
                "notification_load": normalizedNotifLoad,
                "fragmented_idle_ratio": computeFragmentedIdleRatio(events: events, durationMs: durationMs),
                "scroll_jitter_rate": scrollJitterRate,
                "distraction_score": distractionScore,
                "focus_hint": focusHint,
                "deep_focus_blocks": deepFocusBlocks
            ] as [String: Any]
        ]
    }

    // MARK: - Typing session analysis

    private static func analyzeTypingSessions(
        keyTimestamps: [Int64],
        durationSec: Double
    ) -> [String: Any] {
        if keyTimestamps.isEmpty {
            return zeroTypingData()
        }

        // Group keystrokes into sessions (gap > 2s = new session)
        let sessionGapMs: Int64 = 2000
        let sorted = keyTimestamps.sorted()
        var sessions = [[Int64]]()
        sessions.append([sorted.first!])

        for i in 1..<sorted.count {
            let gap = sorted[i] - sorted[i - 1]
            if gap > sessionGapMs {
                sessions.append([sorted[i]])
            } else {
                sessions[sessions.count - 1].append(sorted[i])
            }
        }

        // Inter-tap intervals (seconds)
        var intervals = [Double]()
        for i in 1..<sorted.count {
            intervals.append(Double(sorted[i] - sorted[i - 1]) / 1000.0)
        }

        let avgIti = intervals.isEmpty ? 0.0 : intervals.reduce(0, +) / Double(intervals.count)

        // Cadence stability (1 - coefficient of variation)
        var cadenceStability = 0.0
        if intervals.count > 1 {
            let mean = avgIti
            let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
            let std = sqrt(variance)
            cadenceStability = mean > 0 ? min(max(1.0 - (std / mean), 0.0), 1.0) : 0.0
        }

        // Session durations
        let sessionDurations = sessions.map { s -> Double in
            if s.count < 2 { return 0.0 }
            return Double(s.last! - s.first!) / 1000.0
        }
        let totalTypingDuration = sessionDurations.reduce(0, +)

        // Session gaps
        var sessionGaps = [Double]()
        for i in 1..<sessions.count {
            sessionGaps.append(Double(sessions[i].first! - sessions[i - 1].last!) / 1000.0)
        }
        let avgGap = sessionGaps.isEmpty ? 0.0 : sessionGaps.reduce(0, +) / Double(sessionGaps.count)

        // Burstiness of typing
        let typingBurstiness: Double = sessions.count > 1
            ? min(max(Double(sessions.filter { $0.count > 5 }.count) / Double(sessions.count), 0.0), 1.0)
            : 0.0

        return [
            "correction_key_count": 0,
            "clipboard_copy_count": 0,
            "clipboard_paste_count": 0,
            "clipboard_activity_rate": 0.0,
            "typing_session_count": sessions.count,
            "average_keystrokes_per_session": Int(Double(sorted.count) / Double(sessions.count)),
            "average_typing_session_duration": sessionDurations.isEmpty
                ? 0.0 : totalTypingDuration / Double(sessions.count),
            "average_typing_speed": totalTypingDuration > 0
                ? Double(sorted.count) / totalTypingDuration : 0.0,
            "average_typing_gap": avgGap,
            "average_inter-tap_interval": avgIti,
            "average_typing_cadence_stability": cadenceStability,
            "average_burstiness_of_typing": typingBurstiness,
            "total_typing_duration": totalTypingDuration,
            "active_typing_ratio": durationSec > 0
                ? min(max(totalTypingDuration / durationSec, 0.0), 1.0) : 0.0,
            "deep_typing_blocks": sessions.filter { $0.count > 20 }.count
        ]
    }

    // MARK: - Motion state

    private static func buildMotionState(motionPoints: [PhoneDataPoint]) -> [String: Any] {
        if motionPoints.isEmpty {
            return [
                "state": ["unknown"],
                "major_state": "unknown",
                "major_state_pct": 0.0,
                "ml_model": "none",
                "confidence": 0.0
            ]
        }

        // Classify: <0.1 = stationary, <0.4 = walking, else running
        let states = motionPoints.map { p -> String in
            let level = p.motionLevel ?? 0.0
            if level < 0.1 {
                return "stationary"
            } else if level < 0.4 {
                return "walking"
            } else {
                return "running"
            }
        }

        var counts = [String: Int]()
        for state in states {
            counts[state, default: 0] += 1
        }
        let majorEntry = counts.max(by: { $0.value < $1.value })!
        let majorState = majorEntry.key
        let majorPct = Double(majorEntry.value) / Double(states.count)

        // Deduplicate consecutive states
        var uniqueStates = [states.first!]
        for i in 1..<states.count {
            if states[i] != states[i - 1] {
                uniqueStates.append(states[i])
            }
        }

        return [
            "state": uniqueStates,
            "major_state": majorState,
            "major_state_pct": majorPct,
            "ml_model": "motion_heuristic_v1",
            "confidence": majorPct
        ]
    }

    // MARK: - Device context

    private static func buildDeviceContext(screenPoints: [PhoneDataPoint]) -> [String: Any] {
        return [
            "avg_screen_brightness": 0.5,
            "start_orientation": "portrait",
            "orientation_changes": 0
        ]
    }

    // MARK: - Statistical helpers

    private static func computeIdleRatio(events: [BehaviorEvent], durationMs: Int64) -> Double {
        if events.isEmpty || durationMs <= 0 { return 1.0 }

        let idleThresholdMs: Int64 = 5000
        let sorted = events.sorted { $0.timestamp < $1.timestamp }

        var idleMs: Int64 = 0
        for i in 1..<sorted.count {
            let gap = Int64(sorted[i].timestamp.timeIntervalSince1970 * 1000)
                    - Int64(sorted[i - 1].timestamp.timeIntervalSince1970 * 1000)
            if gap > idleThresholdMs { idleMs += gap }
        }

        return min(max(Double(idleMs) / Double(durationMs), 0.0), 1.0)
    }

    private static func computeFragmentedIdleRatio(events: [BehaviorEvent], durationMs: Int64) -> Double {
        if events.isEmpty || durationMs <= 0 { return 0.0 }

        let shortIdleMin: Int64 = 5000
        let shortIdleMax: Int64 = 30000
        let sorted = events.sorted { $0.timestamp < $1.timestamp }

        var fragmentedMs: Int64 = 0
        for i in 1..<sorted.count {
            let gap = Int64(sorted[i].timestamp.timeIntervalSince1970 * 1000)
                    - Int64(sorted[i - 1].timestamp.timeIntervalSince1970 * 1000)
            if gap >= shortIdleMin && gap <= shortIdleMax { fragmentedMs += gap }
        }

        return min(max(Double(fragmentedMs) / Double(durationMs), 0.0), 1.0)
    }

    private static func computeBurstiness(events: [BehaviorEvent], durationMs: Int64) -> Double {
        if events.count < 2 || durationMs <= 0 { return 0.0 }

        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var intervals = [Double]()
        for i in 1..<sorted.count {
            let gap = sorted[i].timestamp.timeIntervalSince1970 - sorted[i - 1].timestamp.timeIntervalSince1970
            intervals.append(gap * 1000.0)
        }

        if intervals.isEmpty { return 0.0 }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        if mean <= 0 { return 0.0 }
        let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
        let std = sqrt(variance)

        // Fano factor normalized to 0-1
        return min(max((std / mean) / 2.0, 0.0), 1.0)
    }

    private static func computeNotifClustering(events: [BehaviorEvent], durationMs: Int64) -> Double {
        let notifs = events.filter {
            $0.type == .notificationReceived || $0.type == .notificationOpened
        }.sorted { $0.timestamp < $1.timestamp }

        if notifs.count < 2 { return 0.0 }

        var clustered = 0
        for i in 1..<notifs.count {
            let gapMs = Int64(notifs[i].timestamp.timeIntervalSince1970 * 1000)
                      - Int64(notifs[i - 1].timestamp.timeIntervalSince1970 * 1000)
            if gapMs < 60_000 {
                clustered += 1
            }
        }
        return min(max(Double(clustered) / Double(notifs.count - 1), 0.0), 1.0)
    }

    private static func computeDistractionScore(
        appSwitchCount: Int,
        notifIgnored: Int,
        notifReceived: Int,
        scrollCount: Int,
        idleRatio: Double
    ) -> Double {
        let switchFactor = min(max(Double(appSwitchCount) / 10.0, 0.0), 1.0) * 0.3
        let notifFactor = notifReceived > 0
            ? (1.0 - Double(notifIgnored) / Double(notifReceived)) * 0.2 : 0.0
        let idleFactor = idleRatio * 0.3
        let scrollFactor = min(max(Double(scrollCount) / 50.0, 0.0), 1.0) * 0.2

        return min(max(switchFactor + notifFactor + idleFactor + scrollFactor, 0.0), 1.0)
    }

    private static func detectDeepFocusBlocks(
        events: [BehaviorEvent],
        durationMs: Int64
    ) -> [[String: Any]] {
        if events.isEmpty { return [] }

        let minBlockMs: Int64 = 120_000
        let maxGapMs: Int64 = 10_000
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var blocks = [[String: Any]]()

        var blockStart = Int64(sorted.first!.timestamp.timeIntervalSince1970 * 1000)
        var blockEnd = blockStart

        for i in 1..<sorted.count {
            let currentMs = Int64(sorted[i].timestamp.timeIntervalSince1970 * 1000)
            let prevMs = Int64(sorted[i - 1].timestamp.timeIntervalSince1970 * 1000)
            let gap = currentMs - prevMs
            if gap <= maxGapMs {
                blockEnd = currentMs
            } else {
                let blockDuration = blockEnd - blockStart
                if blockDuration >= minBlockMs {
                    blocks.append([
                        "started_at": msToIso(blockStart),
                        "ended_at": msToIso(blockEnd),
                        "duration_ms": blockDuration
                    ])
                }
                blockStart = currentMs
                blockEnd = currentMs
            }
        }

        // Check final block
        let lastDuration = blockEnd - blockStart
        if lastDuration >= minBlockMs {
            blocks.append([
                "started_at": msToIso(blockStart),
                "ended_at": msToIso(blockEnd),
                "duration_ms": lastDuration
            ])
        }

        return blocks
    }

    // MARK: - Zero data helpers

    private static func zeroTypingData() -> [String: Any] {
        return [
            "correction_key_count": 0,
            "clipboard_copy_count": 0,
            "clipboard_paste_count": 0,
            "clipboard_activity_rate": 0.0,
            "typing_session_count": 0,
            "average_keystrokes_per_session": 0,
            "average_typing_session_duration": 0.0,
            "average_typing_speed": 0.0,
            "average_typing_gap": 0.0,
            "average_inter-tap_interval": 0.0,
            "average_typing_cadence_stability": 0.0,
            "average_burstiness_of_typing": 0.0,
            "total_typing_duration": 0.0,
            "active_typing_ratio": 0.0,
            "deep_typing_blocks": 0
        ]
    }

    private static func zeroBehaviorData() -> [String: Any?] {
        return [
            "micro_session": false,
            "session_spacing": 0,
            "motion_state": [
                "state": ["unknown"],
                "major_state": "unknown",
                "major_state_pct": 0.0,
                "ml_model": "none",
                "confidence": 0.0
            ] as [String: Any],
            "device_context": [
                "avg_screen_brightness": 0.0,
                "start_orientation": "portrait",
                "orientation_changes": 0
            ] as [String: Any],
            "activity_summary": ["total_events": 0, "app_switch_count": 0] as [String: Any],
            "notification_summary": [
                "notification_count": 0,
                "notification_ignored": 0,
                "notification_ignore_rate": 0.0,
                "notification_clustering_index": 0.0,
                "call_count": 0,
                "call_ignored": 0
            ] as [String: Any],
            "system_state": [
                "internet_state": true,
                "do_not_disturb": false,
                "charging": false
            ] as [String: Any],
            "typing_session_summary": zeroTypingData(),
            "behavioral_metrics": [
                "correction_rate": 0.0,
                "editing_friction": 0.0,
                "interaction_intensity": 0.0,
                "task_switch_rate": 0.0,
                "task_switch_cost": 0.0,
                "idle_ratio": 0.0,
                "active_interaction_time": 0.0,
                "burstiness": 0.0,
                "notification_load": 0.0,
                "fragmented_idle_ratio": 0.0,
                "scroll_jitter_rate": 0.0,
                "distraction_score": 0.0,
                "focus_hint": 0.0,
                "deep_focus_blocks": [[String: Any]]()
            ] as [String: Any]
        ]
    }
}
