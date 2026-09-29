import Foundation

public struct SleepEngineConfig: Sendable {
    /// Basis-Schlafbedarf in Minuten (Standard: 7 h 36 min, wie Whoop-Default).
    public var baselineNeedMinutes: Double
    /// Anteil der Schlafschuld, der pro Nacht zusätzlich eingefordert wird.
    public var debtRepayFraction: Double
    /// Obergrenze der akkumulierten Schlafschuld.
    public var maxDebtMinutes: Double
    /// Maximaler Schuld-ZUWACHS pro Nacht. Verhindert, dass eine einzelne
    /// Katastrophen- oder Artefakt-Nacht (z. B. eine kurze Setup-Session am
    /// ersten Tag) die Schuld auf einen Schlag maximiert.
    public var maxDebtGainPerNightMinutes: Double
    /// Maximaler Bedarfs-Aufschlag durch hohen Vortages-Strain.
    public var strainNeedBoostMaxMinutes: Double

    public init(
        baselineNeedMinutes: Double = 456,
        debtRepayFraction: Double = 0.30,
        maxDebtMinutes: Double = 300,
        maxDebtGainPerNightMinutes: Double = 180,
        strainNeedBoostMaxMinutes: Double = 45
    ) {
        self.baselineNeedMinutes = baselineNeedMinutes
        self.debtRepayFraction = debtRepayFraction
        self.maxDebtMinutes = maxDebtMinutes
        self.maxDebtGainPerNightMinutes = maxDebtGainPerNightMinutes
        self.strainNeedBoostMaxMinutes = strainNeedBoostMaxMinutes
    }
}

public struct SleepAnalysis: Sendable {
    public let dateKey: String
    public let sleptMinutes: Double
    public let napMinutes: Double
    public let needMinutes: Double
    /// Schlafperformance 0–100 (geschlafene Zeit / Bedarf).
    public let performance: Double
    /// Composite sleep score 0–100: duration vs need (50 %), efficiency (20 %),
    /// restorative share deep+REM (20 %) and bed/wake consistency (10 %);
    /// missing components are re-weighted.
    public let score: Double
    /// Schlafschuld NACH dieser Nacht.
    public let debtAfterMinutes: Double
    /// Konsistenz der Zubettgeh-/Aufwachzeiten (0–100), nil ohne Historie.
    public let consistency: Double?
    public let efficiency: Double?
    public let stageMinutes: [SleepStage: Double]
    public let bedTime: Date?
    public let wakeTime: Date?
    public let hasData: Bool

    public var restorativeMinutes: Double {
        (stageMinutes[.deep] ?? 0) + (stageMinutes[.rem] ?? 0)
    }
}

/// Empfehlung für die kommende Nacht.
public struct BedtimeRecommendation: Sendable {
    /// Projizierter Schlafbedarf heute Nacht (Minuten).
    public let projectedNeedMinutes: Double
    /// Gewohnte Aufwachzeit als Minuten seit Mitternacht (nil ohne Historie).
    public let habitualWakeMinutes: Double?
    /// Empfohlene Zubettgehzeit als Minuten seit Mitternacht (nil ohne Historie).
    public let recommendedBedtimeMinutes: Double?
    /// Aktuelle Schlafschuld (Minuten), auf der die Projektion basiert.
    public let debtMinutes: Double
}

public enum SleepEngine {
    /// Empfehlung für die kommende Nacht: projizierter Bedarf (aus Schlafschuld
    /// und heutigem Strain) und – aus der gewohnten Aufwachzeit – die Uhrzeit,
    /// zu der man dafür ins Bett sollte.
    public static func bedtimeRecommendation(
        currentDebtMinutes: Double,
        strainToday: Double,
        recentWakeTimes: [Date],
        config: SleepEngineConfig = SleepEngineConfig()
    ) -> BedtimeRecommendation {
        let strainBoost = Stats.clamp((strainToday - 8) / 13, 0, 1) * config.strainNeedBoostMaxMinutes
        var need = config.baselineNeedMinutes + currentDebtMinutes * config.debtRepayFraction + strainBoost
        need = Stats.clamp(need, config.baselineNeedMinutes - 30, config.baselineNeedMinutes + 150)

        guard !recentWakeTimes.isEmpty else {
            return BedtimeRecommendation(
                projectedNeedMinutes: need,
                habitualWakeMinutes: nil,
                recommendedBedtimeMinutes: nil,
                debtMinutes: currentDebtMinutes
            )
        }

        // Aufwachzeiten liegen morgens (kein Mitternachts-Übergang) → einfacher Mittelwert.
        let wakeMinutes = recentWakeTimes.map { clockMinutes(of: $0) }
        let habitualWake = Stats.mean(wakeMinutes)
        let bedtime = ((habitualWake - need).truncatingRemainder(dividingBy: 1440) + 1440)
            .truncatingRemainder(dividingBy: 1440)

        return BedtimeRecommendation(
            projectedNeedMinutes: need,
            habitualWakeMinutes: habitualWake,
            recommendedBedtimeMinutes: bedtime,
            debtMinutes: currentDebtMinutes
        )
    }

    /// Minuten seit Mitternacht (0…1439).
    static func clockMinutes(of date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Analysiert alle Tage chronologisch und führt Schlafschuld sowie
    /// Konsistenz-Historie über die gesamte Zeitreihe.
    /// `strainByDay` liefert den Tages-Strain (für den Bedarfs-Aufschlag der Folgenacht).
    public static func analyze(
        days: [String: DayRecord],
        config: SleepEngineConfig = SleepEngineConfig(),
        strainByDay: [String: Double] = [:]
    ) -> [String: SleepAnalysis] {
        let keys = days.keys.sorted()
        guard let first = keys.first, let last = keys.last else { return [:] }

        var result: [String: SleepAnalysis] = [:]
        var debt: Double = 0
        var recentBedWake: [(bed: Double, wake: Double)] = []

        for key in DayKey.keys(from: first, to: last) {
            let record = days[key]
            let sessions = record?.sleepSessions ?? []
            let main = record?.mainSleep
            let slept = sessions.reduce(0) { $0 + $1.minutesAsleep }
            let napMinutes = slept - (main?.minutesAsleep ?? 0)
            let hasData = main != nil && slept > 0

            let previousStrain = strainByDay[DayKey.addDays(key, -1)] ?? 0
            let strainBoost = Stats.clamp((previousStrain - 8) / 13, 0, 1) * config.strainNeedBoostMaxMinutes
            var need = config.baselineNeedMinutes + debt * config.debtRepayFraction + strainBoost
            need = Stats.clamp(need, config.baselineNeedMinutes - 30, config.baselineNeedMinutes + 150)

            let performance = hasData ? min(100, slept / need * 100) : 0

            if hasData {
                // Schuld wird gegen Basis + Strain-Aufschlag gebucht, NICHT
                // gegen den angezeigten Bedarf: der enthält die Schuld-
                // Rückzahlung, und daran gemessen würde die Schuld verzinst —
                // wer genau seine Basis schläft, käme nie wieder von der
                // Kappung herunter. (Whoop-Logik: zurückgezahlt ist, was ÜBER
                // der Baseline geschlafen wird.)
                let structuralNeed = config.baselineNeedMinutes + strainBoost
                let delta = min(structuralNeed - slept, config.maxDebtGainPerNightMinutes)
                debt = Stats.clamp(debt + delta, 0, config.maxDebtMinutes)
            }

            var consistency: Double?
            if let main {
                let bed = shiftedMinutes(of: main.start)
                let wake = shiftedMinutes(of: main.end)
                if !recentBedWake.isEmpty {
                    let deviations = recentBedWake.map { entry in
                        (circularDiff(entry.bed, bed) + circularDiff(entry.wake, wake)) / 2
                    }
                    let avgDev = Stats.mean(deviations)
                    consistency = Stats.clamp(100 - avgDev / 90 * 100, 0, 100)
                }
                recentBedWake.append((bed, wake))
                if recentBedWake.count > 4 {
                    recentBedWake.removeFirst()
                }
            }

            // Composite score (stage share only counts when real stages exist).
            var scoreParts: [(weight: Double, value: Double)] = []
            if hasData {
                scoreParts.append((0.5, min(1, slept / need)))
                if let eff = main?.efficiency {
                    scoreParts.append((0.2, Stats.clamp((eff - 70) / 25, 0, 1)))
                }
                if let stages = main?.stageMinutes {
                    let asleepStages = (stages[.light] ?? 0) + (stages[.deep] ?? 0) + (stages[.rem] ?? 0)
                    if asleepStages > 0 {
                        let restorative = ((stages[.deep] ?? 0) + (stages[.rem] ?? 0)) / asleepStages
                        scoreParts.append((0.2, min(1, restorative / 0.40)))
                    }
                }
                if let consistency { scoreParts.append((0.1, consistency / 100)) }
            }
            let scoreWeight = scoreParts.reduce(0) { $0 + $1.weight }
            let sleepScore = scoreWeight > 0
                ? scoreParts.reduce(0) { $0 + $1.weight * $1.value } / scoreWeight * 100 : 0

            var stageMinutes = main?.stageMinutes ?? [:]
            if stageMinutes.isEmpty, let main {
                stageMinutes = [.light: main.minutesAsleep]
            }

            result[key] = SleepAnalysis(
                dateKey: key,
                sleptMinutes: slept,
                napMinutes: max(0, napMinutes),
                needMinutes: need,
                performance: performance,
                score: sleepScore,
                debtAfterMinutes: debt,
                consistency: consistency,
                efficiency: main?.efficiency,
                stageMinutes: stageMinutes,
                bedTime: main?.start,
                wakeTime: main?.end,
                hasData: hasData
            )
        }
        return result
    }

    /// Minuten seit 12:00 Uhr (verschoben, damit Zeiten um Mitternacht linear bleiben).
    private static func shiftedMinutes(of date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        return (minutes + 720).truncatingRemainder(dividingBy: 1440)
    }

    private static func circularDiff(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b)
        return min(diff, 1440 - diff)
    }
}
