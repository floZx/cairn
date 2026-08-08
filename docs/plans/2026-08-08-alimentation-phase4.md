# Alimentation — Phase 4 : l'écran Poids

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** L'entrée sidebar « Poids » avec le suivi complet : graphe Swift Charts (objectif + minimum de période), statistiques (Δ 7 j, rythme par régression, estimation), et la liste des pesées éditable.

**Architecture:** `WeightStats` porte fidèlement `suivinut/domain/stats.py` en type pur testé (fenêtre relative à la *dernière* pesée, régression moindres carrés). Les écritures passent par `NutritionJournal` (upsert par jour — une pesée par jour, la ressaisie remplace). La vue suit le motif des autres écrans : Swift Charts comme Statistiques, sheets modales avec la porte clavier vim de NutritionDayView.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Charts (Apple), Swift Testing. Aucune dépendance externe.

**Spec :** `docs/specs/2026-08-08-alimentation-design.md` (§1 sidebar, §6 écran Poids, §7 WeightStats, §11 phase 4). Le mini-calendrier et le panneau stats de la colonne détail d'Alimentation restent pour la phase 6, comme prévu au plan de phase 1.

## Global Constraints

- macOS 15.0 minimum, Swift 6.0, `@MainActor` sur tout ce qui touche `ModelContext`.
- Aucune dépendance externe — Swift Charts est le framework Apple déjà utilisé par Statistiques.
- Identifiants/commentaires **anglais**, chaînes visibles **français**, commentaires « pourquoi ».
- `monospacedDigit` sur les chiffres, couleurs système uniquement (`.green` pour la ligne du minimum, comme suivinut ; `.secondary` pointillé pour l'objectif).
- Après **tout ajout de fichier source** : `xcodegen generate` avant de builder.
- Tests : Swift Testing, noms en français. Commande type :
  ```bash
  xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/WeightStatsTests 2>&1 | tail -5
  ```
- Commits : Conventional Commits en français, scope `poids` (sauf le routage sidebar, scope `alimentation`).
- Sémantique suivinut **à l'identique** (`domain/stats.py`) : la fenêtre d'affichage est relative à la **dernière pesée**, pas à aujourd'hui (`weights_in_window`) ; Δ = dernière − première pesée de la fenêtre, `nil` si < 2 points ; rythme kg/semaine par **régression moindres carrés** sur 30 j (`slope × 7`), `nil` si dénominateur nul ; estimation `|reste / rythme|` seulement si le rythme va **dans le sens** de l'objectif, `nil` sinon ; une pesée par jour, ressaisir un jour existant **remplace**.

---

### Task 1: WeightStats — statistiques pures du poids

**Files:**
- Create: `Cairn/Features/Nutrition/WeightStats.swift`
- Test: `Tests/WeightStatsTests.swift`

**Interfaces:**
- Consumes: `DateKey` (`init?(raw:)`, `.raw`, `.date(calendar:)`, `.advanced(by:)`).
- Produces (utilisé par Task 3, et par le panneau stats de la phase 6) :

```swift
struct WeightPoint: Equatable, Sendable {
    var dateKey: DateKey
    var weightKg: Double
}

enum WeightStats {
    /// Weigh-ins within the last `days` days *relative to the last weigh-in*.
    static func window(_ weights: [WeightPoint], days: Int?) -> [WeightPoint]
    /// Weight change over the trailing window. nil if fewer than 2 points.
    static func delta(_ weights: [WeightPoint], days: Int = 7) -> Double?
    /// kg/week by least-squares regression over the window. nil if degenerate.
    static func ratePerWeek(_ weights: [WeightPoint], days: Int = 30) -> Double?
    /// Estimated weeks to reach `goal` at the current rate. nil when the rate
    /// points away from the goal (or is flat).
    static func weeksToGoal(
        _ weights: [WeightPoint], goal: Double, days: Int = 30
    ) -> Double?
    /// Consecutive logged days ending at `end` (inclusive).
    static func loggingStreak(loggedDates: Set<String>, endingAt end: DateKey) -> Int
}
```

Toutes les fonctions supposent `weights` trié par date croissante (comme suivinut). `loggingStreak` est porté avec le reste du fichier Python : la phase 6 (panneau stats) l'utilisera.

- [ ] **Step 1: Écrire les tests qui échouent** (cas portés de `tests/test_stats.py`)

```swift
// Tests/WeightStatsTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("WeightStats")
struct WeightStatsTests {
    private func point(_ raw: String, _ kg: Double) -> WeightPoint {
        WeightPoint(dateKey: DateKey(raw: raw)!, weightKg: kg)
    }

    @Test("le delta 7 jours compare les bornes de la fenêtre")
    func deltaSevenDays() {
        let weights = [
            point("2026-06-20", 74.0), point("2026-06-24", 73.5),
            point("2026-06-30", 73.0),
        ]
        // Fenêtre 7 j finissant au 30 -> >= 23/06 : 73.5 (24) -> 73.0 (30).
        #expect(WeightStats.delta(weights, days: 7) == -0.5)
        #expect(WeightStats.delta([point("2026-06-30", 73.0)], days: 7) == nil)
    }

    @Test("le rythme hebdomadaire sort de la régression")
    func ratePerWeekFromTwoPoints() throws {
        let weights = [point("2026-06-16", 74.0), point("2026-06-30", 73.0)]
        // -1.0 kg en 14 jours = -0.5 kg/semaine.
        let rate = try #require(WeightStats.ratePerWeek(weights, days: 30))
        #expect(abs(rate - -0.5) < 0.0001)
    }

    @Test("la régression voit la tendance qu'un calcul fin-début raterait")
    func rateUsesRegressionNotEndpoints() throws {
        // Rebond final isolé : fin-début donnerait 0, la régression descend.
        let weights = [
            point("2026-06-01", 74.0), point("2026-06-02", 73.5),
            point("2026-06-03", 73.0), point("2026-06-04", 74.0),
        ]
        let rate = try #require(WeightStats.ratePerWeek(weights, days: 30))
        #expect(abs((rate * 100).rounded() / 100 - -0.35) < 0.0001)
    }

    @Test("l'estimation vers l'objectif suit le rythme, ou s'abstient")
    func weeksToGoal() throws {
        let losing = [point("2026-06-16", 74.0), point("2026-06-30", 73.0)]
        // Reste 3 kg à -0.5 kg/sem -> 6 semaines. Tolérance plutôt qu'égalité
        // exacte : le rythme sort d'une régression en flottants.
        let weeks = try #require(WeightStats.weeksToGoal(losing, goal: 70, days: 30))
        #expect(abs(weeks - 6.0) < 0.0001)
        // Prendre du poids alors qu'il faut en perdre -> pas d'estimation.
        let gaining = [point("2026-06-16", 72.0), point("2026-06-30", 73.0)]
        #expect(WeightStats.weeksToGoal(gaining, goal: 70, days: 30) == nil)
        #expect(WeightStats.weeksToGoal([], goal: 70, days: 30) == nil)
    }

    @Test("la fenêtre est relative à la dernière pesée, pas à aujourd'hui")
    func windowRelativeToLastWeighIn() {
        let weights = [
            point("2026-05-01", 76.0), point("2026-06-20", 74.0),
            point("2026-06-28", 73.6), point("2026-07-01", 73.4),
        ]
        let got = WeightStats.window(weights, days: 30).map(\.dateKey.raw)
        #expect(got == ["2026-06-20", "2026-06-28", "2026-07-01"])
    }

    @Test("fenêtre nil = tout, liste vide = vide")
    func windowNilAndEmpty() {
        let weights = [point("2026-05-01", 76.0), point("2026-07-01", 73.4)]
        #expect(WeightStats.window(weights, days: nil) == weights)
        #expect(WeightStats.window([], days: 30).isEmpty)
    }

    @Test("la série de jours consignés compte en remontant")
    func streakCountsBackwards() {
        let logged: Set<String> = ["2026-06-28", "2026-06-29", "2026-06-30"]
        #expect(WeightStats.loggingStreak(
            loggedDates: logged, endingAt: DateKey(raw: "2026-06-30")!
        ) == 3)
        #expect(WeightStats.loggingStreak(
            loggedDates: logged, endingAt: DateKey(raw: "2026-06-27")!
        ) == 0)
        #expect(WeightStats.loggingStreak(
            loggedDates: ["2026-06-30"], endingAt: DateKey(raw: "2026-06-30")!
        ) == 1)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/WeightStatsTests 2>&1 | tail -5`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/WeightStats.swift
import Foundation

struct WeightPoint: Equatable, Sendable {
    var dateKey: DateKey
    var weightKg: Double
}

/// Pure weight statistics, ported from suivinut's `domain/stats.py` — zero
/// I/O, weigh-ins sorted ascending by date.
enum WeightStats {
    /// The trailing window is anchored on the LAST weigh-in, not on today:
    /// the chart must show data even when the last weigh-in is old.
    static func window(_ weights: [WeightPoint], days: Int?) -> [WeightPoint] {
        guard let days, let last = weights.last else { return weights }
        let cutoff = last.dateKey.advanced(by: -days)
        return weights.filter { $0.dateKey.raw >= cutoff.raw }
    }

    static func delta(_ weights: [WeightPoint], days: Int = 7) -> Double? {
        guard weights.count >= 2 else { return nil }
        let windowed = window(weights, days: days)
        guard windowed.count >= 2, let first = windowed.first,
              let last = windowed.last
        else { return nil }
        return last.weightKg - first.weightKg
    }

    /// Least squares over every point of the window rather than a plain
    /// end-minus-start: an isolated spike at either edge must not fake or
    /// hide a trend.
    static func ratePerWeek(_ weights: [WeightPoint], days: Int = 30) -> Double? {
        guard weights.count >= 2 else { return nil }
        let windowed = window(weights, days: days)
        guard windowed.count >= 2, let origin = windowed.first else { return nil }
        let calendar = Calendar.current
        let start = origin.dateKey.date(calendar: calendar)
        let xs = windowed.map {
            Double(calendar.dateComponents(
                [.day], from: start, to: $0.dateKey.date(calendar: calendar)
            ).day ?? 0)
        }
        let ys = windowed.map(\.weightKg)
        let count = Double(xs.count)
        let meanX = xs.reduce(0, +) / count
        let meanY = ys.reduce(0, +) / count
        let denominator = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        guard denominator != 0 else { return nil }
        let numerator = zip(xs, ys)
            .map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        return numerator / denominator * 7
    }

    /// nil unless the current rate actually converges on the goal — telling
    /// someone gaining weight "N weeks to your loss goal" would be noise.
    static func weeksToGoal(
        _ weights: [WeightPoint], goal: Double, days: Int = 30
    ) -> Double? {
        guard let last = weights.last,
              let rate = ratePerWeek(weights, days: days)
        else { return nil }
        let remaining = last.weightKg - goal
        guard remaining != 0, rate != 0, (remaining > 0) != (rate > 0) else {
            return nil
        }
        return abs(remaining / rate)
    }

    static func loggingStreak(
        loggedDates: Set<String>, endingAt end: DateKey
    ) -> Int {
        var day = end
        var streak = 0
        while loggedDates.contains(day.raw) {
            streak += 1
            day = day.advanced(by: -1)
        }
        return streak
    }
}
```

- [ ] **Step 4: Vérifier le succès**

Run: la même commande qu'au step 2.
Expected: PASS sur les 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/WeightStats.swift Tests/WeightStatsTests.swift
git commit -m "feat(poids): statistiques pures du poids portées de suivinut"
```

---

### Task 2: Pesées dans NutritionJournal

**Files:**
- Modify: `Cairn/Features/Nutrition/NutritionJournal.swift`
- Test: `Tests/NutritionJournalTests.swift` (ajouts)

**Interfaces:**
- Consumes: `WeightEntry` (`#Unique` sur `dateKeyRaw`, `weightKg`, `note: String?`), `DateKey`.
- Produces (utilisé par Task 3) :

```swift
extension NutritionJournal {
    /// One weigh-in per day: recording an existing day replaces it.
    @MainActor @discardableResult static func recordWeight(
        _ weightKg: Double, note: String?, for dateKey: DateKey,
        in context: ModelContext
    ) throws -> WeightEntry
    @MainActor static func deleteWeight(
        _ entry: WeightEntry, in context: ModelContext
    ) throws
}
```

Une note vide après trim devient `nil` (une note vide n'est pas une note, même règle que les notes de repas).

- [ ] **Step 1: Écrire les tests qui échouent** (ajouts dans `NutritionJournalTests`)

```swift
    @Test("une pesée par jour : ressaisir remplace")
    func weightUpsertsPerDay() throws {
        let context = try makeContext()
        let key = DateKey(raw: "2026-08-08")!

        try NutritionJournal.recordWeight(71.4, note: "matin", for: key, in: context)
        try NutritionJournal.recordWeight(71.2, note: nil, for: key, in: context)

        let entries = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(entries.count == 1)
        #expect(entries[0].weightKg == 71.2)
        #expect(entries[0].note == nil)
    }

    @Test("la note d'une pesée se vide en nil après trim")
    func weightNoteTrimsToNil() throws {
        let context = try makeContext()
        let entry = try NutritionJournal.recordWeight(
            70.9, note: "   ", for: DateKey(raw: "2026-08-07")!, in: context
        )
        #expect(entry.note == nil)
    }

    @Test("la suppression d'une pesée retire sa ligne")
    func weightDeletes() throws {
        let context = try makeContext()
        let entry = try NutritionJournal.recordWeight(
            71.0, note: nil, for: DateKey(raw: "2026-08-08")!, in: context
        )
        try NutritionJournal.deleteWeight(entry, in: context)
        #expect(try context.fetch(FetchDescriptor<WeightEntry>()).isEmpty)
    }
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter** (ajout dans `NutritionJournal.swift`)

```swift
extension NutritionJournal {
    /// Upsert on the day: the `#Unique` constraint would make a second insert
    /// collide, and "one weigh-in per day, re-entering replaces" is the
    /// suivinut contract the importer's data already follows.
    @MainActor @discardableResult
    static func recordWeight(
        _ weightKg: Double, note: String?, for dateKey: DateKey,
        in context: ModelContext
    ) throws -> WeightEntry {
        let cleanNote = note?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = (cleanNote?.isEmpty ?? true) ? nil : cleanNote
        let raw = dateKey.raw
        if let existing = try context.fetch(
            FetchDescriptor<WeightEntry>(
                predicate: #Predicate { $0.dateKeyRaw == raw }
            )
        ).first {
            existing.weightKg = weightKg
            existing.note = finalNote
            try context.save()
            return existing
        }
        let entry = WeightEntry(dateKey: dateKey, weightKg: weightKg, note: finalNote)
        context.insert(entry)
        try context.save()
        return entry
    }

    @MainActor
    static func deleteWeight(
        _ entry: WeightEntry, in context: ModelContext
    ) throws {
        context.delete(entry)
        try context.save()
    }
}
```

- [ ] **Step 4: Vérifier le succès** — suite `NutritionJournalTests` complète.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/NutritionJournal.swift Tests/NutritionJournalTests.swift
git commit -m "feat(poids): pesées upsert par jour dans NutritionJournal"
```

---

### Task 3: WeightView — graphe, tuiles et liste des pesées

**Files:**
- Create: `Cairn/Features/Nutrition/WeightPeriod.swift`, `Cairn/Features/Nutrition/WeightEntrySheet.swift`, `Cairn/Features/Nutrition/WeightView.swift`
- Test: `Tests/WeightPeriodTests.swift`

**Interfaces:**
- Consumes: `WeightStats`/`WeightPoint` (Task 1), `NutritionJournal.recordWeight/deleteWeight` (Task 2), `NutritionSettings.weightGoalKey`, `StatTile`, `Format` (`typedNumber`, `dateOnly`), `DateKey`.
- Produces (utilisé par Task 4) : `WeightView(onCommand:)` — même contrat que `NutritionDayView` (closure vim + porte modale interne).

- [ ] **Step 1: WeightPeriod + son test**

```swift
// Cairn/Features/Nutrition/WeightPeriod.swift
import Foundation

/// The chart window. Persisted so the screen reopens the way it was left —
/// same rule as `StatsPeriod`.
enum WeightPeriod: String, CaseIterable, Identifiable {
    case thirtyDays
    case ninetyDays
    case year
    case all

    static let storageKey = "weightPeriod"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .thirtyDays: return "30 j"
        case .ninetyDays: return "90 j"
        case .year: return "1 an"
        case .all: return "Tout"
        }
    }

    /// nil = no cutoff, every weigh-in.
    var days: Int? {
        switch self {
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}
```

```swift
// Tests/WeightPeriodTests.swift
import Testing
@testable import Cairn

@Suite("WeightPeriod")
struct WeightPeriodTests {
    @Test("chaque période porte sa fenêtre en jours")
    func daysPerPeriod() {
        #expect(WeightPeriod.thirtyDays.days == 30)
        #expect(WeightPeriod.ninetyDays.days == 90)
        #expect(WeightPeriod.year.days == 365)
        #expect(WeightPeriod.all.days == nil)
    }

    @Test("le rawValue est stable pour l'AppStorage")
    func rawValuesAreStable() {
        // Persisted in user defaults: renaming a case would silently reset
        // the user's chosen window.
        #expect(WeightPeriod(rawValue: "thirtyDays") == .thirtyDays)
        #expect(WeightPeriod(rawValue: "all") == .all)
    }
}
```

Vérifier l'échec (compilation), implémenter, vérifier le succès sur `-only-testing:CairnTests/WeightPeriodTests`.

- [ ] **Step 2: La sheet de pesée**

```swift
// Cairn/Features/Nutrition/WeightEntrySheet.swift
import SwiftUI
import SwiftData

/// One weigh-in: date, kilograms, optional note. Editing re-records on the
/// chosen day (one weigh-in per day, re-entry replaces); moving an existing
/// entry to another day deletes the original row.
struct WeightEntrySheet: View {
    let existing: WeightEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var weightKg: Double
    @State private var note: String
    @State private var errorMessage: String?

    init(existing: WeightEntry?, defaultWeightKg: Double) {
        self.existing = existing
        _date = State(initialValue: existing?.dateKey?.date() ?? Date())
        _weightKg = State(initialValue: existing?.weightKg ?? defaultWeightKg)
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "Nouvelle pesée" : "Modifier la pesée")
                .font(.headline)
            DatePicker(
                "Date", selection: $date, in: ...Date(),
                displayedComponents: .date
            )
            HStack(spacing: 8) {
                Text("Poids")
                TextField("kg", value: $weightKg, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("kg")
            }
            TextField("Note (optionnelle)", text: $note)
                .textFieldStyle(.roundedBorder)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(weightKg <= 0)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }

    private func save() {
        let key = DateKey(date)
        do {
            try NutritionJournal.recordWeight(
                weightKg, note: note, for: key, in: modelContext
            )
            // Moving an entry to another day: the upsert above created (or
            // replaced) the target day — the original row must not linger.
            if let existing, !existing.isDeleted, existing.dateKeyRaw != key.raw {
                try NutritionJournal.deleteWeight(existing, in: modelContext)
            }
            dismiss()
        } catch {
            errorMessage =
                "La pesée n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 3: La vue Poids**

```swift
// Cairn/Features/Nutrition/WeightView.swift
import SwiftUI
import SwiftData
import Charts

/// The weight screen — suivinut's weight graph, stats and editable list in
/// one place. Chart idioms follow `StatisticsView` (Swift Charts, system
/// colours); write paths follow `NutritionDayView` (NutritionJournal +
/// failure alert + the vim gate while a sheet is up).
struct WeightView: View {
    /// Forwarded window-level vim commands, same contract as
    /// `NutritionDayView.onCommand`.
    let onCommand: (VimCommand) -> Bool

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.dateKeyRaw) private var entries: [WeightEntry]
    @AppStorage(WeightPeriod.storageKey) private var period: WeightPeriod = .ninetyDays
    @AppStorage(NutritionSettings.weightGoalKey)
    private var weightGoal = NutritionSettings.defaultWeightGoalKg
    @State private var isAddingEntry = false
    @State private var editingEntry: WeightEntry?
    @State private var writeFailureMessage: String?

    private var isPresentingModal: Bool {
        isAddingEntry || editingEntry != nil || writeFailureMessage != nil
    }

    /// Sorted ascending by the query; the raw string sorts chronologically.
    private var points: [WeightPoint] {
        entries.compactMap { entry in
            entry.dateKey.map { WeightPoint(dateKey: $0, weightKg: entry.weightKg) }
        }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Aucune pesée", systemImage: "scalemass")
                } description: {
                    Text("Consignez votre poids pour suivre la tendance.")
                } actions: {
                    Button("Nouvelle pesée…") { isAddingEntry = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                content
            }
        }
        .vimKeys(enabled: !isPresentingModal, onCommand)
        .sheet(isPresented: $isAddingEntry) {
            WeightEntrySheet(existing: nil, defaultWeightKg: defaultWeight)
        }
        .sheet(item: $editingEntry) { entry in
            WeightEntrySheet(existing: entry, defaultWeightKg: defaultWeight)
        }
        .alert(
            "Écriture impossible",
            isPresented: Binding(
                get: { writeFailureMessage != nil },
                set: { if !$0 { writeFailureMessage = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(writeFailureMessage ?? "")
        }
    }

    /// The last weigh-in is the least surprising prefill for a new one.
    private var defaultWeight: Double {
        entries.last?.weightKg ?? weightGoal
    }

    // MARK: - Content

    private var content: some View {
        let windowed = WeightStats.window(points, days: period.days)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Poids")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Picker("Période", selection: $period) {
                        ForEach(WeightPeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Button {
                        isAddingEntry = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Nouvelle pesée")
                }
                chart(windowed)
                tiles
                Divider()
                list
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chart(_ windowed: [WeightPoint]) -> some View {
        Chart {
            ForEach(windowed, id: \.dateKey.raw) { point in
                LineMark(
                    x: .value("Date", point.dateKey.date()),
                    y: .value("Poids", point.weightKg)
                )
                PointMark(
                    x: .value("Date", point.dateKey.date()),
                    y: .value("Poids", point.weightKg)
                )
                .symbolSize(20)
            }
            if weightGoal > 0 {
                RuleMark(y: .value("Objectif", weightGoal))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .bottomTrailing) {
                        Text("Objectif \(Format.typedNumber(weightGoal)) kg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
            }
            // The period minimum, green like suivinut's braille graph: the
            // floor already reached is the encouraging line.
            if let minimum = windowed.map(\.weightKg).min() {
                RuleMark(y: .value("Minimum", minimum))
                    .foregroundStyle(.green.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: yDomain(windowed))
        .frame(height: 220)
    }

    /// Fitted rather than zero-based: a weight chart from zero flattens a
    /// 3 kg trend into an invisible wiggle. The goal line stays in frame.
    private func yDomain(_ windowed: [WeightPoint]) -> ClosedRange<Double> {
        let values = windowed.map(\.weightKg)
            + (weightGoal > 0 ? [weightGoal] : [])
        guard let low = values.min(), let high = values.max() else {
            return 0...100
        }
        return (low - 0.5)...(high + 0.5)
    }

    private var tiles: some View {
        HStack(alignment: .top, spacing: 24) {
            if let current = points.last {
                StatTile("Poids actuel", "\(Format.typedNumber(current.weightKg)) kg")
            }
            if let delta = WeightStats.delta(points) {
                StatTile("Δ 7 jours", signed(delta) + " kg")
            }
            if let rate = WeightStats.ratePerWeek(points) {
                StatTile("Rythme", signed(rate) + " kg/sem")
            }
            if weightGoal > 0,
               let weeks = WeightStats.weeksToGoal(points, goal: weightGoal) {
                StatTile("Objectif", "~\(Int(weeks.rounded())) sem")
            }
        }
    }

    private func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "−") + Format.typedNumber(abs(value))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pesées")
                .font(.headline)
            // Newest first: the row being checked or fixed is almost always
            // the latest one.
            ForEach(entries.reversed(), id: \.persistentModelID) { entry in
                HStack(spacing: 16) {
                    Text(entry.dateKey.map { Format.dateOnly($0.date()) } ?? entry.dateKeyRaw)
                        .frame(width: 110, alignment: .leading)
                    Text("\(Format.typedNumber(entry.weightKg)) kg")
                        .monospacedDigit()
                        .frame(width: 70, alignment: .trailing)
                    if let note = entry.note {
                        Text(note)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                .contentShape(.rect)
                .contextMenu {
                    Button("Éditer…") { editingEntry = entry }
                    Divider()
                    Button("Supprimer", role: .destructive) { delete(entry) }
                }
            }
        }
    }

    private func delete(_ entry: WeightEntry) {
        do {
            try NutritionJournal.deleteWeight(entry, in: modelContext)
        } catch {
            writeFailureMessage =
                "Votre suppression n'a pas pu être enregistrée. \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 4: Builder et lancer la suite complète**

Run:
```bash
xcodegen generate && xcodebuild build -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | tail -3
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests 2>&1 | tail -3
```
Expected: build OK, suite verte.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/WeightPeriod.swift Cairn/Features/Nutrition/WeightEntrySheet.swift Cairn/Features/Nutrition/WeightView.swift Tests/WeightPeriodTests.swift
git commit -m "feat(poids): écran Poids avec graphe, statistiques et pesées éditables"
```

---

### Task 4: Entrée sidebar et routage

**Files:**
- Modify: `Cairn/App/SidebarView.swift` (enum + label)
- Modify: `Cairn/App/RootView.swift` (helper + branche de routage)

**Interfaces:**
- Consumes: `WeightView(onCommand:)` (Task 3), `SidebarItem`, `performInNutrition` (existant — le filtre vaut pour tout écran du journal, poids compris).
- Produces: `SidebarItem.weight`, entrée « Poids » sous « Alimentation ».

- [ ] **Step 1: Sidebar**

Dans `SidebarView.swift`, l'enum devient :

```swift
enum SidebarItem: Hashable {
    case all
    case globalMap
    case statistics
    case nutrition
    case weight
}
```

et sous le label Alimentation :

```swift
                Label("Alimentation", systemImage: "fork.knife")
                    .tag(SidebarItem.nutrition)
                Label("Poids", systemImage: "scalemass")
                    .tag(SidebarItem.weight)
```

- [ ] **Step 2: Routage**

Dans `RootView.swift`, à côté de `showsNutrition` :

```swift
    private var showsWeight: Bool { sidebarSelection == .weight }
```

et dans `splitView`, après la branche `showsNutrition` :

```swift
                } else if showsWeight {
                    // Same command filter as the food journal: the weight
                    // screen is journal territory too, an invisible activity
                    // selection must stay unreachable from it.
                    WeightView(onCommand: performInNutrition)
                } else {
```

- [ ] **Step 3: Builder et lancer la suite complète** — build OK, suite verte (l'ajout du cas d'enum ne casse aucun `switch` exhaustif : `VimCommand` ne fait que transporter `SidebarItem`).

- [ ] **Step 4: Vérification visuelle**

En mode démo (`STRAVALOCAL_DEMO=1`, store séparé) : cliquer « Poids » (état vide + « Nouvelle pesée… »), ajouter quelques pesées à des dates différentes, vérifier graphe (ligne objectif pointillée, ligne verte du minimum), les tuiles, le picker de période, l'édition (y compris déplacer une pesée vers une autre date), la suppression. Si le vrai journal a été importé dans le store de démo à la phase 3, les 51 pesées réelles doivent peupler le graphe d'office.

- [ ] **Step 5: Commit**

```bash
git add Cairn/App/SidebarView.swift Cairn/App/RootView.swift
git commit -m "feat(alimentation): entrée sidebar Poids et routage"
```

---

## Après cette phase

Phase 5 (plan séparé) : pipeline catalogue — téléchargement de l'export CSV OFF avec reprise validée ETag/If-Range (contrat de `data/download.py`), décompression et parsing TSV en flux, filtres `FILTER_SQL`, bascule atomique, progression et annulation dans Réglages → Nutrition (remplacer le texte de statut par le bouton). Phase 6 : clavier (`gn`/`gp`, raccourcis d'écran), colonne détail d'Alimentation (mini-calendrier + panneau stats — `loggingStreak` et `WeightStats` sont prêts), drag de réordonnancement, message d'erreur de recherche, volet détail activité résiduel, et les reliquats mineurs des ledgers de phases 2-3.
