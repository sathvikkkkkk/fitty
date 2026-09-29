import SwiftUI
import Charts

// MARK: - Fitness tab

struct FitnessView: View {
    @Environment(AppModel.self) private var model
    @State private var showLog = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        DayChips()
                        StressCard()
                        CardioLoadCard()
                        activityCard
                        workoutsCard
                        strengthCard
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Fitness")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLog = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.strainBlue)
                    }
                    .accessibilityLabel("Log workout")
                }
            }
            .sheet(isPresented: $showLog) {
                WorkoutLogSheet(dayKey: model.selectedDayKey)
            }
        }
    }

    // MARK: Daily activity totals from the Fitbit

    @ViewBuilder
    private var activityCard: some View {
        let record = model.selectedRecord
        SectionCard("Activity") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                StatCell(label: "Steps", value: record?.steps.map { $0.formatted() } ?? "–")
                StatCell(label: "Distance", value: record?.distanceMeters.map { String(format: "%.1f km", $0 / 1000) } ?? "–")
                StatCell(label: "Floors", value: record?.floors.map { String(format: "%.0f", $0) } ?? "–")
                StatCell(label: "Active zone min", value: record?.activeZoneMinutes.map { String(format: "%.0f", $0) } ?? "–")
                StatCell(label: "Energy burned", value: record?.caloriesOut.map { String(format: "%.0f kcal", $0) } ?? "–")
                StatCell(label: "VO₂max", value: record?.vo2max.map { String(format: "%.0f", $0) } ?? "–")
            }
        }
    }

    // MARK: Workouts (watch + logged)

    private var workoutsCard: some View {
        let key = model.selectedDayKey
        let recorded = model.record(for: key)?.workouts ?? []
        let logged = model.loggedWorkouts.filter { $0.date == key }
        return SectionCard("Workouts") {
            if recorded.isEmpty && logged.isEmpty {
                Text("No workouts on this day. Tap + to log one — even without a watch, it counts towards strain and cardio load.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(recorded, id: \.id) { workout in
                HStack(spacing: 12) {
                    Image(systemName: "applewatch").foregroundStyle(Theme.strainBlue).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        Text("\(Int(workout.durationMinutes.rounded())) min" + (workout.averageHR.map { " · avg \(Int($0.rounded())) bpm" } ?? ""))
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let strain = workout.strain {
                        PillBadge(text: String(format: "%.1f", strain), color: Theme.strainBlue)
                    }
                }
            }
            ForEach(logged) { workout in
                HStack(spacing: 12) {
                    Image(systemName: workout.kind.symbol).foregroundStyle(Theme.orange).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.kind.label).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        Text(detail(workout)).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        model.removeWorkout(id: workout.id)
                    } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Delete workout")
                }
            }
        }
    }

    private func detail(_ w: LoggedWorkout) -> String {
        var parts = ["\(Int(w.durationMinutes.rounded())) min", "RPE \(w.rpe)"]
        if w.totalSets > 0 {
            parts.append("\(w.totalSets) sets · \(Int(w.totalVolumeKg.rounded())) kg volume")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Strength progress

    @ViewBuilder
    private var strengthCard: some View {
        let bests = model.workoutLog.personalBests().sorted { $0.value > $1.value }
        if !bests.isEmpty {
            SectionCard("Strength — estimated 1RM") {
                ForEach(bests.prefix(6), id: \.key) { name, orm in
                    HStack {
                        Text(name.capitalized).font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(String(format: "%.1f kg", orm))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                Text("Epley estimate from your best set (≤ 12 reps).")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Stress

struct StressCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let result = model.stressResults[model.selectedDayKey]
        SectionCard("Stress") {
            if let result {
                HStack(alignment: .center, spacing: 20) {
                    RingGauge(progress: result.score / 100, color: color(result.level), lineWidth: 11) {
                        VStack(spacing: 0) {
                            Text("\(Int(result.score.rounded()))")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Text(String(format: "%.1f / 3", result.scale3))
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: 8) {
                        PillBadge(text: result.level.label, color: color(result.level))
                        if let elevation = result.daytimeElevationBpm {
                            Text(String(format: "Daytime HR %+.0f bpm vs resting", elevation))
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Text(advice(result.level))
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }

                if result.hourly.contains(where: { $0 != nil }) {
                    Chart {
                        ForEach(0..<24, id: \.self) { hour in
                            if let value = result.hourly[hour] {
                                BarMark(x: .value("Hour", hour), y: .value("Stress", value))
                                    .foregroundStyle(color(StressEngine.level(for: value)))
                                    .cornerRadius(2)
                            }
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartXScale(domain: 5...23)
                    .chartXAxis {
                        AxisMarks(values: [6, 9, 12, 15, 18, 21]) { value in
                            AxisValueLabel { if let h = value.as(Int.self) { Text("\(h)h").font(.caption2) } }
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 90)
                }
                Text("Estimated from daytime heart rate and overnight HRV against your own baseline. Not a medical measurement.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: "Stress needs a day of heart-rate data (and ideally a few nights of HRV).")
            }
        }
    }

    private func color(_ level: StressLevel) -> Color {
        switch level {
        case .low: return Theme.green
        case .moderate: return Theme.yellow
        case .high: return Theme.stressPink
        }
    }

    private func advice(_ level: StressLevel) -> String {
        switch level {
        case .low: return "Your body is calm — good day to push if you're recovered."
        case .moderate: return "Typical load. A short walk or breathing break helps."
        case .high: return "Running hot. Prioritise wind-down time and sleep tonight."
        }
    }
}

// MARK: - Cardio load

struct CardioLoadCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let key = model.selectedDayKey
        let result = model.cardioLoads[key]
        SectionCard("Cardio load") {
            if let result {
                HStack(alignment: .top) {
                    StatCell(label: "Today", value: "\(Int(result.load.rounded()))")
                    StatCell(label: "7-day load", value: "\(Int(result.weeklyLoad.rounded()))")
                    StatCell(
                        label: "Ratio",
                        value: result.ratio.map { String(format: "%.2f", $0) } ?? "–",
                        color: statusColor(result.status)
                    )
                }
                PillBadge(text: result.status.label, color: statusColor(result.status))
                if let range = result.optimalWeeklyRange {
                    Text("Optimal weekly load for you: \(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded()))")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }

                let points = recentLoads(endingAt: key)
                if !points.isEmpty {
                    Chart {
                        ForEach(points, id: \.key) { point in
                            BarMark(x: .value("Day", Fmt.weekdayLetter(point.key) + Fmt.dayNumber(point.key)), y: .value("Load", point.load))
                                .foregroundStyle(point.key == key ? Theme.strainBlue : Theme.strainBlue.opacity(0.45))
                                .cornerRadius(3)
                        }
                        RuleMark(y: .value("Chronic", result.chronic))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 80)
                    Text("Dashed line: your 28-day average daily load.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Text("Ratio = 7-day vs 28-day load. 0.8–1.3 builds fitness with low injury risk; above 1.5 is a warning sign (Gabbett 2016).")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            } else {
                EmptyDataHint(text: "Cardio load appears once heart-rate or workout data has synced.")
            }
        }
    }

    private struct LoadPoint { let key: String; let load: Double }

    private func recentLoads(endingAt key: String) -> [LoadPoint] {
        DayKey.keys(from: DayKey.addDays(key, -13), to: key).map { LoadPoint(key: $0, load: model.cardioLoads[$0]?.load ?? 0) }
    }

    private func statusColor(_ status: CardioLoadStatus) -> Color {
        switch status {
        case .building: return Theme.textSecondary
        case .detraining: return Theme.strainBlue
        case .optimal: return Theme.green
        case .high: return Theme.yellow
        case .veryHigh: return Theme.red
        }
    }
}

// MARK: - Log workout

struct WorkoutLogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dayKey: String

    @State private var kind = WorkoutKind.strength
    @State private var start = Date()
    @State private var duration = 45.0
    @State private var rpe = 6.0
    @State private var avgHR = ""
    @State private var note = ""
    @State private var exercises: [StrengthExercise] = []

    private var draft: LoggedWorkout {
        LoggedWorkout(
            date: dayKey, start: start, durationMinutes: duration, kind: kind, rpe: Int(rpe),
            averageHR: Double(avgHR), calories: nil, note: note.isEmpty ? nil : note,
            exercises: exercises.filter { !$0.name.isEmpty }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    kindPicker
                    SectionCard("When & how long") {
                        DatePicker("Start", selection: $start)
                            .foregroundStyle(Theme.textPrimary)
                        Stepper(value: $duration, in: 5...300, step: 5) {
                            Text("Duration: \(Int(duration)) min").foregroundStyle(Theme.textPrimary)
                        }
                    }
                    SectionCard("Effort (RPE)") {
                        Slider(value: $rpe, in: 1...10, step: 1)
                        HStack {
                            Text("\(Int(rpe)) / 10").font(.headline).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(rpeLabel).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                        TextField("Average heart rate (optional)", text: $avgHR)
                            .keyboardType(.numberPad)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardElevated))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    if kind == .strength { strengthEditor }
                    SectionCard("Impact") {
                        Text("≈ \(Int(draft.estimatedTrimp.rounded())) cardio load · ≈ \(Int(draft.estimatedCalories(weightKg: model.weightKg).rounded())) kcal")
                            .font(.subheadline).foregroundStyle(Theme.textPrimary)
                        Text("Counted towards strain only when your watch recorded no heart rate for this time window.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Log workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var workout = draft
                        workout.calories = workout.estimatedCalories(weightKg: model.weightKg)
                        model.addWorkout(workout)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .onAppear {
            // Log onto the selected day, at a sensible time of day.
            if dayKey != DayKey.today(), let date = DayKey.date(from: dayKey) {
                start = date.addingTimeInterval(18 * 3600)
            }
        }
    }

    private var rpeLabel: String {
        switch Int(rpe) {
        case 1...2: return "Very easy"
        case 3...4: return "Easy"
        case 5...6: return "Moderate"
        case 7...8: return "Hard"
        default: return "Max effort"
        }
    }

    private var kindPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(WorkoutKind.allCases) { option in
                Button {
                    kind = option
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.symbol).font(.title3)
                        Text(option.label).font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(kind == option ? Theme.strainBlue.opacity(0.25) : Theme.cardElevated))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(kind == option ? Theme.strainBlue : .clear, lineWidth: 1))
                    .foregroundStyle(kind == option ? Theme.strainBlue : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Strength editor

    private var strengthEditor: some View {
        SectionCard("Exercises") {
            ForEach($exercises) { $exercise in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Exercise (e.g. Back squat)", text: $exercise.name)
                            .foregroundStyle(Theme.textPrimary)
                        Button(role: .destructive) {
                            exercises.removeAll { $0.id == exercise.id }
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    ForEach($exercise.sets) { $set in
                        HStack(spacing: 10) {
                            Text("Set").font(.caption).foregroundStyle(Theme.textSecondary)
                            Stepper("\(set.reps) reps", value: $set.reps, in: 1...50)
                                .font(.subheadline).foregroundStyle(Theme.textPrimary)
                            TextField("kg", value: $set.weightKg, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardElevated))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    Button {
                        let last = exercise.sets.last
                        exercise.sets.append(StrengthSet(reps: last?.reps ?? 8, weightKg: last?.weightKg ?? 20))
                    } label: {
                        Label("Add set", systemImage: "plus")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.strainBlue)
                    if let orm = exercise.bestOneRepMax {
                        Text(String(format: "Est. 1RM %.1f kg", orm)).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
                Divider().overlay(Theme.stroke)
            }
            Button {
                exercises.append(StrengthExercise(name: "", sets: [StrengthSet(reps: 8, weightKg: 20)]))
            } label: {
                Label("Add exercise", systemImage: "plus.circle")
            }
            .foregroundStyle(Theme.strainBlue)
        }
    }
}
