import Foundation
import FittrCore

// Self-Test-Runner: verifiziert die Core-Logik ohne Xcode/iOS-SDK.

var failures: [String] = []

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ✓ \(message)")
    } else {
        print("  ✗ FEHLER: \(message)")
        failures.append(message)
    }
}

func section(_ name: String) {
    print("\n— \(name)")
}

func jsonDict(_ raw: String) -> [String: Any] {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let dict = object as? [String: Any] else {
        failures.append("Fixture nicht parsebar")
        return [:]
    }
    return dict
}

// MARK: PKCE (RFC-7636-Testvektor)

section("PKCE")
let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
check(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "SHA256-Challenge entspricht RFC-7636-Vektor")
let freshPKCE = PKCE()
check(freshPKCE.verifier.count >= 43, "Zufälliger Verifier hat ausreichende Länge")
check(freshPKCE.verifier != PKCE().verifier, "Verifier sind zufällig")

// MARK: OAuth-Konfiguration

section("OAuth-Konfiguration")
let config = GoogleOAuthConfig(clientID: "407408718192-abc123.apps.googleusercontent.com")
check(config.reversedClientScheme == "com.googleusercontent.apps.407408718192-abc123", "Reversed-Client-Schema korrekt")
check(config.redirectURI == "com.googleusercontent.apps.407408718192-abc123:/oauth2redirect", "Redirect-URI korrekt")
check(!GoogleOAuthConfig(clientID: "kaputt").isValid, "Ungültige Client-ID wird erkannt")

let auth = GoogleAuth(usesKeychain: false)
if let url = auth.authorizationURL(config: config, pkce: pkce, state: "test-state") {
    let absolute = url.absoluteString
    check(absolute.hasPrefix("https://accounts.google.com/o/oauth2/v2/auth"), "Auth-URL zeigt auf Google")
    check(absolute.contains("code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"), "Auth-URL enthält PKCE-Challenge")
    check(absolute.contains("googlehealth.sleep.readonly"), "Auth-URL enthält Health-Scopes")
    check(!absolute.contains("prompt="), "Kein prompt=consent (Google-Health-Empfehlung)")
} else {
    check(false, "Auth-URL konnte nicht gebaut werden")
}
let callback = URL(string: "com.googleusercontent.apps.x:/oauth2redirect?state=test-state&code=4/abc")!
check(GoogleAuth.extractCode(from: callback, expectedState: "test-state") == "4/abc", "Code-Extraktion aus Callback")
check(GoogleAuth.extractCode(from: callback, expectedState: "falsch") == nil, "State-Mismatch wird abgelehnt")
check(GoogleAuth.formEncode(["a": "b c", "x": "y+z"]) == "a=b%20c&x=y%2Bz", "Form-Encoding percent-encodiert korrekt")

// MARK: JSON-Extraktion (Google-Health-Formate)

section("JSON-Extraktion")
check(JSONExtract.snakeCase("heartRateVariability") == "heart_rate_variability", "camelCase → snake_case")

let hrPoint = jsonDict(#"""
{
  "dataSource": { "device": { "displayName": "Fitbit Air" }, "platform": "FITBIT", "recordingMethod": "DERIVED" },
  "heartRate": { "sampleTime": { "physicalTime": "2026-05-12T15:59:07Z" }, "beatsPerMinute": 72 }
}
"""#)
let hrPayload = (hrPoint["heartRate"] as? [String: Any]) ?? [:]
check(JSONExtract.firstDouble(in: hrPayload, keys: ["beatsPerMinute", "bpm"]) == 72, "Herzfrequenz-Wert extrahiert")
check(JSONExtract.firstDate(in: hrPayload, keys: ["physicalTime"]) != nil, "Sample-Zeit extrahiert (verschachtelt)")

let civil = JSONExtract.civilDateString(from: ["year": 2026, "month": 7, "day": 5])
check(civil == "2026-07-05", "CivilDate-Objekt → yyyy-MM-dd")

let sleepPoint = jsonDict(#"""
{
  "name": "users/me/dataTypes/sleep/dataPoints/abc",
  "sleep": {
    "type": "STAGES",
    "interval": { "startTime": "2026-07-16T22:45:00Z", "endTime": "2026-07-17T06:30:00Z" },
    "stages": [
      { "type": "LIGHT", "startTime": "2026-07-16T22:45:00Z", "endTime": "2026-07-17T00:10:00Z" },
      { "type": "DEEP", "startTime": "2026-07-17T00:10:00Z", "endTime": "2026-07-17T01:20:00Z" },
      { "type": "REM", "startTime": "2026-07-17T01:20:00Z", "endTime": "2026-07-17T02:00:00Z" },
      { "type": "AWAKE", "startTime": "2026-07-17T02:00:00Z", "endTime": "2026-07-17T02:08:00Z" },
      { "type": "LIGHT", "startTime": "2026-07-17T02:08:00Z", "endTime": "2026-07-17T06:30:00Z" }
    ],
    "summary": { "minutesAsleep": 457, "minutesAwake": 8, "stagesSummary": [ { "type": "DEEP", "minutes": 70 } ] }
  }
}
"""#)
if let session = HealthAPIClient.parseSleep(sleepPoint) {
    check(session.stages.count == 5, "5 Schlafphasen dekodiert")
    check(session.minutesAsleep == 457, "minutesAsleep aus Summary übernommen")
    check(session.stages[1].stage == .deep, "DEEP → .deep gemappt")
    check(abs(session.minutesInBed - 465) < 0.01, "Zeit im Bett = 465 min")
} else {
    check(false, "Schlaf-Fixture konnte nicht dekodiert werden")
}
check(HealthAPIClient.parseSleep(["sleep": ["interval": [:]]]) == nil, "Unvollständige Schlafdaten → nil statt Absturz")

// Exercise: Google nennt das Zeitintervall "interval" (Filter interval.civil_start_time).
let exercisePoint = jsonDict(#"""
{
  "name": "users/me/dataTypes/exercise/dataPoints/xyz",
  "exercise": {
    "exerciseType": "RUNNING",
    "activityName": "Laufen",
    "interval": { "startTime": "2026-07-17T17:30:00Z", "endTime": "2026-07-17T18:15:00Z" },
    "averageHeartRate": 148,
    "calories": 430
  }
}
"""#)
if let workout = HealthAPIClient.parseExercise(exercisePoint) {
    check(workout.name == "Laufen", "Workout-Name aus activityName")
    check(abs(workout.durationMinutes - 45) < 0.01, "Workout-Dauer aus interval = 45 min")
    check(workout.averageHR == 148, "Ø-Puls des Workouts dekodiert")
} else {
    check(false, "Exercise-Fixture mit interval konnte nicht dekodiert werden")
}
// Ältere/alternative Struktur "sessionTimeInterval" bleibt als Fallback lesbar.
let exerciseAlt = jsonDict(#"""
{ "exercise": { "activityName": "Rad", "sessionTimeInterval": { "startTime": "2026-07-17T08:00:00Z", "endTime": "2026-07-17T08:30:00Z" } } }
"""#)
check(HealthAPIClient.parseExercise(exerciseAlt)?.name == "Rad", "Fallback sessionTimeInterval bleibt lesbar")
check(HealthAPIClient.parseExercise(["exercise": ["interval": [:]]]) == nil, "Unvollständiges Workout → nil statt Absturz")

// MARK: DayKey

section("DayKey")
check(DayKey.addDays("2026-07-18", -1) == "2026-07-17", "addDays über Tagesgrenze")
check(DayKey.keys(from: "2026-02-27", to: "2026-03-02").count == 4, "Schaltjahr-Bereich (2026 kein Schaltjahr): 27.2.–2.3. = 4 Tage")
check(DayKey.distance(from: "2026-07-01", to: "2026-07-18") == 17, "Distanz zwischen Keys")
if let lateEvening = DayKey.date(from: "2026-07-17")?.addingTimeInterval(23 * 3600) {
    check(DayKey.nightKey(for: lateEvening) == "2026-07-18", "23-Uhr-Sample zählt zur Nacht des Folgetags")
}
if let earlyMorning = DayKey.date(from: "2026-07-18")?.addingTimeInterval(5 * 3600) {
    check(DayKey.nightKey(for: earlyMorning) == "2026-07-18", "5-Uhr-Sample zählt zum selben Tag")
}

// MARK: Statistik

section("Statistik")
check(Stats.percentile([1, 2, 3, 4, 5], 0.5) == 3, "Median")
check(Stats.percentile([10], 0.05) == 10, "Perzentil mit einem Wert")
check(abs(Stats.logistic(0) - 0.5) < 1e-9, "Logistic(0) = 0.5")
if let baseline = Stats.baseline([60, 62, 64, 66, 68]) {
    check(abs(baseline.mean - 64) < 1e-9, "Baseline-Mittelwert")
    check(baseline.isReliable, "5 Werte gelten als belastbar")
    check(abs(baseline.z(64)) < 1e-9, "z-Score am Mittelwert = 0")
} else {
    check(false, "Baseline nil trotz 5 Werten")
}
check(Stats.baseline([1, 2]) == nil, "Baseline braucht mindestens 3 Werte")

// MARK: Sprachen

section("Sprachen (DE/EN)")
check(JournalFactor.alcohol.label(.de) == "Alkohol" && JournalFactor.alcohol.label(.en) == "Alcohol", "JournalFactor zweisprachig")
check(BiologicalSex.male.label(.en) == "Male", "BiologicalSex englisch")
check(HealthMetricKind.restingHR.label(.en) == "Resting HR" && HealthMetricKind.restingHR.unit(.en) == "bpm", "HealthMetricKind englisch inkl. Einheit")
check(StrainEngine.zoneLabels(.en).count == StrainEngine.zoneLabels.count, "Zonen-Labels: EN-Liste vollständig")
// Eigene lokale Inputs — fitInputs/healthRecord sind hier noch nicht initialisiert
// (main.swift-Top-Level läuft sequenziell; Vorwärts-Zugriff wäre ein Segfault).
let langInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: [52, 51, 53, 52, 54],
    rmssdValues: Array(repeating: 57, count: 10),
    restingHRValues: Array(repeating: 51, count: 10),
    sleepPerformances: [88, 90, 87, 91],
    stepsValues: [12000, 11500, 12500],
    validDayCount: 30
)
let deAge = AgeEngine.compute(dateKey: "2026-07-18", inputs: langInputs, language: .de)
let enAge = AgeEngine.compute(dateKey: "2026-07-18", inputs: langInputs, language: .en)
check(enAge.components.contains { $0.label == "Resting HR" || $0.label == "Sleep" || $0.label == "Activity" }, "AgeEngine-Komponenten auf Englisch")
check(enAge.fittrAge == deAge.fittrAge, "Sprache ändert nur Texte, nie Werte")
func langHealthRecord(_ key: String, rhr: Double, resp: Double) -> DayRecord {
    var r = DayRecord(date: key)
    r.restingHR = rhr; r.respiratoryRate = resp; r.hrvRmssd = 60; r.spo2Avg = 97; r.bodyTemp = 34
    return r
}
var langAlertRecords = (0..<8).map { langHealthRecord(DayKey.addDays("2026-06-01", $0), rhr: 55, resp: 14) }
langAlertRecords.append(langHealthRecord(DayKey.addDays("2026-06-01", 8), rhr: 70, resp: 18))
if let enAlert = HealthMonitor.alert(records: langAlertRecords, language: .en) {
    check(enAlert.message.contains("outside your baseline"), "Health-Alert englisch formuliert")
} else {
    check(false, "EN-Health-Alert fehlt")
}

// MARK: Trend-Aggregation

section("Trend-Aggregation")
let maPairs: [(key: String, value: Double)] = (0..<10).map { (DayKey.addDays("2026-06-01", $0), Double($0)) }
let ma3 = TrendMath.movingAverage(maPairs, window: 3)
check(ma3.count == 10, "Gleitender Mittelwert behält die Punktzahl")
check(abs(ma3[0].value - 0) < 1e-9, "Erster Punkt: Mittel aus sich selbst")
check(abs(ma3[2].value - 1) < 1e-9, "Fenster 3 über 0,1,2 → 1")
check(abs(ma3[9].value - 8) < 1e-9, "Fenster 3 über 7,8,9 → 8")
// Lücken: fehlende Tage werden übersprungen, nicht als 0 gezählt.
let gapPairs: [(key: String, value: Double)] = [("2026-06-01", 10), ("2026-06-03", 30)]
let maGap = TrendMath.movingAverage(gapPairs, window: 3)
check(abs(maGap[1].value - 20) < 1e-9, "Lücke im Fenster → Mittel nur über vorhandene Werte")

// 2026-07-19 war ein Sonntag, 2026-07-20 ein Montag.
let weekPairs: [(key: String, value: Double)] = [
    ("2026-07-17", 60), ("2026-07-18", 70), ("2026-07-19", 80), // Woche ab Mo 13.07.
    ("2026-07-20", 40), ("2026-07-21", 60),                     // Woche ab Mo 20.07.
]
let weekly = TrendMath.weeklyMean(weekPairs)
check(weekly.count == 2, "Zwei Kalenderwochen → zwei Punkte")
check(weekly[0].key == "2026-07-13" && abs(weekly[0].value - 70) < 1e-9, "Woche 1: Montag-Key + Mittel 70")
check(weekly[1].key == "2026-07-20" && abs(weekly[1].value - 50) < 1e-9, "Woche 2: Montag-Key + Mittel 50")

// MARK: Strain-Engine

section("Strain-Engine")
check(StrainEngine.strain(fromRaw: 0) == 0, "Kein Load → Strain 0")
// Raw load is Banister TRIMP: easy day ≈ 30, solid session ≈ 110, hard day ≈ 230.
let s60 = StrainEngine.strain(fromRaw: 30)
let s300 = StrainEngine.strain(fromRaw: 110)
let s900 = StrainEngine.strain(fromRaw: 230)
let s5000 = StrainEngine.strain(fromRaw: 5000)
check(s60 > 2 && s60 < 4.5, "Lockerer Tag ≈ 2–4,5 (ist \(String(format: "%.1f", s60)))")
check(s300 > 9 && s300 < 12, "Solides Training ≈ 9–12 (ist \(String(format: "%.1f", s300)))")
check(s900 > 15 && s900 < 18, "Harter Tag ≈ 15–18 (ist \(String(format: "%.1f", s900)))")
check(s5000 < 21.0001, "Skala bleibt bei 21 gedeckelt (ist \(String(format: "%.2f", s5000)))")
check(s60 < s300 && s300 < s900 && s900 < s5000, "Strain wächst monoton mit Load")
// Strain-Ziel aus Recovery (Whoop-Bereiche: Training 14–18, locker 10–14).
let t90 = StrainEngine.targetStrain(forRecovery: 90)
let t67 = StrainEngine.targetStrain(forRecovery: 67)
let t34 = StrainEngine.targetStrain(forRecovery: 34)
check(t90 >= 17 && t90 <= 18.5, "Recovery 90 → Trainings-Ziel (\(String(format: "%.1f", t90)))")
check(t67 >= 13 && t67 <= 14, "Recovery 67 → moderates Ziel (\(String(format: "%.1f", t67)))")
check(t34 >= 6 && t34 <= 8, "Recovery 34 → Erholungs-Ziel (\(String(format: "%.1f", t34)))")
check(StrainEngine.targetStrain(forRecovery: 5) >= 3, "Ziel-Untergrenze 3")
check(StrainEngine.targetStrain(forRecovery: 99) <= 18.5, "Ziel-Obergrenze 18,5 (nie All-out)")
check(t90 > t67 && t67 > t34, "Ziel wächst monoton mit Recovery")

check(StrainEngine.zoneIndex(for: 0.1) == nil, "Unter Zone 0 → kein Load")
check(StrainEngine.zoneIndex(for: 0.5) == 2, "50 % HRR → Zone 3 (Index 2)")
check(StrainEngine.zoneIndex(for: 0.99) == 5, "99 % HRR → Maximal-Zone")

// Ruhezeit: Samples nahe Ruhepuls erzeugen keine aktive Zonenzeit, aber restMin.
let strainBase = DayKey.date(from: "2026-07-17")!
let restSamples = (0..<10).map { HRSample(t: strainBase.addingTimeInterval(Double($0) * 60), bpm: 60) }
let restAcc = StrainEngine.accumulate(samples: restSamples, restingHR: 58, maxHR: 190)
check(restAcc.zones.reduce(0, +) == 0, "Ruhepuls-nahe Samples → keine aktive Zonenzeit")
check(restAcc.restMin >= 9, "Ruhezeit wird erfasst (\(Int(restAcc.restMin)) min)")
let restResult = StrainEngine.dayStrain(
    record: { var r = DayRecord(date: "2026-07-17"); r.hrSamples = restSamples; return r }(),
    restingHR: 58,
    config: StrainConfig(age: 30)
)
check(restResult.strain < 1, "Reiner Ruhetag → Strain nahe 0")
check(restResult.trackedMinutes >= 9, "Aufgezeichnete Zeit (Ruhe+aktiv) sichtbar")

// MARK: Demo-Daten + Engines Ende-zu-Ende

section("Demo-Daten & Engines")
let demoDays = DemoData.generate(daysBack: 120, seed: 42)
check(demoDays.count == 120, "120 Demo-Tage erzeugt")
let sortedKeys = demoDays.keys.sorted()

let strainConfig = StrainConfig(age: 30)
var strainByDay: [String: Double] = [:]
for (key, record) in demoDays {
    let result = StrainEngine.dayStrain(record: record, restingHR: record.restingHR, config: strainConfig)
    strainByDay[key] = result.strain
    if result.strain < 0 || result.strain > 21 {
        check(false, "Strain außerhalb 0–21 an \(key): \(result.strain)")
    }
}
check(strainByDay.values.allSatisfy { $0 >= 0 && $0 <= 21 }, "Alle Tages-Strains in 0–21")
let maxStrain = strainByDay.values.max() ?? 0
let avgStrain = strainByDay.values.reduce(0, +) / Double(strainByDay.count)
check(maxStrain > 10, "Harte Tage erreichen Strain > 10 (max \(String(format: "%.1f", maxStrain)))")
check(avgStrain > 3 && avgStrain < 16, "Durchschnitts-Strain plausibel (\(String(format: "%.1f", avgStrain)))")

let sleepConfig = SleepEngineConfig()
let sleepAnalyses = SleepEngine.analyze(days: demoDays, config: sleepConfig, strainByDay: strainByDay)
check(sleepAnalyses.count == 120, "Schlafanalyse für alle Tage")
for (key, analysis) in sleepAnalyses {
    if analysis.needMinutes < 300 || analysis.needMinutes > 620 {
        check(false, "Schlafbedarf außerhalb Plausibilität an \(key): \(analysis.needMinutes)")
    }
    if analysis.debtAfterMinutes < 0 || analysis.debtAfterMinutes > sleepConfig.maxDebtMinutes {
        check(false, "Schlafschuld außerhalb Grenzen an \(key)")
    }
    if let consistency = analysis.consistency, consistency < 0 || consistency > 100 {
        check(false, "Konsistenz außerhalb 0–100 an \(key)")
    }
    if analysis.performance < 0 || analysis.performance > 100 {
        check(false, "Schlafperformance außerhalb 0–100 an \(key)")
    }
}
check(true, "Bedarf/Schuld/Konsistenz/Performance in gültigen Bereichen")
let withStages = sleepAnalyses.values.filter { !$0.stageMinutes.isEmpty }
check(withStages.count == 120, "Alle Nächte haben Phasen-Minuten")

var recoveryScores: [Int] = []
for key in sortedKeys.suffix(60) {
    guard let record = demoDays[key] else { continue }
    let history = sortedKeys.filter { $0 < key }.compactMap { demoDays[$0] }
    let result = RecoveryEngine.compute(
        dateKey: key,
        today: record,
        history: history,
        sleepPerformance: sleepAnalyses[key]?.performance
    )
    if let result {
        recoveryScores.append(result.score)
        if result.score < 1 || result.score > 99 {
            check(false, "Recovery außerhalb 1–99 an \(key): \(result.score)")
        }
        let expectedZone: RecoveryZone = result.score >= 67 ? .green : (result.score >= 34 ? .yellow : .red)
        if result.zone != expectedZone {
            check(false, "Zonen-Mapping falsch an \(key)")
        }
        let weightSum = result.components.reduce(0) { $0 + $1.weight }
        if abs(weightSum - 1) > 0.001 {
            check(false, "Komponenten-Gewichte summieren nicht auf 1 an \(key)")
        }
    } else {
        check(false, "Recovery nil trotz Daten an \(key)")
    }
}
check(recoveryScores.count == 60, "Recovery für die letzten 60 Tage berechnet")
let recoveryRange = (recoveryScores.min() ?? 0)...(recoveryScores.max() ?? 0)
check(recoveryRange.upperBound - recoveryRange.lowerBound >= 20, "Recovery streut realistisch (\(recoveryRange))")

if let lastKey = sortedKeys.last, let lastRecord = demoDays[lastKey] {
    let history = sortedKeys.dropLast().compactMap { demoDays[$0] }
    let statuses = HealthMonitor.evaluate(today: lastRecord, history: Array(history))
    check(statuses.count == HealthMetricKind.allCases.count, "Health-Monitor liefert alle Metriken")
    check(statuses.allSatisfy { $0.state != .noData }, "Demo-Daten: keine Metrik ohne Daten")
    let rhrStatus = statuses.first { $0.kind == .restingHR }
    check(rhrStatus?.lowerBound != nil && rhrStatus?.upperBound != nil, "Ruhepuls hat Baseline-Band")
}

// MARK: Workout-Strain

section("Workout-Strain")
var workoutStrainChecked = false
for key in sortedKeys.suffix(28) {
    guard let record = demoDays[key], let workout = record.workouts.first else { continue }
    if let strain = StrainEngine.workoutStrain(workout: workout, daySamples: record.hrSamples, restingHR: record.restingHR, config: strainConfig) {
        check(strain > 0 && strain <= 21, "Workout-Strain (\(workout.name), \(key)) in 0–21: \(String(format: "%.1f", strain))")
        workoutStrainChecked = true
        break
    }
}
check(workoutStrainChecked, "Mindestens ein Workout-Strain berechnet")

// MARK: Alters-Engine (Fittr Alter)

section("Alters-Normen")
// Inversion trifft die Stützstellen wieder.
check(abs(AgeNorms.fitnessAge(vo2max: 48.0, sex: .male) - 25) < 1.0, "VO₂max 48 (m) → Fitness-Alter ≈ 25")
check(abs(AgeNorms.fitnessAge(vo2max: 40.3, sex: .male) - 45) < 1.0, "VO₂max 40,3 (m) → Fitness-Alter ≈ 45")
check(abs(AgeNorms.fitnessAge(vo2max: 30.9, sex: .female) - 45) < 1.0, "VO₂max 30,9 (w) → Fitness-Alter ≈ 45")
// Monotonie: fitter ⇒ jünger.
check(AgeNorms.fitnessAge(vo2max: 55, sex: .male) < AgeNorms.fitnessAge(vo2max: 35, sex: .male), "Höherer VO₂max ⇒ jüngeres Fitness-Alter")
let fitVeryHigh = AgeNorms.fitnessAge(vo2max: 65, sex: .male)
check(fitVeryHigh >= 20 && fitVeryHigh <= 25, "Sehr hoher VO₂max wird auf ≥20 geklemmt (\(String(format: "%.0f", fitVeryHigh)))")
check(abs(AgeNorms.hrvAge(rmssd: 55) - 35) < 1.5, "RMSSD 55 (nocturnal wearable norm) → HRV age ≈ 35")
check(abs(AgeNorms.hrvAge(rmssd: 43) - 45) < 1.5, "RMSSD 43 → HRV age ≈ 45")
check(AgeNorms.hrvAge(rmssd: 60) < AgeNorms.hrvAge(rmssd: 25), "Höhere HRV ⇒ jüngeres HRV-Alter")
// Geschlecht verschiebt die Kurve.
check(AgeNorms.vo2max(age: 40, sex: .male) > AgeNorms.vo2max(age: 40, sex: .female), "VO₂max-Norm: Männer > Frauen bei gleichem Alter")

section("Alters-Engine")
let fitInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: [52, 51, 53, 52, 54],
    rmssdValues: Array(repeating: 57, count: 10),
    restingHRValues: Array(repeating: 51, count: 10),
    sleepPerformances: [88, 90, 87, 91],
    stepsValues: [12000, 11500, 12500],
    validDayCount: 30
)
let fitResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: fitInputs)
if let fittrAge = fitResult.fittrAge, let delta = fitResult.deltaYears {
    check(fittrAge >= 15 && fittrAge <= 95, "Fitter 30-Jähriger: Fittr-Alter in Grenzen (\(String(format: "%.0f", fittrAge)))")
    check(delta < 0, "Fitter Mensch ist biologisch jünger (Δ \(String(format: "%.0f", delta)))")
    check(!fitResult.vo2maxEstimated, "Gemessener VO₂max wird bevorzugt (nicht geschätzt)")
} else {
    check(false, "Fittr-Alter trotz voller Daten nil")
}

let unfitInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: Array(repeating: 30, count: 5),
    rmssdValues: Array(repeating: 25, count: 10),
    restingHRValues: Array(repeating: 72, count: 10),
    sleepPerformances: [60, 63, 58],
    stepsValues: [3000, 2800, 3200],
    validDayCount: 30
)
let unfitResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: unfitInputs)
check((unfitResult.deltaYears ?? 0) > 0, "Unfitter Mensch ist biologisch älter (Δ \(String(format: "%.0f", unfitResult.deltaYears ?? 0)))")
check((fitResult.fittrAge ?? 0) < (unfitResult.fittrAge ?? 0), "Fit < Unfit im Fittr-Alter")

// Kalibrierungs-Gate: zu wenig Tage ⇒ kein Wert.
let earlyInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: [50, 51, 52],
    rmssdValues: Array(repeating: 55, count: 8),
    restingHRValues: Array(repeating: 52, count: 8),
    validDayCount: 10
)
let earlyResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: earlyInputs)
check(earlyResult.fittrAge == nil, "Unter 14 gültigen Tagen: noch kein Fittr-Alter")
check(earlyResult.calibrating, "Frühe Phase ist als kalibrierend markiert")
check(earlyResult.calibrationHave == 10, "Kalibrierungsfortschritt zählt gültige Tage")

// Doppelzählungs-Schutz: ohne gemessenen VO₂max wird geschätzt UND der
// Ruhepuls fließt dann NICHT zusätzlich als Korrektur ein.
let estimatedInputs = AgeInputs(
    chronoAge: 40, sex: .male,
    vo2maxValues: [],
    rmssdValues: Array(repeating: 40, count: 10),
    restingHRValues: Array(repeating: 58, count: 12),
    observedMaxHR: 185,
    sleepPerformances: [80, 82],
    stepsValues: [9000, 8500],
    validDayCount: 30
)
let estimatedResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: estimatedInputs)
check(estimatedResult.vo2maxEstimated, "Ohne Messwert: VO₂max wird über HF-Ratio geschätzt")
check(estimatedResult.vo2max != nil, "Geschätzter VO₂max ist vorhanden")
check(!estimatedResult.components.contains { $0.key == "rhr" }, "Bei geschätztem VO₂max keine separate Ruhepuls-Korrektur (kein Doppelzählen)")
check(estimatedResult.components.contains { $0.key == "fitness" }, "Fitness-Komponente auch im Schätz-Pfad vorhanden")

// Ende-zu-Ende auf Demo-Daten (gemessener VO₂max ~50).
let ageWindow = sortedKeys.suffix(30).compactMap { demoDays[$0] }
let ageSleepPerf = sortedKeys.suffix(30).compactMap { key -> Double? in
    guard let a = sleepAnalyses[key], a.hasData else { return nil }
    return a.performance
}
let demoAgeInputs = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: ageWindow.compactMap { $0.vo2max },
    rmssdValues: ageWindow.compactMap { $0.hrvRmssd },
    restingHRValues: ageWindow.compactMap { $0.restingHR },
    sleepPerformances: ageSleepPerf,
    stepsValues: ageWindow.compactMap { $0.steps.map(Double.init) },
    validDayCount: ageWindow.filter { $0.hrvRmssd != nil || $0.restingHR != nil }.count
)
let demoAgeResult = AgeEngine.compute(dateKey: sortedKeys.last!, inputs: demoAgeInputs)
check(demoAgeResult.vo2max != nil, "Demo: VO₂max vorhanden")
if let demoFittrAge = demoAgeResult.fittrAge {
    check(demoFittrAge >= 15 && demoFittrAge <= 45, "Demo: Fittr-Alter plausibel (\(String(format: "%.0f", demoFittrAge)))")
} else {
    check(false, "Demo: Fittr-Alter trotz 30 Tagen nil")
}

// MARK: Journal & Korrelation

section("Journal & Korrelation")
var journalEntries: [String: JournalEntry] = [:]
var journalRecovery: [String: Int] = [:]
for i in 0..<12 {
    let day = DayKey.addDays("2026-06-01", i)
    let alcohol = i % 2 == 0
    let factors: Set<JournalFactor> = alcohol ? [.alcohol] : []
    journalEntries[day] = JournalEntry(date: day, factors: factors)
    journalRecovery[DayKey.addDays("2026-06-01", i + 1)] = alcohol ? 45 : 75
}
let insights = JournalEngine.insights(entries: journalEntries, recoveryByDay: journalRecovery)
if let alc = insights.first(where: { $0.factor == .alcohol }) {
    check(alc.delta < -15, "Alkohol senkt Folge-Recovery deutlich (Δ \(Int(alc.delta)))")
    check(alc.daysWith >= 5 && alc.daysWithout >= 5, "Beide Gruppen über Whoop-Mindestfallzahl (5/5)")
    check(alc.confidence == .solid, "Klarer, konsistenter Effekt → belastbar")
} else {
    check(false, "Alkohol-Insight fehlt trotz Daten")
}
check(!insights.contains { $0.factor == .sick }, "Faktor ohne Einträge liefert kein Insight")
check(JournalFactor.allCases.contains(.sex), "Sex ist als Journal-Faktor vorhanden")

// Verrauschter Mini-Effekt → nur Tendenz, nicht belastbar.
var noisyEntries: [String: JournalEntry] = [:]
var noisyRecovery: [String: Int] = [:]
// Gruppen-Mittel fast gleich (~68), aber hohe Streuung → kein echter Effekt.
let noisyScores = [55, 58, 80, 77, 60, 63, 75, 74, 65, 70, 72, 68]
for i in 0..<12 {
    let day = DayKey.addDays("2026-05-01", i)
    noisyEntries[day] = JournalEntry(date: day, factors: i % 2 == 0 ? [.lateMeal] : [])
    noisyRecovery[DayKey.addDays("2026-05-01", i + 1)] = noisyScores[i]
}
if let noisy = JournalEngine.insights(entries: noisyEntries, recoveryByDay: noisyRecovery).first(where: { $0.factor == .lateMeal }) {
    check(noisy.confidence == .emerging, "Kleiner Effekt in starkem Rauschen → nur Tendenz (Δ \(String(format: "%.1f", noisy.delta)), SE \(String(format: "%.1f", noisy.standardError)))")
} else {
    check(false, "Rausch-Insight fehlt trotz 6/6 Tagen")
}

check(!JournalEngine.assessmentReady(recoveryByDay: journalRecovery), "Unter 28 Recovery-Tagen: Monats-Auswertung noch nicht bereit")
var manyRecoveries: [String: Int] = [:]
for i in 0..<30 { manyRecoveries[DayKey.addDays("2026-05-01", i)] = 70 }
check(JournalEngine.assessmentReady(recoveryByDay: manyRecoveries), "Ab 28 Recovery-Tagen: Monats-Auswertung bereit")

let tmpJournal = FileManager.default.temporaryDirectory.appendingPathComponent("fittr-journal-\(UUID().uuidString)")
let jStore = JournalStore(directory: tmpJournal)
jStore.toggle(.alcohol, on: "2026-07-18")
check(jStore.isSet(.alcohol, on: "2026-07-18"), "Toggle setzt Faktor")
check(jStore.save(), "Journal speichern erfolgreich")
let jReload = JournalStore(directory: tmpJournal)
check(jReload.isSet(.alcohol, on: "2026-07-18"), "Journal übersteht Roundtrip")
try? FileManager.default.removeItem(at: tmpJournal)

// MARK: Schlafschuld (kein Zinseszins, Kappung pro Nacht)

section("Schlafschuld")
func debtNight(_ key: String, minutes: Double) -> DayRecord {
    var r = DayRecord(date: key)
    guard let dayStart = DayKey.date(from: key) else { return r }
    let wake = dayStart.addingTimeInterval(7 * 3600)
    let bed = wake.addingTimeInterval(-minutes * 60)
    r.sleepSessions = [SleepSession(id: "debt-\(key)", start: bed, end: wake, minutesAsleep: minutes, minutesAwake: 0)]
    return r
}
// Basis 456, kein Strain: 1. Nacht Katastrophe (60 min), dann exakt Basis, dann Basis+60.
let debtDays: [String: DayRecord] = [
    "2026-06-01": debtNight("2026-06-01", minutes: 60),
    "2026-06-02": debtNight("2026-06-02", minutes: 456),
    "2026-06-03": debtNight("2026-06-03", minutes: 516),
]
let debtAnalyses = SleepEngine.analyze(days: debtDays, config: SleepEngineConfig())
check(abs((debtAnalyses["2026-06-01"]?.debtAfterMinutes ?? -1) - 180) < 0.01, "Katastrophen-Nacht: Zuwachs pro Nacht auf 180 min gekappt (nicht sofort Maximum)")
check(abs((debtAnalyses["2026-06-02"]?.debtAfterMinutes ?? -1) - 180) < 0.01, "Exakt Basis geschlafen → Schuld bleibt konstant (kein Zinseszins)")
check(abs((debtAnalyses["2026-06-03"]?.debtAfterMinutes ?? -1) - 120) < 0.01, "60 min Überschlafen → Schuld sinkt um 60")
check((debtAnalyses["2026-06-02"]?.needMinutes ?? 0) > 456, "Angezeigter Bedarf enthält weiterhin die Schuld-Rückzahlung")

// MARK: Recovery-Kalibrierung ohne HRV

section("Recovery-Kalibrierung")
func rhrOnly(_ key: String, rhr: Double) -> DayRecord {
    var r = DayRecord(date: key)
    r.restingHR = rhr
    return r
}
let rhrHistory = (0..<10).map { rhrOnly(DayKey.addDays("2026-06-01", $0), rhr: 54 + Double($0 % 3)) }
let noHrvResult = RecoveryEngine.compute(
    dateKey: "2026-06-11",
    today: rhrOnly("2026-06-11", rhr: 55),
    history: rhrHistory,
    sleepPerformance: 85
)
check(noHrvResult != nil, "Recovery ohne HRV berechenbar")
check(noHrvResult?.calibrating == false, "Fehlendes HRV blockiert die Kalibrierung nicht (10 RHR-Nächte reichen)")
let shortHistory = Array(rhrHistory.prefix(3))
let earlyNoHrv = RecoveryEngine.compute(
    dateKey: "2026-06-05",
    today: rhrOnly("2026-06-05", rhr: 55),
    history: shortHistory,
    sleepPerformance: 85
)
check(earlyNoHrv?.calibrating == true, "Unter 5 RHR-Nächten kalibriert weiterhin")

// MARK: Zubettgeh-Empfehlung

section("Zubettgeh-Empfehlung")
var wakeComps = DateComponents()
wakeComps.year = 2026; wakeComps.month = 6; wakeComps.day = 10; wakeComps.hour = 6; wakeComps.minute = 45
let wake645 = Calendar.current.date(from: wakeComps)!
let bedRec = SleepEngine.bedtimeRecommendation(
    currentDebtMinutes: 0, strainToday: 3, recentWakeTimes: [wake645, wake645, wake645]
)
check(abs(bedRec.projectedNeedMinutes - 456) < 5, "Ohne Schuld/Strain ≈ Basisbedarf (\(Int(bedRec.projectedNeedMinutes)))")
if let bed = bedRec.recommendedBedtimeMinutes {
    check(abs(bed - 1389) < 3, "Zubettgehzeit = Aufwachzeit − Bedarf (\(Int(bed)/60):\(String(format: "%02d", Int(bed)%60)))")
} else {
    check(false, "Keine Bedtime trotz Aufwachzeiten")
}
let bedRecHard = SleepEngine.bedtimeRecommendation(currentDebtMinutes: 120, strainToday: 16, recentWakeTimes: [wake645])
check(bedRecHard.projectedNeedMinutes > bedRec.projectedNeedMinutes, "Schuld + harter Tag erhöhen den Bedarf")

// MARK: Health-Warnung

section("Health-Warnung")
func healthRecord(_ key: String, rhr: Double, resp: Double) -> DayRecord {
    var r = DayRecord(date: key)
    r.restingHR = rhr; r.respiratoryRate = resp; r.hrvRmssd = 60; r.spo2Avg = 97; r.bodyTemp = 34
    return r
}
var stableRecords = (0..<8).map { healthRecord(DayKey.addDays("2026-06-01", $0), rhr: 55, resp: 14) }
check(HealthMonitor.alert(records: stableRecords) == nil, "Stabile Werte → keine Warnung")
stableRecords.append(healthRecord(DayKey.addDays("2026-06-01", 8), rhr: 70, resp: 18))
if let multi = HealthMonitor.alert(records: stableRecords) {
    check(multi.kinds.count >= 2, "Mehrere auffällige Werte → Warnung mit ≥2 Metriken")
} else {
    check(false, "Warnung fehlt trotz zwei auffälliger Werte")
}
var streakRecords = (0..<7).map { healthRecord(DayKey.addDays("2026-07-01", $0), rhr: 55, resp: 14) }
streakRecords.append(healthRecord(DayKey.addDays("2026-07-01", 7), rhr: 68, resp: 14))
streakRecords.append(healthRecord(DayKey.addDays("2026-07-01", 8), rhr: 69, resp: 14))
if let streak = HealthMonitor.alert(records: streakRecords) {
    check(streak.kinds == [.restingHR], "Einzelne Metrik über 2 Tage → Streak-Warnung")
} else {
    check(false, "Streak-Warnung fehlt")
}

// MARK: Sync-Helfer

section("Sync-Helfer")
let base = DayKey.date(from: "2026-07-17")!
let rawSamples = (0..<120).map { i in
    SamplePoint(time: base.addingTimeInterval(Double(i) * 5), value: 60 + Double(i % 10))
}
let downsampled = SyncEngine.downsampleToMinutes(rawSamples)
check(downsampled.count == 10, "600 s in 5-s-Auflösung → 10 Minuten-Buckets")
check(downsampled.allSatisfy { $0.bpm >= 60 && $0.bpm <= 70 }, "Downsampling mittelt korrekt")

let nightSamples = [
    SamplePoint(time: DayKey.date(from: "2026-07-16")!.addingTimeInterval(23.5 * 3600), value: 55),
    SamplePoint(time: DayKey.date(from: "2026-07-17")!.addingTimeInterval(3 * 3600), value: 65),
]
let grouped = SyncEngine.groupByNight(nightSamples)
check(grouped["2026-07-17"]?.count == 2, "Nacht-Gruppierung fasst Abend + Morgen zusammen")

// Rate-Limit-Backoff (Google: 300 Requests/min/Nutzer).
check(HealthAPIClient.retryDelay(attempt: 0, retryAfterHeader: "7") == 7, "Retry-After-Header wird respektiert")
check(HealthAPIClient.retryDelay(attempt: 0, retryAfterHeader: nil) == 2, "Ohne Header: exponentiell ab 2 s")
check(HealthAPIClient.retryDelay(attempt: 2, retryAfterHeader: nil) == 8, "Exponentieller Anstieg (Versuch 3 → 8 s)")
check(HealthAPIClient.retryDelay(attempt: 9, retryAfterHeader: nil) == 60, "Backoff bei 60 s gekappt")
check(HealthAPIClient.retryDelay(attempt: 0, retryAfterHeader: "120") == 60, "Retry-After bei 60 s gekappt")

// Inkrementeller HF-Sync: geprüfte Vergangenheitstage werden übersprungen.
let oldKey = DayKey.addDays(DayKey.today(), -3)
var oldFull = DayRecord(date: oldKey)
oldFull.hrSamples = [HRSample(t: DayKey.date(from: oldKey)!, bpm: 60)]
oldFull.hrSyncedAt = Date() // nach Tagesende geprüft
check(SyncEngine.isIntradayComplete(oldFull, dayKey: oldKey), "Alter Tag mit Daten, nach Tagesende geprüft → übersprungen")
var oldEmpty = DayRecord(date: oldKey)
oldEmpty.hrSyncedAt = Date() // leer, aber geprüft
check(SyncEngine.isIntradayComplete(oldEmpty, dayKey: oldKey), "Alter LEERER Tag, einmal geprüft → wird NICHT erneut geladen")
let yesterdayKey = DayKey.addDays(DayKey.today(), -1)
var yest = DayRecord(date: yesterdayKey)
yest.hrSamples = [HRSample(t: DayKey.date(from: yesterdayKey)!, bpm: 60)]
yest.hrSyncedAt = Date()
check(!SyncEngine.isIntradayComplete(yest, dayKey: yesterdayKey), "Gestern wird immer neu geladen (verspätete Uhr-Daten)")
var todayDay = DayRecord(date: DayKey.today())
todayDay.hrSamples = [HRSample(t: Date(), bpm: 60)]
todayDay.hrSyncedAt = Date()
check(!SyncEngine.isIntradayComplete(todayDay, dayKey: DayKey.today()), "Heute gilt nie als vollständig")
var oldUnstamped = DayRecord(date: oldKey)
oldUnstamped.hrSamples = [HRSample(t: DayKey.date(from: oldKey)!, bpm: 60)]
check(!SyncEngine.isIntradayComplete(oldUnstamped, dayKey: oldKey), "Ohne hrSyncedAt-Stempel wird geladen")
check(!SyncEngine.isIntradayComplete(nil, dayKey: oldKey), "Fehlender Tag wird geladen")

// Spike-Filter: isolierte Artefakt-Spitze wird geglättet, Rampe bleibt.
let spikeSamples = [60.0, 62, 175, 61, 63].enumerated().map {
    HRSample(t: base.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element)
}
let deSpiked = SyncEngine.removeSpikes(spikeSamples)
check(deSpiked[2].bpm < 100, "Isolierte HF-Spitze (175) wird geglättet → \(Int(deSpiked[2].bpm))")
let rampSamples = [60.0, 105, 150, 175].enumerated().map {
    HRSample(t: base.addingTimeInterval(Double($0.offset) * 60), bpm: $0.element)
}
check(SyncEngine.removeSpikes(rampSamples).map(\.bpm) == rampSamples.map(\.bpm), "Monotoner Anstieg bleibt unangetastet")

// MARK: Store-Roundtrip

section("MetricsStore")
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("fittr-selftest-\(UUID().uuidString)")
let store = MetricsStore(directory: tempDir)
store.merge(Array(demoDays.values))
check(store.days.count == 120, "Store enthält 120 Tage")
check(store.save(), "Speichern erfolgreich")

let reloaded = MetricsStore(directory: tempDir)
check(reloaded.days.count == 120, "Reload liefert 120 Tage")
if let lastKey = sortedKeys.last {
    let original = store.days[lastKey]
    let restored = reloaded.days[lastKey]
    check(original?.hrvRmssd == restored?.hrvRmssd, "HRV übersteht Roundtrip")
    // ISO-8601-Encoding rundet Dates auf ganze Sekunden → tolerant vergleichen.
    let hrStampDelta = abs((original?.hrSyncedAt?.timeIntervalSince1970 ?? -1) - (restored?.hrSyncedAt?.timeIntervalSince1970 ?? -2))
    check(hrStampDelta < 1, "hrSyncedAt übersteht Roundtrip (Sekunden-Präzision)")
    check(original?.sleepSessions.count == restored?.sleepSessions.count, "Schlaf-Sessions überstehen Roundtrip")
    check((restored?.hrSamples.count ?? 0) > 0, "HR-Samples des letzten Tages erhalten")
}
let historyCheck = reloaded.history(before: sortedKeys.last!, days: 30)
check(historyCheck.count == 30, "history(before:) liefert 30 Tage")
try? FileManager.default.removeItem(at: tempDir)


// MARK: New engines (v2): TRIMP, sleep score, stress, cardio load, nutrition, workouts, coach

section("Strain — Banister TRIMP")
let trimpMale = StrainEngine.trimpPerMinute(fraction: 0.6, sex: .male)
let trimpFemale = StrainEngine.trimpPerMinute(fraction: 0.6, sex: .female)
check(abs(trimpMale - 1.2153) < 0.01, "TRIMP/min at 60 % HRR (male) = 0.64·0.6·e^(1.92·0.6) ≈ 1.215 (\(String(format: "%.3f", trimpMale)))")
check(abs(trimpFemale - 1.4055) < 0.01, "TRIMP/min at 60 % HRR (female) ≈ 1.406 (\(String(format: "%.3f", trimpFemale)))")
check(StrainEngine.trimpPerMinute(fraction: 0.9, sex: .male) > StrainEngine.trimpPerMinute(fraction: 0.6, sex: .male) * 2, "Intensity is weighted super-linearly")
let trimpBase = DayKey.date(from: "2026-07-17")!
let hrHard = (0..<60).map { HRSample(t: trimpBase.addingTimeInterval(Double($0) * 60), bpm: 60 + 0.65 * 130) }
let hardAcc = StrainEngine.accumulate(samples: hrHard, restingHR: 60, maxHR: 190, sex: .male)
check(hardAcc.raw > 80 && hardAcc.raw < 95, "60 min at 65 % HRR ≈ 87 TRIMP (\(String(format: "%.0f", hardAcc.raw)))")
check(StrainEngine.strain(fromRaw: hardAcc.raw) > 8 && StrainEngine.strain(fromRaw: hardAcc.raw) < 10.5, "…a ~9 strain session on its own (≈10.5 with everyday movement on top)")
let hrEasy = (0..<60).map { HRSample(t: trimpBase.addingTimeInterval(Double($0) * 60), bpm: 60 + 0.25 * 130) }
check(StrainEngine.accumulate(samples: hrEasy, restingHR: 60, maxHR: 190, sex: .male).raw == 0, "Below 30 % HRR (daily living) adds no strain")

section("Sleep score")
func sleepDay(_ key: String, hours: Double, deepRemShare: Double, awakeMin: Double) -> DayRecord {
    var r = DayRecord(date: key)
    let end = DayKey.date(from: key)!.addingTimeInterval(7 * 3600)
    let inBed = hours * 60 + awakeMin
    let start = end.addingTimeInterval(-inBed * 60)
    let asleep = hours * 60
    let restorative = asleep * deepRemShare
    let stages = [
        StageSpan(stage: .light, start: start, end: start.addingTimeInterval((asleep - restorative) * 60)),
        StageSpan(stage: .deep, start: start.addingTimeInterval((asleep - restorative) * 60), end: start.addingTimeInterval((asleep - restorative / 2) * 60)),
        StageSpan(stage: .rem, start: start.addingTimeInterval((asleep - restorative / 2) * 60), end: start.addingTimeInterval(asleep * 60)),
        StageSpan(stage: .awake, start: start.addingTimeInterval(asleep * 60), end: end),
    ]
    r.sleepSessions = [SleepSession(id: key, start: start, end: end, minutesAsleep: asleep, minutesAwake: awakeMin, stages: stages)]
    return r
}
let sleepGood = SleepEngine.analyze(days: ["2026-07-17": sleepDay("2026-07-17", hours: 8, deepRemShare: 0.45, awakeMin: 20)])["2026-07-17"]!
let sleepPoor = SleepEngine.analyze(days: ["2026-07-17": sleepDay("2026-07-17", hours: 5, deepRemShare: 0.20, awakeMin: 90)])["2026-07-17"]!
check(sleepGood.score > 85 && sleepGood.score <= 100, "Good night scores > 85 (\(String(format: "%.0f", sleepGood.score)))")
check(sleepPoor.score < 65, "Short, fragmented night scores < 65 (\(String(format: "%.0f", sleepPoor.score)))")
check(sleepGood.score > sleepPoor.score, "Sleep score orders good above poor")
check(SleepEngine.analyze(days: ["2026-07-18": DayRecord(date: "2026-07-18")])["2026-07-18"]!.score == 0, "No sleep data → score 0")

section("Stress")
func stressDay(_ key: String, rhr: Double, elevation: Double, hrv: Double) -> DayRecord {
    var r = DayRecord(date: key)
    r.restingHR = rhr
    r.hrvRmssd = hrv
    let day = DayKey.date(from: key)!
    r.hrSamples = (0..<720).map { HRSample(t: day.addingTimeInterval(8 * 3600 + Double($0) * 60), bpm: rhr + elevation) }
    return r
}
let stressHistory = (1...12).map { stressDay(DayKey.addDays("2026-07-20", -$0), rhr: 55, elevation: 8 + Double($0 % 3), hrv: 60 + Double($0 % 4)) }
let stressCalm = StressEngine.compute(dateKey: "2026-07-20", record: stressDay("2026-07-20", rhr: 55, elevation: 4, hrv: 75), history: stressHistory, maxHR: 190)
let stressHigh = StressEngine.compute(dateKey: "2026-07-20", record: stressDay("2026-07-20", rhr: 55, elevation: 24, hrv: 38), history: stressHistory, maxHR: 190)
let stressTypical = StressEngine.compute(dateKey: "2026-07-20", record: stressDay("2026-07-20", rhr: 55, elevation: 9, hrv: 61), history: stressHistory, maxHR: 190)
check((stressCalm?.score ?? 100) < 25 && stressCalm?.level == .low, "Calm day → low stress (\(String(format: "%.0f", stressCalm?.score ?? -1)))")
check((stressHigh?.score ?? 0) > 70 && stressHigh?.level == .high, "Elevated HR + suppressed HRV → high stress (\(String(format: "%.0f", stressHigh?.score ?? -1)))")
check(abs((stressTypical?.score ?? 0) - 33) < 12, "A typical day for you lands near 33 (\(String(format: "%.0f", stressTypical?.score ?? -1)))")
check((stressHigh?.hourly.compactMap { $0 }.count ?? 0) >= 10, "Hourly profile covers the recorded hours")
// Regression: with no personal history a normal awake heart rate (+27 bpm) must not read as 94 "High".
let stressNoHistory = StressEngine.compute(dateKey: "2026-07-20", record: { var r = stressDay("2026-07-20", rhr: 55, elevation: 27, hrv: 45); r.hrvRmssd = nil; return r }(), history: [], maxHR: 190)
check((stressNoHistory?.score ?? 100) > 40 && (stressNoHistory?.score ?? 100) < 75, "No history, +27 bpm awake → moderate, not extreme (\(String(format: "%.0f", stressNoHistory?.score ?? -1)))")
let stressNoHistoryTypical = StressEngine.compute(dateKey: "2026-07-20", record: { var r = stressDay("2026-07-20", rhr: 55, elevation: 20, hrv: 45); r.hrvRmssd = nil; return r }(), history: [], maxHR: 190)
check(abs((stressNoHistoryTypical?.score ?? 0) - 33) < 6, "No history, +20 bpm awake ≈ typical (\(String(format: "%.0f", stressNoHistoryTypical?.score ?? -1)))")
check(StressEngine.compute(dateKey: "2026-07-20", record: DayRecord(date: "2026-07-20"), history: [], maxHR: 190) == nil, "No HR and no HRV → no stress value")

section("Cardio load")
var steady: [String: Double] = [:]
for i in 0..<28 { steady[DayKey.addDays("2026-07-01", i)] = 100 }
let steadyResult = CardioLoadEngine.compute(loads: steady)["2026-07-28"]!
check(abs((steadyResult.ratio ?? 0) - 1.0) < 0.05 && steadyResult.status == .optimal, "Constant load → ratio ≈ 1.0, optimal (\(String(format: "%.2f", steadyResult.ratio ?? -1)))")
var spike = steady
for i in 21..<28 { spike[DayKey.addDays("2026-07-01", i)] = 260 }
let spikeResult = CardioLoadEngine.compute(loads: spike)["2026-07-28"]!
check((spikeResult.ratio ?? 0) > 1.3, "A sudden jump in load pushes the ratio above 1.3 (\(String(format: "%.2f", spikeResult.ratio ?? -1)))")
check(CardioLoadEngine.compute(loads: steady)["2026-07-05"]?.status == .building, "Fewer than 14 days → building baseline")
check(abs(steadyResult.weeklyLoad - 700) < 1e-6, "Weekly load sums the last 7 days")

section("Nutrition")
check(abs(NutritionEngine.bmr(sex: .male, weightKg: 80, heightCm: 180, age: 30) - 1780) < 0.01, "Mifflin-St Jeor (80 kg, 180 cm, 30 y, male) = 1780")
check(abs(NutritionEngine.bmr(sex: .female, weightKg: 60, heightCm: 165, age: 30) - 1320.25) < 0.01, "Mifflin-St Jeor (female) = 1320")
let tgtEst = NutritionEngine.targets(sex: .male, weightKg: 80, heightCm: 180, age: 30, goal: .maintain, recentCaloriesOut: [])
check(abs(tgtEst.calories - 1780 * 1.4) < 1, "No Fitbit data → BMR × 1.4 (\(Int(tgtEst.calories)))")
check(abs(tgtEst.proteinG - 128) < 0.5, "Maintenance protein 1.6 g/kg = 128 g")
check(abs(tgtEst.proteinG * 4 + tgtEst.carbsG * 4 + tgtEst.fatG * 9 - tgtEst.calories) < 2, "Macros add up to the calorie target")
let tgtMeasured = NutritionEngine.targets(sex: .male, weightKg: 80, heightCm: 180, age: 30, goal: .lose, recentCaloriesOut: [2800, 2900, 2700, 2800])
check(abs(tgtMeasured.maintenance - 2800) < 1, "Measured Fitbit burn is used as maintenance")
check(abs(tgtMeasured.calories - 2380) < 1, "Fat-loss goal = 85 % of maintenance")
check(tgtMeasured.proteinG > tgtEst.proteinG, "Deficit raises protein to 2.0 g/kg")
check(NutritionEngine.targets(sex: .female, weightKg: 45, heightCm: 150, age: 60, goal: .lose, recentCaloriesOut: []).calories >= 1200, "Calorie target never drops below 1200")
let nutriDir = FileManager.default.temporaryDirectory.appendingPathComponent("fittr-nutrition-\(UUID().uuidString)")
let nutriStore = NutritionStore(directory: nutriDir)
nutriStore.add(FoodEntry(date: "2026-07-17", meal: .lunch, name: "Rice bowl", calories: 650, proteinG: 40, carbsG: 80, fatG: 15, fiberG: 6))
nutriStore.add(FoodEntry(date: "2026-07-17", meal: .snack, name: "Apple", calories: 95, carbsG: 25, fiberG: 4))
nutriStore.save()
let nutriReloaded = NutritionStore(directory: nutriDir)
check(nutriReloaded.entries.count == 2, "Food log survives a save/load roundtrip")
let totals = NutritionTotals(nutriReloaded.entries(for: "2026-07-17"))
check(totals.calories == 745 && totals.proteinG == 40 && totals.fiberG == 10, "Daily totals add up")
nutriReloaded.remove(id: nutriReloaded.entries[0].id)
check(nutriReloaded.entries.count == 1, "Entries can be removed")
try? FileManager.default.removeItem(at: nutriDir)

section("Workout log")
let squatSet = StrengthSet(reps: 5, weightKg: 100)
check(abs((squatSet.estimatedOneRepMax ?? 0) - 116.667) < 0.01, "Epley 1RM: 100 kg × 5 = 116.7 kg")
check(StrengthSet(reps: 20, weightKg: 40).estimatedOneRepMax == nil, "1RM is not estimated above 12 reps")
check(StrengthSet(reps: 1, weightKg: 140).estimatedOneRepMax == 140, "A single is its own 1RM")
let lifting = LoggedWorkout(date: "2026-07-17", start: trimpBase, durationMinutes: 60, kind: .strength, rpe: 6, exercises: [
    StrengthExercise(name: "Squat", sets: [StrengthSet(reps: 5, weightKg: 100), StrengthSet(reps: 5, weightKg: 100)]),
    StrengthExercise(name: "Bench", sets: [StrengthSet(reps: 8, weightKg: 60)]),
])
check(lifting.sessionLoadAU == 360, "Session-RPE load = RPE × minutes (Foster)")
check(abs(lifting.estimatedTrimp - 72) < 0.01, "60 min at RPE 6 ≈ 72 TRIMP (matches 60 % HRR)")
check(lifting.totalVolumeKg == 1480 && lifting.totalSets == 3, "Volume and set counts (1480 kg, 3 sets)")
check(lifting.estimatedCalories(weightKg: 80) > 300 && lifting.estimatedCalories(weightKg: 80) < 500, "MET-based energy estimate is plausible")
let woDir = FileManager.default.temporaryDirectory.appendingPathComponent("fittr-workouts-\(UUID().uuidString)")
let woStore = WorkoutLogStore(directory: woDir)
woStore.add(lifting)
woStore.save()
let woReloaded = WorkoutLogStore(directory: woDir)
check(woReloaded.workouts.count == 1 && woReloaded.workouts[0].exercises.count == 2, "Workout log survives a roundtrip")
check(abs((woReloaded.personalBests()["squat"] ?? 0) - 116.667) < 0.01, "Personal bests track the best estimated 1RM")
try? FileManager.default.removeItem(at: woDir)

section("Fittr Age — bounded (regression: \"shows 50\")")
// A 30-year-old man with resting HR 70, low HRV and NO measured VO₂max previously scored ~50.
let regression = AgeInputs(
    chronoAge: 30, sex: .male,
    vo2maxValues: [],
    rmssdValues: Array(repeating: 25, count: 14),
    restingHRValues: Array(repeating: 70, count: 14),
    sleepPerformances: [70, 72, 68],
    stepsValues: [6000, 6500, 5500],
    validDayCount: 30
)
let regressionResult = AgeEngine.compute(dateKey: "2026-07-18", inputs: regression)
if let regressionAge = regressionResult.fittrAge {
    check(regressionAge > 30, "Below-average markers still read older than 30 (\(String(format: "%.0f", regressionAge)))")
    check(regressionAge < 42, "…but an estimated VO₂max and a noisy HRV cannot push a 30-year-old to 50 (\(String(format: "%.0f", regressionAge)))")
} else {
    check(false, "Regression scenario produced no Fittr Age")
}
let extreme = AgeEngine.compute(dateKey: "2026-07-18", inputs: AgeInputs(
    chronoAge: 35, sex: .female, vo2maxValues: [12, 12, 12], rmssdValues: Array(repeating: 8, count: 10),
    restingHRValues: Array(repeating: 100, count: 10), sleepPerformances: [30], stepsValues: [500], validDayCount: 30))
check((extreme.deltaYears ?? 99) <= 15.0001, "Worst-case markers are capped at +15 years (\(String(format: "%.1f", extreme.deltaYears ?? -99)))")
let elite = AgeEngine.compute(dateKey: "2026-07-18", inputs: AgeInputs(
    chronoAge: 50, sex: .male, vo2maxValues: [65, 65, 65], rmssdValues: Array(repeating: 90, count: 10),
    restingHRValues: Array(repeating: 42, count: 10), sleepPerformances: [95], stepsValues: [16000], validDayCount: 30))
check((elite.deltaYears ?? 0) >= -15.0001, "Best-case markers are capped at −15 years (\(String(format: "%.1f", elite.deltaYears ?? 99)))")
check((elite.deltaYears ?? 0) < -5, "An elite 50-year-old is clearly biologically younger (\(String(format: "%.1f", elite.deltaYears ?? 99)))")

section("Coach")
let fenced = "```json\n{\"name\":\"Chicken salad\",\"calories\":430,\"protein_g\":38,\"carbs_g\":12,\"fat_g\":25,\"fiber_g\":4,\"note\":\"Assumed 150 g chicken\"}\n```"
if let meal = try? CoachClient.parseMeal(fenced) {
    check(meal.name == "Chicken salad" && meal.calories == 430 && meal.proteinG == 38 && meal.fiberG == 4, "Meal estimate JSON is parsed even inside a code fence")
} else {
    check(false, "Meal JSON should parse")
}
check((try? CoachClient.parseMeal("I could not tell")) == nil, "Non-JSON answers are rejected, not guessed")
check((try? CoachClient.parseMeal("{\"name\":\"x\"}")) == nil, "A meal without calories is rejected")
check(CoachClient.defaultModel == "claude-opus-5-5", "Default model id")

// MARK: Ergebnis

print("")
if failures.isEmpty {
    print("ALLE TESTS BESTANDEN ✅")
    exit(0)
} else {
    print("\(failures.count) TEST(S) FEHLGESCHLAGEN ❌")
    for failure in failures {
        print("  – \(failure)")
    }
    exit(1)
}
