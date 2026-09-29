import Foundation

public enum WorkoutKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case run, walk, cycle, strength, hiit, swim, yoga, other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .run: return "Run"
        case .walk: return "Walk"
        case .cycle: return "Cycle"
        case .strength: return "Strength"
        case .hiit: return "HIIT"
        case .swim: return "Swim"
        case .yoga: return "Yoga"
        case .other: return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cycle: return "figure.outdoor.cycle"
        case .strength: return "dumbbell.fill"
        case .hiit: return "bolt.heart.fill"
        case .swim: return "figure.pool.swim"
        case .yoga: return "figure.yoga"
        case .other: return "figure.mixed.cardio"
        }
    }
}

public struct StrengthSet: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var reps: Int
    public var weightKg: Double

    public init(id: UUID = UUID(), reps: Int, weightKg: Double) {
        self.id = id
        self.reps = reps
        self.weightKg = weightKg
    }

    public var volumeKg: Double { Double(reps) * weightKg }

    /// Estimated one-rep max (Epley): w · (1 + reps/30). Only meaningful for ≤ 12 reps.
    public var estimatedOneRepMax: Double? {
        guard reps > 0, reps <= 12, weightKg > 0 else { return nil }
        return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }
}

public struct StrengthExercise: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var sets: [StrengthSet]

    public init(id: UUID = UUID(), name: String, sets: [StrengthSet] = []) {
        self.id = id
        self.name = name
        self.sets = sets
    }

    public var volumeKg: Double { sets.reduce(0) { $0 + $1.volumeKg } }
    public var bestOneRepMax: Double? { sets.compactMap { $0.estimatedOneRepMax }.max() }
}

public struct LoggedWorkout: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: String
    public var start: Date
    public var durationMinutes: Double
    public var kind: WorkoutKind
    /// Rate of perceived exertion, 1–10 (Borg CR10).
    public var rpe: Int
    public var averageHR: Double?
    public var calories: Double?
    public var note: String?
    public var exercises: [StrengthExercise]

    public init(
        id: UUID = UUID(), date: String, start: Date, durationMinutes: Double, kind: WorkoutKind,
        rpe: Int, averageHR: Double? = nil, calories: Double? = nil, note: String? = nil,
        exercises: [StrengthExercise] = []
    ) {
        self.id = id
        self.date = date
        self.start = start
        self.durationMinutes = durationMinutes
        self.kind = kind
        self.rpe = rpe
        self.averageHR = averageHR
        self.calories = calories
        self.note = note
        self.exercises = exercises
    }

    public var end: Date { start.addingTimeInterval(durationMinutes * 60) }
    public var totalVolumeKg: Double { exercises.reduce(0) { $0 + $1.volumeKg } }
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// Session-RPE load (Foster 2001): RPE × minutes, in arbitrary units.
    public var sessionLoadAU: Double { Double(rpe) * durationMinutes }

    /// Converts session-RPE load to the Banister-TRIMP scale used for strain.
    /// Calibrated so that 60 min at RPE 6 (≈ 60 % HRR) ≈ 72 TRIMP.
    public static let trimpPerAU = 0.20

    /// Cardio-load contribution used when the watch recorded no heart rate for it.
    public var estimatedTrimp: Double { sessionLoadAU * Self.trimpPerAU }

    /// Rough energy estimate via MET values (Compendium of Physical Activities).
    public func estimatedCalories(weightKg: Double) -> Double {
        let met: Double
        switch kind {
        case .run: met = 9.8
        case .walk: met = 3.8
        case .cycle: met = 7.5
        case .strength: met = 5.0
        case .hiit: met = 8.5
        case .swim: met = 7.0
        case .yoga: met = 2.8
        case .other: met = 5.0
        }
        // Scale by effort around a "typical" RPE of 6.
        let effort = Stats.clamp(Double(rpe) / 6, 0.6, 1.4)
        return met * effort * weightKg * durationMinutes / 60
    }
}

/// JSON-backed workout log.
public final class WorkoutLogStore {
    public private(set) var workouts: [LoggedWorkout] = []
    private let fileURL: URL

    public init(directory: URL, filename: String = "workouts.json") {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        workouts = (try? decoder.decode([LoggedWorkout].self, from: data)) ?? []
    }

    @discardableResult
    public func save() -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(workouts) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }

    public func workouts(for day: String) -> [LoggedWorkout] {
        workouts.filter { $0.date == day }.sorted { $0.start < $1.start }
    }

    public func add(_ workout: LoggedWorkout) {
        workouts.append(workout)
    }

    public func remove(id: UUID) {
        workouts.removeAll { $0.id == id }
    }

    public func wipe() {
        workouts = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Best estimated 1RM per exercise name across all history (for progress display).
    public func personalBests() -> [String: Double] {
        var best: [String: Double] = [:]
        for workout in workouts {
            for exercise in workout.exercises {
                guard let orm = exercise.bestOneRepMax else { continue }
                let key = exercise.name.lowercased()
                best[key] = max(best[key] ?? 0, orm)
            }
        }
        return best
    }
}
