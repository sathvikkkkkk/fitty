import Foundation

public enum MealType: String, Codable, CaseIterable, Sendable, Identifiable {
    case breakfast, lunch, dinner, snack

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snack: return "Snack"
        }
    }

    public var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "carrot.fill"
        }
    }

    /// Sensible default meal for the current time of day.
    public static func suggested(at date: Date = Date()) -> MealType {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 17..<22: return .dinner
        default: return .snack
        }
    }
}

public struct FoodEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: String          // "yyyy-MM-dd"
    public var time: Date
    public var meal: MealType
    public var name: String
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double?
    /// "manual" or "ai" (estimated by the coach model from text/photo).
    public var source: String

    public init(
        id: UUID = UUID(), date: String, time: Date = Date(), meal: MealType, name: String,
        calories: Double, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
        fiberG: Double? = nil, source: String = "manual"
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.meal = meal
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.source = source
    }
}

public struct NutritionTotals: Sendable {
    public var calories = 0.0
    public var proteinG = 0.0
    public var carbsG = 0.0
    public var fatG = 0.0
    public var fiberG = 0.0

    public init() {}

    public init(_ entries: [FoodEntry]) {
        for e in entries {
            calories += e.calories
            proteinG += e.proteinG
            carbsG += e.carbsG
            fatG += e.fatG
            fiberG += e.fiberG ?? 0
        }
    }
}

public enum NutritionGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case lose, maintain, gain

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .lose: return "Lose fat"
        case .maintain: return "Maintain"
        case .gain: return "Build muscle"
        }
    }

    /// Energy adjustment relative to maintenance.
    var calorieFactor: Double {
        switch self {
        case .lose: return 0.85
        case .maintain: return 1.0
        case .gain: return 1.10
        }
    }

    /// Protein target in g per kg body weight (ISSN position stand: 1.4–2.0 g/kg;
    /// the upper end when in a deficit to protect lean mass).
    var proteinPerKg: Double {
        switch self {
        case .lose: return 2.0
        case .maintain: return 1.6
        case .gain: return 1.8
        }
    }
}

public struct NutritionTargets: Sendable {
    public let calories: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let fiberG: Double
    /// Maintenance energy the calorie target is based on, and where it came from.
    public let maintenance: Double
    public let basis: String
}

public enum NutritionEngine {
    /// Resting energy expenditure — Mifflin-St Jeor (1990), the most accurate
    /// predictive equation for non-obese adults (ADA evidence review).
    public static func bmr(sex: BiologicalSex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78
        }
    }

    /// Daily targets. Maintenance energy prefers the **measured** average of the last
    /// days' total-calorie burn from the Fitbit; otherwise BMR × 1.4 (lightly active).
    public static func targets(
        sex: BiologicalSex,
        weightKg: Double,
        heightCm: Double,
        age: Int,
        goal: NutritionGoal,
        recentCaloriesOut: [Double]
    ) -> NutritionTargets {
        let bmr = bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age)
        let usable = recentCaloriesOut.filter { $0 > bmr * 0.9 && $0 < 6000 }
        let maintenance: Double
        let basis: String
        if usable.count >= 3 {
            maintenance = Stats.mean(usable)
            basis = "your Fitbit's average burn (\(usable.count) days)"
        } else {
            maintenance = bmr * 1.4
            basis = "estimated from BMR × 1.4"
        }
        let calories = max(1200, maintenance * goal.calorieFactor)
        let protein = goal.proteinPerKg * weightKg
        let fat = calories * 0.27 / 9
        let carbs = max(0, (calories - protein * 4 - fat * 9) / 4)
        return NutritionTargets(
            calories: calories, proteinG: protein, carbsG: carbs, fatG: fat,
            fiberG: calories / 1000 * 14, // 14 g per 1000 kcal (Dietary Guidelines)
            maintenance: maintenance, basis: basis
        )
    }
}

/// JSON-backed food log.
public final class NutritionStore {
    public private(set) var entries: [FoodEntry] = []
    private let fileURL: URL

    public init(directory: URL, filename: String = "nutrition.json") {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([FoodEntry].self, from: data)) ?? []
    }

    @discardableResult
    public func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }

    public func entries(for day: String) -> [FoodEntry] {
        entries.filter { $0.date == day }.sorted { $0.time < $1.time }
    }

    public func add(_ entry: FoodEntry) {
        entries.append(entry)
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public func wipe() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Distinct recent foods for one-tap re-logging.
    public func recentFoods(limit: Int = 12) -> [FoodEntry] {
        var seen = Set<String>()
        var result: [FoodEntry] = []
        for entry in entries.sorted(by: { $0.time > $1.time }) {
            let key = entry.name.lowercased()
            if seen.insert(key).inserted {
                result.append(entry)
                if result.count == limit { break }
            }
        }
        return result
    }
}
