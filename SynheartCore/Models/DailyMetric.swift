import Foundation

/// The daily metrics the personal baselines accept from
/// ``Synheart/srmPushWearableDaily(provider:metric:date:value:vendorSummary:timeZone:)``,
/// by their runtime names. The unit is part of each name: push seconds to
/// ``sleepDurationS``, minutes to ``sleepDeepMin``, a `0...1` fraction to
/// ``vendorRecoveryFrac``.
///
/// Any other name is refused with `1004`, and so are the names these replaced
/// (`hrv_rmssd`, `resting_hr`, `sleep_need`, …).
public enum DailyMetric {
    /// Total sleep for the night, in seconds.
    public static let sleepDurationS = "sleep.duration_s"
    /// Midpoint of the sleep period, in hours after local midnight.
    public static let sleepMidpointH = "sleep.midpoint_h"
    /// Overnight RMSSD, in milliseconds.
    public static let overnightRmssdMs = "cardiac.overnight_rmssd_ms"
    /// Overnight SDNN, in milliseconds.
    public static let overnightSdnnMs = "cardiac.overnight_sdnn_ms"
    /// Resting heart rate, in beats per minute.
    public static let restingHrBpm = "cardiac.resting_hr_bpm"
    /// A provider's recovery score as a fraction, `0...1`.
    public static let vendorRecoveryFrac = "vendor.recovery_frac"
    /// Deep sleep, in minutes.
    public static let sleepDeepMin = "sleep.deep_min"
    /// REM sleep, in minutes.
    public static let sleepRemMin = "sleep.rem_min"
    /// A provider's daily strain normalised to `0...1`.
    public static let vendorStrainFrac = "vendor.strain_frac"
    /// Step count for the day.
    public static let stepsCount = "motion.steps_count"
    /// Heart-rate-reserve load for the day, in arbitrary units.
    public static let hrrLoadAu = "cardiac.hrr_load_au"
    /// Standard deviation of overnight heart rate, in beats per minute.
    public static let overnightHrSdBpm = "cardiac.overnight_hr_sd_bpm"

    public static let all: Set<String> = [
        sleepDurationS, sleepMidpointH, overnightRmssdMs, overnightSdnnMs,
        restingHrBpm, vendorRecoveryFrac, sleepDeepMin, sleepRemMin,
        vendorStrainFrac, stepsCount, hrrLoadAu, overnightHrSdBpm,
    ]
}
