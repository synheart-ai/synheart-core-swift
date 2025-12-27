import Foundation

/// Extracts behavioral features from events
class BehaviorFeatureExtractor {
    /// Extract features from a list of events
    func extract(_ events: [BehaviorEvent]) -> BehaviorWindowFeatures {
        if events.isEmpty {
            return BehaviorWindowFeatures(
                tapRateNorm: 0.0,
                keystrokeRateNorm: 0.0,
                scrollVelocityNorm: 0.0,
                idleRatio: 1.0,
                switchRateNorm: 0.0,
                burstiness: 0.0,
                sessionFragmentation: 0.0,
                notificationLoad: 0.0,
                distractionScore: 0.0,
                focusHint: 1.0
            )
        }
        
        let tapRate = calculateTapRate(events)
        let keystrokeRate = calculateKeystrokeRate(events)
        let scrollVelocity = calculateScrollVelocity(events)
        let idleRatio = calculateIdleRatio(events)
        let switchRate = calculateSwitchRate(events)
        let burstiness = calculateBurstiness(events)
        let fragmentation = calculateFragmentation(events)
        let notificationLoad = calculateNotificationLoad(events)
        
        // Simple heuristic for distraction/focus (will be replaced by MLP)
        let distractionScore = estimateDistraction(
            switchRate: switchRate,
            burstiness: burstiness,
            fragmentation: fragmentation,
            notificationLoad: notificationLoad
        )
        let focusHint = 1.0 - distractionScore
        
        return BehaviorWindowFeatures(
            tapRateNorm: tapRate,
            keystrokeRateNorm: keystrokeRate,
            scrollVelocityNorm: scrollVelocity,
            idleRatio: idleRatio,
            switchRateNorm: switchRate,
            burstiness: burstiness,
            sessionFragmentation: fragmentation,
            notificationLoad: notificationLoad,
            distractionScore: distractionScore,
            focusHint: focusHint
        )
    }
    
    private func calculateTapRate(_ events: [BehaviorEvent]) -> Double {
        let taps = events.filter { $0.type == .tap }.count
        let duration = getDuration(events)
        if duration == 0 { return 0.0 }
        return min(1.0, max(0.0, Double(taps) / duration))
    }
    
    private func calculateKeystrokeRate(_ events: [BehaviorEvent]) -> Double {
        let keystrokes = events.filter { $0.type == .keyDown || $0.type == .keyUp }.count
        let duration = getDuration(events)
        if duration == 0 { return 0.0 }
        return min(1.0, max(0.0, Double(keystrokes) / duration / 2.0)) // Normalize to reasonable rate
    }
    
    private func calculateScrollVelocity(_ events: [BehaviorEvent]) -> Double {
        let scrollEvents = events.filter { $0.type == .scroll }
        if scrollEvents.isEmpty { return 0.0 }
        
        let totalDelta = scrollEvents.compactMap { event -> Double? in
            guard let metadata = event.metadata,
                  let delta = metadata["delta"] as? Double else {
                return nil
            }
            return abs(delta)
        }.reduce(0, +)
        
        let duration = getDuration(events)
        if duration == 0 { return 0.0 }
        
        return min(1.0, max(0.0, totalDelta / duration))
    }
    
    private func calculateIdleRatio(_ events: [BehaviorEvent]) -> Double {
        let duration = getDuration(events)
        if duration == 0 { return 1.0 }
        
        // Simple heuristic: idle if no events for > 5 seconds
        let idleThreshold: TimeInterval = 5.0
        var idleTime: TimeInterval = 0.0
        var lastEventTime: Date?
        
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let lastTime = lastEventTime {
                let gap = event.timestamp.timeIntervalSince(lastTime)
                if gap > idleThreshold {
                    idleTime += gap - idleThreshold
                }
            }
            lastEventTime = event.timestamp
        }
        
        return min(1.0, max(0.0, idleTime / duration))
    }
    
    private func calculateSwitchRate(_ events: [BehaviorEvent]) -> Double {
        let switches = events.filter { $0.type == .appSwitch }.count
        let duration = getDuration(events)
        if duration == 0 { return 0.0 }
        return min(1.0, max(0.0, Double(switches) / duration))
    }
    
    private func calculateBurstiness(_ events: [BehaviorEvent]) -> Double {
        // Simple burstiness: variance in inter-event intervals
        guard events.count > 1 else { return 0.0 }
        
        let sortedEvents = events.sorted(by: { $0.timestamp < $1.timestamp })
        var intervals: [TimeInterval] = []
        
        for i in 1..<sortedEvents.count {
            let interval = sortedEvents[i].timestamp.timeIntervalSince(sortedEvents[i-1].timestamp)
            intervals.append(interval)
        }
        
        guard !intervals.isEmpty else { return 0.0 }
        
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(intervals.count)
        
        return min(1.0, max(0.0, sqrt(variance) / (mean + 0.001))) // Normalize
    }
    
    private func calculateFragmentation(_ events: [BehaviorEvent]) -> Double {
        // Simple fragmentation: number of idle gaps
        let idleThreshold: TimeInterval = 10.0
        var gaps = 0
        
        let sortedEvents = events.sorted(by: { $0.timestamp < $1.timestamp })
        for i in 1..<sortedEvents.count {
            let gap = sortedEvents[i].timestamp.timeIntervalSince(sortedEvents[i-1].timestamp)
            if gap > idleThreshold {
                gaps += 1
            }
        }
        
        let duration = getDuration(events)
        if duration == 0 { return 0.0 }
        
        return min(1.0, max(0.0, Double(gaps) / (duration / 60.0))) // Gaps per minute
    }
    
    private func calculateNotificationLoad(_ events: [BehaviorEvent]) -> Double {
        let notifications = events.filter {
            $0.type == .notificationReceived || $0.type == .notificationOpened
        }.count
        
        let duration = getDuration(events)
        if duration == 0 { return 0.0 }
        
        return min(1.0, max(0.0, Double(notifications) / duration))
    }
    
    private func estimateDistraction(
        switchRate: Double,
        burstiness: Double,
        fragmentation: Double,
        notificationLoad: Double
    ) -> Double {
        // Simple weighted combination (will be replaced by MLP)
        let distraction = (switchRate * 0.3) + (burstiness * 0.2) + (fragmentation * 0.3) + (notificationLoad * 0.2)
        return min(1.0, max(0.0, distraction))
    }
    
    private func getDuration(_ events: [BehaviorEvent]) -> TimeInterval {
        guard !events.isEmpty else { return 0.0 }
        let sorted = events.sorted(by: { $0.timestamp < $1.timestamp })
        return sorted.last!.timestamp.timeIntervalSince(sorted.first!.timestamp)
    }
}

