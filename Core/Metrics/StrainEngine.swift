import Foundation

public struct StrainConfig: Sendable {
    public var age: Int
    public var maxHROverride: Double?
    /// Zeitkonstante der logarithmischen 0–21-Skala.
    public var tau: Double
    public var sex: BiologicalSex

    public init(age: Int = 30, maxHROverride: Double? = nil, tau: Double = StrainEngine.defaultTau, sex: BiologicalSex = .unspecified) {
        self.age = age
        self.maxHROverride = maxHROverride
        self.tau = tau
        self.sex = sex
    }

    /// Maximale Herzfrequenz: Override oder Tanaka-Formel (208 − 0,7 × Alter).
    public var maxHR: Double {
        maxHROverride ?? (208 - 0.7 * Double(age))
    }
}

public struct StrainResult: Sendable {
    /// Strain auf der Whoop-artigen 0–21-Skala.
    public let strain: Double
    public let rawLoad: Double
    /// Minuten je Intensitätszone (Index 0 = sehr leicht … 5 = maximal).
    public let zoneMinutes: [Double]
    /// Minuten unterhalb der ersten Zone (Ruhe/Alltag) — zählt nicht zum Strain,
    /// macht aber die aufgezeichnete Gesamtzeit sichtbar.
    public let restMinutes: Double
    public let avgHR: Double?
    public let peakHR: Double?

    public init(strain: Double, rawLoad: Double, zoneMinutes: [Double], restMinutes: Double = 0, avgHR: Double?, peakHR: Double?) {
        self.strain = strain
        self.rawLoad = rawLoad
        self.zoneMinutes = zoneMinutes
        self.restMinutes = restMinutes
        self.avgHR = avgHR
        self.peakHR = peakHR
    }

    /// Aufgezeichnete Gesamtzeit mit gültigem Puls (Ruhe + aktive Zonen), in Minuten.
    public var trackedMinutes: Double {
        restMinutes + zoneMinutes.reduce(0, +)
    }

    public static let empty = StrainResult(strain: 0, rawLoad: 0, zoneMinutes: Array(repeating: 0, count: 6), avgHR: nil, peakHR: nil)
}

/// Kardiovaskuläre Belastung nach dem TRIMP-Prinzip:
/// Zeit in Herzfrequenz-Reserve-Zonen wird gewichtet aufsummiert und
/// logarithmisch auf 0–21 abgebildet (wie die Whoop-Strain-Skala, die nach
/// oben immer schwerer zu steigern ist).
public enum StrainEngine {
    /// Untergrenzen der Zonen als Anteil der Herzfrequenz-Reserve (Karvonen).
    public static let zoneLowerBounds: [Double] = [0.20, 0.30, 0.45, 0.60, 0.72, 0.85]
    public static let zoneWeights: [Double] = [0.5, 1.0, 2.5, 5.0, 8.0, 11.0]
    public static let zoneLabels: [String] = ["Very light", "Light", "Moderate", "Demanding", "Hard", "Max"]

    /// Time constant of the 0–21 scale, calibrated for Banister TRIMP anchors:
    /// easy day (≈ 30 TRIMP) ≈ 3.5, solid 60-min session (≈ 110) ≈ 10.5,
    /// hard day (≈ 230) ≈ 16, extreme endurance day (≈ 430) ≈ 19.7.
    public static let defaultTau = 160.0
    /// Heart-rate reserve below which effort is treated as daily living (no strain).
    public static let strainFloor = 0.30

    /// Banister TRIMP weight per minute at a given fraction of heart-rate reserve
    /// (Banister 1991): `y = ΔHR · a · e^(b·ΔHR)` with a = 0.64, b = 1.92 (men) and
    /// a = 0.86, b = 1.67 (women); the unspecified profile uses the mean of both.
    public static func trimpPerMinute(fraction x: Double, sex: BiologicalSex) -> Double {
        let f = Stats.clamp(x, 0, 1.05)
        switch sex {
        case .male: return f * 0.64 * exp(1.92 * f)
        case .female: return f * 0.86 * exp(1.67 * f)
        case .unspecified: return f * 0.75 * exp(1.795 * f)
        }
    }

    public static func strain(fromRaw raw: Double, tau: Double = StrainEngine.defaultTau) -> Double {
        guard raw > 0 else { return 0 }
        return 21 * (1 - exp(-raw / tau))
    }

    /// Tages-Belastungsziel aus der morgendlichen Recovery (wie Whoops
    /// „Strain Target": der Strich auf dem Ring). Kalibriert an Whoops
    /// publizierten Bereichen — Training bei grüner Recovery ~14–18,
    /// lockere Tage ~10–14, rote Recovery deutlich darunter.
    /// Transparent linear: 0,2 × Recovery, gedeckelt auf 3…18,5.
    public static func targetStrain(forRecovery recovery: Int) -> Double {
        Stats.clamp(0.2 * Double(recovery), 3, 18.5)
    }

    public static func zoneIndex(for fraction: Double) -> Int? {
        var index: Int?
        for (i, bound) in zoneLowerBounds.enumerated() where fraction >= bound {
            index = i
        }
        return index
    }

    /// Summiert die gewichtete Belastung über HR-Samples (Minutenauflösung).
    public static func accumulate(
        samples: [HRSample],
        restingHR: Double,
        maxHR: Double,
        sex: BiologicalSex = .unspecified
    ) -> (raw: Double, zones: [Double], avgHR: Double?, peakHR: Double?, restMin: Double) {
        let emptyZones = Array(repeating: 0.0, count: zoneWeights.count)
        guard !samples.isEmpty, maxHR > restingHR + 20 else {
            return (0, emptyZones, nil, nil, 0)
        }
        let sorted = samples.sorted { $0.t < $1.t }
        var raw = 0.0
        var zones = emptyZones
        var restMin = 0.0
        var previous: Date?
        var sum = 0.0
        var peak = 0.0

        for sample in sorted {
            var dt = 1.0
            if let prev = previous {
                dt = Stats.clamp(sample.t.timeIntervalSince(prev) / 60, 0, 5)
            }
            previous = sample.t
            sum += sample.bpm
            peak = max(peak, sample.bpm)

            let fraction = (sample.bpm - restingHR) / (maxHR - restingHR)
            guard let zone = zoneIndex(for: fraction) else {
                restMin += dt // unter Zone 0 → Ruhe/Alltag, kein Strain
                continue
            }
            if fraction >= strainFloor {
                raw += trimpPerMinute(fraction: fraction, sex: sex) * dt
            }
            zones[zone] += dt
        }
        return (raw, zones, sum / Double(sorted.count), peak, restMin)
    }

    /// Tages-Strain aus Intraday-HR; Fallback über Workout-Durchschnittspuls
    /// und Schritte, falls keine Samples vorliegen.
    public static func dayStrain(
        record: DayRecord,
        restingHR: Double?,
        config: StrainConfig = StrainConfig()
    ) -> StrainResult {
        let rhr = restingHR ?? 62
        let maxHR = config.maxHR

        if !record.hrSamples.isEmpty {
            let acc = accumulate(samples: record.hrSamples, restingHR: rhr, maxHR: maxHR, sex: config.sex)
            return StrainResult(
                strain: strain(fromRaw: acc.raw, tau: config.tau),
                rawLoad: acc.raw,
                zoneMinutes: acc.zones,
                restMinutes: acc.restMin,
                avgHR: acc.avgHR,
                peakHR: acc.peakHR
            )
        }

        // Fallback ohne Intraday-Daten
        var raw = 0.0
        var zones = Array(repeating: 0.0, count: zoneWeights.count)
        for workout in record.workouts {
            guard let avgHR = workout.averageHR else { continue }
            let fraction = (avgHR - rhr) / (maxHR - rhr)
            guard let zone = zoneIndex(for: fraction) else { continue }
            if fraction >= strainFloor {
                raw += trimpPerMinute(fraction: fraction, sex: config.sex) * workout.durationMinutes
            }
            zones[zone] += workout.durationMinutes
        }
        if let steps = record.steps, steps > 0 {
            raw += Double(steps) / 1000 * 2.5
        }
        return StrainResult(
            strain: strain(fromRaw: raw, tau: config.tau),
            rawLoad: raw,
            zoneMinutes: zones,
            avgHR: nil,
            peakHR: nil
        )
    }

    /// Strain eines einzelnen Workouts (eigene 0–21-Skala).
    public static func workoutStrain(
        workout: Workout,
        daySamples: [HRSample],
        restingHR: Double?,
        config: StrainConfig = StrainConfig()
    ) -> Double? {
        let rhr = restingHR ?? 62
        let slice = daySamples.filter { $0.t >= workout.start && $0.t <= workout.end }
        if slice.count >= 3 {
            let acc = accumulate(samples: slice, restingHR: rhr, maxHR: config.maxHR, sex: config.sex)
            return strain(fromRaw: acc.raw, tau: config.tau)
        }
        guard let avgHR = workout.averageHR else { return nil }
        let fraction = (avgHR - rhr) / (config.maxHR - rhr)
        guard fraction >= strainFloor else { return 0 }
        let raw = trimpPerMinute(fraction: fraction, sex: config.sex) * workout.durationMinutes
        return strain(fromRaw: raw, tau: config.tau)
    }
}
