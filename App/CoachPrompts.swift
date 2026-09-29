import Foundation

// MARK: - Intent

/// What the user is asking about. Each intent adds a task template (a fixed output format) to
/// the prompt — small on-device models follow a concrete format far better than open-ended rules.
enum CoachIntent: CaseIterable {
    case workout, meal, sleep, recovery

    private var keywords: [String] {
        switch self {
        case .workout:
            return ["workout", "exercise", "train", "lift", "gym", "push", "pull", "legs", "leg day", "run",
                    "cardio", "hiit", "strength", "routine", "session", "reps", "sets"]
        case .meal:
            return ["meal", "eat", "diet", "food", "breakfast", "lunch", "dinner", "snack", "protein",
                    "calorie", "macro", "recipe", "nutrition", "hungry"]
        case .sleep:
            return ["sleep", "bed", "nap", "insomnia", "tired at night", "wake"]
        case .recovery:
            return ["recovery", "hrv", "resting heart", "stress", "tired", "fatigue", "sore", "overtrain",
                    "readiness", "rest day", "strain"]
        }
    }

    /// Intents mentioned in `text` (a message can ask for several, e.g. "meal plan and a push workout").
    static func detect(in text: String) -> [CoachIntent] {
        let lower = text.lowercased()
        return allCases.filter { intent in intent.keywords.contains { lower.contains($0) } }
    }
}

// MARK: - Templates

enum CoachTemplates {
    static let rules = """
    ## Rules
    - The FACTS section is computed by the app from the user's Fitbit data. Treat it as true and quote its numbers. Never invent numbers, dates or measurements that are not in FACTS or RECENT DAYS.
    - You MAY use general fitness and nutrition knowledge for the content of answers (exercises, foods, technique, sets and reps). Use the FACTS to decide how hard or how much.
    - Interpretation guide: day strain under 6 = light, 6-10 = moderate, 10-14 = hard, over 14 = very hard. Training spends recovery; it never raises today's recovery score. Recovery green (67+) = ready for hard work, yellow (34-66) = moderate work, red (under 34) = rest or very light activity.
    - Scores are wearable estimates, not medical advice. Never diagnose. For chest pain, fainting or worrying symptoms say to see a doctor.
    - Answer only the user's latest question. Do not repeat earlier answers. Be concise and specific.
    """

    static let workout = """
    ## Task: workout
    Write ONE workout for today. Pick the intensity and volume from FACTS ("Training guidance"). Use general training knowledge for the exercises.
    "Push" workout = a push day: chest, shoulders, triceps. "Pull" = back and biceps. "Legs" = quads, hamstrings, glutes, calves. "Full body" = a mix. If the user names no split, choose one that fits the recent workouts.
    If the guidance says recovery day, give a light session instead and say why in one sentence.
    Use EXACTLY this format:
    **Focus:** <split and intensity>
    **Warm-up:** <two short items>
    **Main sets:**
    - <Exercise> — <sets> x <reps> — <rest>
    (5 or 6 lines, compound lifts first)
    **Finish:** <one line>
    **Why today:** <one sentence using the user's recovery and strain numbers>
    Example of the style:
    **Focus:** Push day (chest, shoulders, triceps) — moderate volume
    **Warm-up:** 5 min easy cardio; 2 light sets of push-ups
    **Main sets:**
    - Barbell bench press — 4 x 6-8 — 2 min
    - Seated dumbbell shoulder press — 3 x 8-10 — 90 s
    - Incline dumbbell press — 3 x 10 — 90 s
    - Cable lateral raise — 3 x 12-15 — 60 s
    - Triceps rope pushdown — 3 x 10-12 — 60 s
    **Finish:** 5 min walk and chest/shoulder stretch
    **Why today:** Recovery <X>% (<zone>) and only <Y> strain so far, so a <intensity> push session fits.
    (In the example, <X>, <Y>, <zone> and <intensity> are placeholders: always use the user's real numbers from FACTS.)
    """

    static let meal = """
    ## Task: meal plan
    Plan the REST of today's meals so the totals land close to "Still to eat today" in FACTS. Never go over the remaining calories. Favour whole foods and protein; respect the user's goal.
    Use EXACTLY this format, one line per meal:
    **<Meal>** — <foods with portions> — ~<kcal> kcal, <P> g protein
    then a last line:
    **Total:** <kcal> kcal · <P> g protein · <C> g carbs · <F> g fat
    Make the meal lines add up to the Total. If little or nothing remains, say so and suggest a light snack instead.
    """

    static let sleep = """
    ## Task: sleep
    Give 3 short, concrete tips for tonight. Mention the recommended bedtime and the sleep debt from FACTS. Do not exceed 90 words.
    """

    static let recovery = """
    ## Task: recovery / stress
    Explain in 2-3 sentences what the user's recovery, HRV, resting heart rate and stress in FACTS suggest, then give 2 practical actions for today.
    """

    static func templates(for intents: [CoachIntent]) -> String {
        var parts: [String] = []
        for intent in intents.prefix(2) {
            switch intent {
            case .workout: parts.append(workout)
            case .meal: parts.append(meal)
            case .sleep: parts.append(sleep)
            case .recovery: parts.append(recovery)
            }
        }
        if parts.isEmpty {
            parts.append("""
            ## Task: general question
            Answer in at most 120 words. Quote 2-3 numbers from FACTS or RECENT DAYS. End with one practical next step.
            """)
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Facts computed by the app

extension AppModel {
    /// Conclusions the app can compute exactly — so the model phrases them instead of reasoning
    /// over raw numbers (which small models do badly).
    func coachFacts() -> String {
        let today = DayKey.today()
        var lines: [String] = []

        // Recovery → training guidance
        if let recovery = recoveryResults[today] ?? recoveryResults.keys.sorted().last.flatMap({ recoveryResults[$0] }) {
            let target = StrainEngine.targetStrain(forRecovery: recovery.score)
            let guidance: String
            switch recovery.zone {
            case .green:
                guidance = String(format: "GREEN — hard training is fine. Aim for a day strain of about %.0f-%.0f (target %.1f).", max(target - 3, 8), target, target)
            case .yellow:
                guidance = String(format: "YELLOW — moderate training only (day strain about 8-12, target %.1f). No maximal efforts.", target)
            case .red:
                guidance = "RED — recovery day. Light movement only (walking, mobility, easy cycling), day strain under 8."
            }
            lines.append("Recovery today: \(recovery.score)% → Training guidance: \(guidance)")
        } else {
            lines.append("Recovery today: not available yet (no synced overnight data). Suggest a moderate session.")
        }

        // Strain so far
        if let strain = strainResults[today] {
            var text = String(format: "Strain so far today: %.1f / 21", strain.strain)
            if let recovery = recoveryResults[today] {
                let target = StrainEngine.targetStrain(forRecovery: recovery.score)
                text += String(format: " (target %.1f, %.1f left to reach it)", target, max(0, target - strain.strain))
            }
            lines.append(text)
        }

        // Sleep
        if let last = sleepAnalyses.keys.sorted().last(where: { sleepAnalyses[$0]?.hasData == true }), let s = sleepAnalyses[last] {
            lines.append(String(format: "Last night's sleep: %@ h (score %.0f, performance %.0f%%). Sleep debt: %@ h.",
                                Fmt.hm(s.sleptMinutes), s.score, s.performance, Fmt.hm(s.debtAfterMinutes)))
        }
        if let bed = bedtimeTonight?.recommendedBedtimeMinutes {
            lines.append("Recommended bedtime tonight: \(Fmt.clockFromMinutes(bed)).")
        }

        // Stress and load
        if let stress = stressResults[today] {
            lines.append(String(format: "Stress today: %.0f/100 (%@).", stress.score, stress.level.label.lowercased()))
        }
        if let load = cardioLoads[today], load.ratio != nil {
            lines.append("Cardio load status: \(load.status.label).")
        }

        // Nutrition: what is left to eat today
        let target = nutritionTargets
        let eaten = nutritionTotals(for: today)
        lines.append(String(format: "Daily targets (%@): %.0f kcal, %.0f g protein, %.0f g carbs, %.0f g fat.",
                            nutritionGoal.label.lowercased(), target.calories, target.proteinG, target.carbsG, target.fatG))
        lines.append(String(format: "Eaten so far today: %.0f kcal, %.0f g protein, %.0f g carbs, %.0f g fat.",
                            eaten.calories, eaten.proteinG, eaten.carbsG, eaten.fatG))
        lines.append(String(format: "Still to eat today: %.0f kcal, %.0f g protein, %.0f g carbs, %.0f g fat.",
                            max(0, target.calories - eaten.calories), max(0, target.proteinG - eaten.proteinG),
                            max(0, target.carbsG - eaten.carbsG), max(0, target.fatG - eaten.fatG)))

        // Recent training (recorded + logged)
        var recent: [String] = []
        for offset in 0..<7 {
            let key = DayKey.addDays(today, -offset)
            let recorded = (store.days[key]?.workouts ?? []).map { "\($0.name) \(Int($0.durationMinutes.rounded())) min" }
            let logged = loggedWorkouts.filter { $0.date == key }.map { "\($0.kind.label) \(Int($0.durationMinutes.rounded())) min RPE \($0.rpe)" }
            let all = recorded + logged
            if !all.isEmpty { recent.append("\(offset == 0 ? "today" : "\(offset)d ago"): " + all.joined(separator: ", ")) }
        }
        lines.append("Workouts in the last 7 days: " + (recent.isEmpty ? "none" : recent.joined(separator: "; ")) + ".")

        return "## FACTS (computed by the app)\n" + lines.map { "- " + $0 }.joined(separator: "\n")
    }
}
