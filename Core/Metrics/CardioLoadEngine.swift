import Foundation

public enum CardioLoadStatus: String, Sendable {
    case building     // not enough history yet
    case detraining   // ratio < 0.8
    case optimal      // 0.8 – 1.3
    case high         // 1.3 – 1.5
    case veryHigh     // > 1.5

    public var label: String {
        switch self {
        case .building: return "Building baseline"
        case .detraining: return "Low – room to do more"
        case .optimal: return "Optimal"
        case .high: return "High"
        case .veryHigh: return "Very high – ease off"
        }
    }
}

public struct CardioLoadResult: Sendable {
    public let dateKey: String
    /// Today's cardio load (Banister TRIMP, same unit as `StrainResult.rawLoad`).
    public let load: Double
    /// 7-day and 28-day exponentially weighted load.
    public let acute: Double
    public let chronic: Double
    /// Acute : chronic workload ratio; nil until ≥ 14 days of history exist.
    public let ratio: Double?
    public let status: CardioLoadStatus
    /// Sum of the last 7 days and the optimal weekly range derived from the chronic load.
    public let weeklyLoad: Double
    public let optimalWeeklyRange: ClosedRange<Double>?
}

/// Cardio load and workload ratio (Gabbett, *Br J Sports Med* 2016; EWMA variant from
/// Williams et al., *Br J Sports Med* 2017). The "sweet spot" is an acute:chronic
/// ratio of about 0.8–1.3; sustained values above ~1.5 are associated with a higher
/// injury / overreaching risk. Days without data count as zero load (rest).
public enum CardioLoadEngine {
    public static let acuteDays = 7.0
    public static let chronicDays = 28.0
    public static let minHistoryDays = 14

    public static func status(forRatio ratio: Double?) -> CardioLoadStatus {
        guard let ratio else { return .building }
        switch ratio {
        case ..<0.8: return .detraining
        case ..<1.3: return .optimal
        case ..<1.5: return .high
        default: return .veryHigh
        }
    }

    /// `loads` maps "yyyy-MM-dd" → the day's load.
    public static func compute(loads: [String: Double]) -> [String: CardioLoadResult] {
        let keys = loads.keys.sorted()
        guard let first = keys.first, let last = keys.last else { return [:] }

        let lambdaA = 2 / (acuteDays + 1)
        let lambdaC = 2 / (chronicDays + 1)
        var acute = 0.0
        var chronic = 0.0
        var window: [Double] = []
        var result: [String: CardioLoadResult] = [:]
        var dayIndex = 0

        for key in DayKey.keys(from: first, to: last) {
            let load = loads[key] ?? 0
            if dayIndex == 0 {
                acute = load
                chronic = load
            } else {
                acute = lambdaA * load + (1 - lambdaA) * acute
                chronic = lambdaC * load + (1 - lambdaC) * chronic
            }
            window.append(load)
            if window.count > 7 { window.removeFirst() }
            dayIndex += 1

            let ratio: Double? = (dayIndex >= minHistoryDays && chronic > 1) ? acute / chronic : nil
            let range: ClosedRange<Double>? = dayIndex >= minHistoryDays && chronic > 1
                ? (chronic * 7 * 0.8)...(chronic * 7 * 1.3) : nil
            result[key] = CardioLoadResult(
                dateKey: key,
                load: load,
                acute: acute,
                chronic: chronic,
                ratio: ratio,
                status: status(forRatio: ratio),
                weeklyLoad: window.reduce(0, +),
                optimalWeeklyRange: range
            )
        }
        return result
    }
}
