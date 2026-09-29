import Foundation

public enum StressLevel: String, Sendable {
    case low, moderate, high

    public var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }
}

public struct StressResult: Sendable {
    public let dateKey: String
    /// Estimated physiological stress, 0–100 (a typical day for *you* lands near 30).
    public let score: Double
    public let level: StressLevel
    /// Same value on the familiar 0–3 scale.
    public var scale3: Double { score / 100 * 3 }
    /// Stress by hour of day (0–23); nil where there is not enough heart-rate data.
    public let hourly: [Double?]
    /// Daytime heart-rate part (0–1) and overnight HRV part (0–1); nil if unavailable.
    public let heartRatePart: Double?
    public let hrvPart: Double?
    /// Median daytime heart rate above resting (bpm) — the raw signal behind the HR part.
    public let daytimeElevationBpm: Double?
}

/// Estimates physiological stress from data the Fitbit Air actually provides:
///
/// 1. **Daytime heart-rate elevation** — median HR above resting HR over waking,
///    non-workout minutes, compared with *your own* recent days (z-score). Sustained
///    elevation at low intensity is the classic sympathetic-activation signal.
/// 2. **Overnight HRV** — ln(RMSSD) against your 30-day baseline; a suppressed HRV
///    means less parasympathetic recovery going into the day.
///
/// Both go through a logistic curve and are blended 60/40 (HR only or HRV only when
/// one is missing). There is no per-minute motion data, so this is an *estimate*:
/// it cannot tell a brisk walk from a stressful meeting, which is why the median
/// (robust to short bursts) is used instead of the mean.
public enum StressEngine {
    static let wakingHours = 6..<23
    /// Minutes after a workout that are excluded (heart rate is still recovering).
    static let workoutCooldownMinutes = 20.0
    static let hrWeight = 0.6
    static let hrvWeight = 0.4
    /// Offset so that an average day (z = 0) maps to ≈ 33 (bottom of "moderate").
    static let typicalOffset = 0.7
    static let slope = 1.2

    /// Fallback while there is too little personal history (< 5 days): a population-level
    /// z-score. Awake, non-workout median HR typically sits ~15–25 bpm above resting HR, so
    /// 20 bpm is "typical" (→ score ≈ 33) and each 8 bpm is one SD.
    static func absoluteZ(_ elevationBpm: Double) -> Double {
        (elevationBpm - 20) / 8
    }

    public static func level(for score: Double) -> StressLevel {
        score < 33 ? .low : (score < 66 ? .moderate : .high)
    }

    /// Non-workout waking samples of a record as (hour, bpm) pairs.
    static func daytimeSamples(_ record: DayRecord) -> [(hour: Int, bpm: Double)] {
        let calendar = Calendar.current
        let blocked = record.workouts.map {
            ($0.start, $0.end.addingTimeInterval(workoutCooldownMinutes * 60))
        }
        return record.hrSamples.compactMap { sample in
            let hour = calendar.component(.hour, from: sample.t)
            guard wakingHours.contains(hour) else { return nil }
            if blocked.contains(where: { sample.t >= $0.0 && sample.t <= $0.1 }) { return nil }
            return (hour, sample.bpm)
        }
    }

    static func restingReference(_ record: DayRecord) -> Double? {
        if let rhr = record.restingHR { return rhr }
        let bpms = record.hrSamples.map { $0.bpm }
        return Stats.percentile(bpms, 0.05)
    }

    /// Median daytime HR above resting, or nil with too little data (< 60 minutes).
    static func daytimeElevation(_ record: DayRecord) -> Double? {
        guard let rhr = restingReference(record) else { return nil }
        let samples = daytimeSamples(record)
        guard samples.count >= 60 else { return nil }
        guard let median = Stats.percentile(samples.map { $0.bpm }, 0.5) else { return nil }
        return median - rhr
    }

    public static func compute(
        dateKey: String,
        record: DayRecord,
        history: [DayRecord],
        maxHR: Double
    ) -> StressResult? {
        let elevation = daytimeElevation(record)
        let hrvBaseline = Stats.baseline(history.compactMap { $0.hrvRmssd }.suffix(30).map { log($0) })

        // --- Heart-rate part ---
        var hrPart: Double?
        var elevationSD = 3.0
        var elevationMean: Double?
        if let elevation {
            let pastElevations = history.suffix(14).compactMap { daytimeElevation($0) }
            if pastElevations.count >= 5 {
                elevationMean = Stats.mean(pastElevations)
                elevationSD = max(2.0, Stats.standardDeviation(pastElevations))
                let z = (elevation - elevationMean!) / elevationSD
                hrPart = Stats.logistic(slope * z - typicalOffset)
            } else {
                hrPart = Stats.logistic(slope * absoluteZ(elevation) - typicalOffset)
            }
        }

        // --- HRV part ---
        var hrvPart: Double?
        if let hrv = record.hrvRmssd, let baseline = hrvBaseline, baseline.isReliable {
            let z = baseline.z(log(hrv), minSD: 0.03)
            hrvPart = Stats.logistic(-slope * z - typicalOffset)
        }

        guard hrPart != nil || hrvPart != nil else { return nil }

        var weighted = 0.0
        var totalWeight = 0.0
        if let hrPart { weighted += hrPart * hrWeight; totalWeight += hrWeight }
        if let hrvPart { weighted += hrvPart * hrvWeight; totalWeight += hrvWeight }
        let score = Stats.clamp(weighted / totalWeight * 100, 0, 100)

        // --- Hourly profile (same personal scale, per hour) ---
        var hourly = [Double?](repeating: nil, count: 24)
        if let rhr = restingReference(record) {
            let byHour = Dictionary(grouping: daytimeSamples(record), by: { $0.hour })
            for (hour, samples) in byHour where samples.count >= 10 {
                guard let median = Stats.percentile(samples.map { $0.bpm }, 0.5) else { continue }
                let e = median - rhr
                if let mean = elevationMean {
                    hourly[hour] = Stats.logistic(slope * ((e - mean) / elevationSD) - typicalOffset) * 100
                } else {
                    hourly[hour] = Stats.logistic(slope * absoluteZ(e) - typicalOffset) * 100
                }
            }
        }

        return StressResult(
            dateKey: dateKey,
            score: score,
            level: level(for: score),
            hourly: hourly,
            heartRatePart: hrPart,
            hrvPart: hrvPart,
            daytimeElevationBpm: elevation
        )
    }
}
