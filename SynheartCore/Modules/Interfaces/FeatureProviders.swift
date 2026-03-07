import Foundation

/// Window types for time-based aggregation
public enum WindowType {
    /// 30-second window
    case window30s

    /// 5-minute window
    case window5m

    /// 1-hour window
    case window1h

    /// 24-hour window
    case window24h
}

/// Sleep stage information
public enum SleepStage {
    case awake
    case light
    case deep
    case rem
}

// MARK: - Wear Module

/// Biosignal features from wearables
public struct WearWindowFeatures {
    /// Window duration
    public let windowDuration: TimeInterval

    /// Average heart rate (bpm)
    public let hrAverage: Double?

    /// Minimum heart rate (bpm)
    public let hrMin: Double?

    /// Maximum heart rate (bpm)
    public let hrMax: Double?

    /// Heart rate variability - RMSSD (ms)
    public let hrvRmssd: Double?

    /// Motion index (0.0 - 1.0)
    public let motionIndex: Double?

    /// Sleep stage
    public let sleepStage: SleepStage?

    /// Respiration rate (breaths per minute)
    public let respRate: Double?

    public init(
        windowDuration: TimeInterval,
        hrAverage: Double? = nil,
        hrMin: Double? = nil,
        hrMax: Double? = nil,
        hrvRmssd: Double? = nil,
        motionIndex: Double? = nil,
        sleepStage: SleepStage? = nil,
        respRate: Double? = nil
    ) {
        self.windowDuration = windowDuration
        self.hrAverage = hrAverage
        self.hrMin = hrMin
        self.hrMax = hrMax
        self.hrvRmssd = hrvRmssd
        self.motionIndex = motionIndex
        self.sleepStage = sleepStage
        self.respRate = respRate
    }
}

// MARK: - Phone Module

/// Phone context features
public struct PhoneWindowFeatures {
    /// Motion level (0.0 - 1.0)
    public let motionLevel: Double

    /// App switch rate (normalized)
    public let appSwitchRate: Double

    /// Screen on ratio (proportion of window)
    public let screenOnRatio: Double

    /// Notification rate (per minute)
    public let notificationRate: Double

    public init(
        motionLevel: Double,
        appSwitchRate: Double,
        screenOnRatio: Double,
        notificationRate: Double
    ) {
        self.motionLevel = motionLevel
        self.appSwitchRate = appSwitchRate
        self.screenOnRatio = screenOnRatio
        self.notificationRate = notificationRate
    }
}

// MARK: - Behavior Module

/// Behavioral interaction features
public struct BehaviorWindowFeatures {
    /// Typing cadence (normalized 0.0 - 1.0)
    public let tapRateNorm: Double

    /// Keystroke rate (normalized 0.0 - 1.0)
    public let keystrokeRateNorm: Double

    /// Scroll velocity (normalized 0.0 - 1.0)
    public let scrollVelocityNorm: Double

    /// Idle ratio (0.0 - 1.0)
    public let idleRatio: Double

    /// App/context switch rate (normalized)
    public let switchRateNorm: Double

    /// Burstiness (0.0 - 1.0)
    public let burstiness: Double

    /// Session fragmentation (0.0 - 1.0)
    public let sessionFragmentation: Double

    /// Notification load (0.0 - 1.0)
    public let notificationLoad: Double

    /// Distraction score from MLP (0.0 - 1.0)
    public let distractionScore: Double

    /// Focus hint from MLP (0.0 - 1.0)
    public let focusHint: Double

    public init(
        tapRateNorm: Double,
        keystrokeRateNorm: Double,
        scrollVelocityNorm: Double,
        idleRatio: Double,
        switchRateNorm: Double,
        burstiness: Double,
        sessionFragmentation: Double,
        notificationLoad: Double,
        distractionScore: Double,
        focusHint: Double
    ) {
        self.tapRateNorm = tapRateNorm
        self.keystrokeRateNorm = keystrokeRateNorm
        self.scrollVelocityNorm = scrollVelocityNorm
        self.idleRatio = idleRatio
        self.switchRateNorm = switchRateNorm
        self.burstiness = burstiness
        self.sessionFragmentation = sessionFragmentation
        self.notificationLoad = notificationLoad
        self.distractionScore = distractionScore
        self.focusHint = focusHint
    }
}
