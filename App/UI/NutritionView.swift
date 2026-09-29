import SwiftUI
import PhotosUI

// MARK: - Nutrition tab

struct NutritionView: View {
    @Environment(AppModel.self) private var model
    @State private var dayKey = DayKey.today()
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        dayHeader
                        summaryCard
                        macroCard
                        balanceCard
                        ForEach(MealType.allCases) { meal in
                            mealCard(meal)
                        }
                        goalCard
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.nutritionAmber)
                    }
                    .accessibilityLabel("Add food")
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFoodSheet(dayKey: dayKey)
            }
        }
    }

    // MARK: Header

    private var dayHeader: some View {
        HStack {
            Button { dayKey = DayKey.addDays(dayKey, -1) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            Spacer()
            Text(Fmt.dayTitle(dayKey))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { dayKey = DayKey.addDays(dayKey, 1) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .disabled(dayKey >= DayKey.today())
        }
        .foregroundStyle(Theme.textSecondary)
    }

    // MARK: Cards

    private var summaryCard: some View {
        let totals = model.nutritionTotals(for: dayKey)
        let target = model.nutritionTargets
        let remaining = target.calories - totals.calories
        return SectionCard("Calories") {
            HStack(spacing: 20) {
                RingGauge(
                    progress: totals.calories / max(target.calories, 1),
                    color: totals.calories > target.calories * 1.1 ? Theme.orange : Theme.nutritionAmber,
                    lineWidth: 12
                ) {
                    VStack(spacing: 0) {
                        Text("\(Int(totals.calories.rounded()))")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text("kcal")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 10) {
                    StatCell(label: "Target", value: "\(Int(target.calories.rounded())) kcal")
                    StatCell(
                        label: remaining >= 0 ? "Remaining" : "Over target",
                        value: "\(Int(abs(remaining).rounded())) kcal",
                        color: remaining >= 0 ? Theme.textPrimary : Theme.orange
                    )
                }
            }
            Text("Goal: \(model.nutritionGoal.label.lowercased()) · based on \(target.basis).")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var macroCard: some View {
        let totals = model.nutritionTotals(for: dayKey)
        let target = model.nutritionTargets
        return SectionCard("Macros") {
            VStack(spacing: 14) {
                MacroBar(label: "Protein", value: totals.proteinG, target: target.proteinG, color: Theme.strainBlue)
                MacroBar(label: "Carbs", value: totals.carbsG, target: target.carbsG, color: Theme.nutritionAmber)
                MacroBar(label: "Fat", value: totals.fatG, target: target.fatG, color: Theme.stressPink)
                MacroBar(label: "Fiber", value: totals.fiberG, target: target.fiberG, color: Theme.green)
            }
        }
    }

    @ViewBuilder
    private var balanceCard: some View {
        let totals = model.nutritionTotals(for: dayKey)
        let burn = model.record(for: dayKey)?.caloriesOut
        if let burn, totals.calories > 0 {
            let balance = totals.calories - burn
            SectionCard("Energy balance") {
                HStack {
                    StatCell(label: "Eaten", value: "\(Int(totals.calories.rounded()))")
                    StatCell(label: "Burned (Fitbit)", value: "\(Int(burn.rounded()))")
                    StatCell(
                        label: balance >= 0 ? "Surplus" : "Deficit",
                        value: "\(Int(abs(balance).rounded()))",
                        color: balance >= 0 ? Theme.orange : Theme.green
                    )
                }
            }
        }
    }

    private func mealCard(_ meal: MealType) -> some View {
        let entries = model.foods(for: dayKey).filter { $0.meal == meal }
        let kcal = entries.reduce(0) { $0 + $1.calories }
        return SectionCard {
            HStack {
                Image(systemName: meal.symbol).foregroundStyle(Theme.nutritionAmber)
                Text(meal.label)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(kcal.rounded())) kcal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            if entries.isEmpty {
                Text("Nothing logged")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(entry.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.textPrimary)
                                    if entry.source == "ai" {
                                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(Theme.teal)
                                    }
                                }
                                Text("P \(Int(entry.proteinG.rounded())) · C \(Int(entry.carbsG.rounded())) · F \(Int(entry.fatG.rounded())) g")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text("\(Int(entry.calories.rounded()))")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Button(role: .destructive) {
                                model.removeFood(id: entry.id)
                            } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityLabel("Delete \(entry.name)")
                        }
                    }
                }
            }
        }
    }

    private var goalCard: some View {
        @Bindable var model = model
        return SectionCard("Goal") {
            Picker("Goal", selection: $model.nutritionGoal) {
                ForEach(NutritionGoal.allCases) { goal in
                    Text(goal.label).tag(goal)
                }
            }
            .pickerStyle(.segmented)
            Text("Calories come from your Fitbit's measured burn (or BMR × 1.4 when unavailable), adjusted for the goal. Protein follows sports-nutrition guidance (1.6–2.0 g/kg); fat is 27 % of energy; carbs fill the rest. Update height and weight under More.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Macro bar

struct MacroBar: View {
    let label: String
    let value: Double
    let target: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(target.rounded())) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.16))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(min(1, value / max(target, 1)))))
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Add food

struct AddFoodSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dayKey: String

    @State private var meal = MealType.suggested()
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""

    @State private var aiText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var estimating = false
    @State private var aiError: String?
    @State private var aiNote: String?
    @State private var usedAI = false

    private func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (number(calories) ?? -1) >= 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Meal", selection: $meal) {
                        ForEach(MealType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    aiCard
                    manualCard
                    recentCard
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoData = Self.downscaledJPEG(data)
                }
            }
        }
    }

    // MARK: AI estimate

    private var aiCard: some View {
        SectionCard("Describe or snap it (AI)") {
            TextField("e.g. two eggs, toast with butter and a banana", text: $aiText, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardElevated))
                .foregroundStyle(Theme.textPrimary)

            HStack {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(photoData == nil ? "Add photo" : "Photo added", systemImage: photoData == nil ? "camera" : "checkmark.circle.fill")
                        .font(.subheadline)
                }
                .foregroundStyle(photoData == nil ? Theme.textSecondary : Theme.green)
                Spacer()
                Button {
                    Task { await estimate() }
                } label: {
                    HStack(spacing: 6) {
                        if estimating { ProgressView().tint(.black) }
                        Text(estimating ? "Estimating…" : "Estimate")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Theme.nutritionAmber))
                    .foregroundStyle(Color.black)
                }
                .disabled(estimating || (aiText.trimmingCharacters(in: .whitespaces).isEmpty && photoData == nil))
            }

            if !model.coachReady {
                Text("\(model.coachStatus) Set it up under More → AI Coach.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if model.coachEngine == .claude {
                Text("The description and photo are sent to Anthropic to estimate the nutrition.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let aiError {
                Text(aiError).font(.caption).foregroundStyle(Theme.red)
            }
            if let aiNote {
                Text(aiNote).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Manual entry

    private var manualCard: some View {
        SectionCard("Details") {
            field("Name", text: $name, keyboard: .default)
            HStack(spacing: 10) {
                field("kcal", text: $calories, keyboard: .decimalPad)
                field("Protein g", text: $protein, keyboard: .decimalPad)
            }
            HStack(spacing: 10) {
                field("Carbs g", text: $carbs, keyboard: .decimalPad)
                field("Fat g", text: $fat, keyboard: .decimalPad)
                field("Fiber g", text: $fiber, keyboard: .decimalPad)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(Theme.textSecondary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardElevated))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private var recentCard: some View {
        let recents = model.nutrition.recentFoods()
        if !recents.isEmpty {
            SectionCard("Recent") {
                ForEach(recents) { food in
                    Button {
                        name = food.name
                        calories = "\(Int(food.calories))"
                        protein = "\(Int(food.proteinG))"
                        carbs = "\(Int(food.carbsG))"
                        fat = "\(Int(food.fatG))"
                        fiber = food.fiberG.map { "\(Int($0))" } ?? ""
                    } label: {
                        HStack {
                            Text(food.name).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(Int(food.calories)) kcal").foregroundStyle(Theme.textSecondary)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Actions

    private func estimate() async {
        aiError = nil
        aiNote = nil
        estimating = true
        defer { estimating = false }
        do {
            let result = try await model.estimateMeal(
                description: aiText.trimmingCharacters(in: .whitespacesAndNewlines),
                imageJPEG: photoData
            )
            name = result.name
            calories = "\(Int(result.calories.rounded()))"
            protein = "\(Int(result.proteinG.rounded()))"
            carbs = "\(Int(result.carbsG.rounded()))"
            fat = "\(Int(result.fatG.rounded()))"
            fiber = result.fiberG.map { "\(Int($0.rounded()))" } ?? ""
            aiNote = result.note
            usedAI = true
        } catch {
            aiError = error.localizedDescription
        }
    }

    private func save() {
        guard let kcal = number(calories) else { return }
        model.addFood(FoodEntry(
            date: dayKey,
            time: dayKey == DayKey.today() ? Date() : (DayKey.date(from: dayKey) ?? Date()).addingTimeInterval(12 * 3600),
            meal: meal,
            name: name.trimmingCharacters(in: .whitespaces),
            calories: kcal,
            proteinG: number(protein) ?? 0,
            carbsG: number(carbs) ?? 0,
            fatG: number(fat) ?? 0,
            fiberG: number(fiber),
            source: usedAI ? "ai" : "manual"
        ))
        dismiss()
    }

    /// Shrinks a photo to ≤ 1024 px on the long edge as JPEG (small, fast, cheap to send).
    static func downscaledJPEG(_ data: Data, maxEdge: CGFloat = 1024) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxEdge / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
