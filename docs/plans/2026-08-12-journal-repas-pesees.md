# Les notes de repas et de pesée dans le journal — plan d'implémentation

> **Pour un agent :** SOUS-COMPÉTENCE REQUISE — `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour dérouler ce plan tâche par
> tâche. Les étapes sont des cases à cocher (`- [ ]`).

**But :** faire entrer dans le journal le texte écrit dans le journal
alimentaire — la note d'un repas et le commentaire d'une pesée — comme y entre
déjà la note d'une sortie.

**Architecture :** `JournalDay.activityNotes` devient `elsewhereNotes`, une
seule liste de ce qui a été écrit hors du coffre ; une fonction pure la
construit à partir des trois sources ; un nouveau bloc du volet affiche les
notes de repas et la pesée, rendues en Markdown.

**Pile :** Swift 6, SwiftUI, SwiftData, Swift Testing. Projet généré par
XcodeGen.

## Contraintes globales

- **Le journal lit, il n'écrit pas.** Aucune de ces notes ne devient éditable
  depuis le journal. Le coffre reste la seule chose que Cairn écrit.
- **Le texte seul fait exister un jour.** Une pesée sans commentaire n'apparaît
  ni dans la liste ni dans le volet. Un repas consigné sans note non plus.
- **Commentaires de code en anglais**, comme le reste du dépôt ; **noms de
  tests et chaînes affichées en français**.
- **Après tout ajout de fichier source : `xcodegen generate`.** Sans quoi le
  fichier n'est dans aucune cible et le test ne compile pas.
- Lancer les tests :
  `xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build`
  Ajouter `-only-testing:CairnTests/<Suite>` pour n'en lancer qu'une.

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `Cairn/Features/Journal/JournalDay.swift` | modifié : `activityNotes` → `elsewhereNotes` |
| `Cairn/Features/Journal/JournalDaySources.swift` | **créé** : groupe les trois sources par jour |
| `Cairn/Features/Journal/JournalDayNutrition.swift` | **créé** : le bloc du volet |
| `Cairn/Features/Journal/JournalDetailView.swift` | modifié : pose le bloc sous celui des activités |
| `Cairn/App/RootView.swift` | modifié : deux requêtes de plus, la collecte déléguée |
| `Tests/JournalDayTests.swift` | modifié : le nom du paramètre |
| `Tests/JournalDaySourcesTests.swift` | **créé** |
| `Tests/JournalDayNutritionTests.swift` | **créé** |

---

### Tâche 1 : `activityNotes` devient `elsewhereNotes`

Renommage seul, aucun comportement ne change. Les tests existants sont le
garde-fou : ils doivent passer sans qu'une seule assertion soit modifiée, hors
nom de propriété.

**Fichiers :**
- Modifier : `Cairn/Features/Journal/JournalDay.swift`
- Modifier : `Cairn/App/RootView.swift:370`
- Modifier : `Tests/JournalDayTests.swift`

**Interfaces produites :**
- `JournalDay.elsewhereNotes: [String]`
- `JournalDay.init(date: DateKey, note: JournalNote? = nil, elsewhereNotes: [String] = [])`
- `JournalDay.merge(notes: [JournalNote], elsewhereNotes: [DateKey: [String]]) -> [JournalDay]`

- [ ] **Étape 1 : renommer dans `JournalDay.swift`**

Quatre endroits. La propriété et son commentaire :

```swift
    /// What was written about this day anywhere but the vault: an outing's own
    /// note, a meal's, a weigh-in's. One list and not three, because nothing
    /// downstream asks where a sentence came from — the row's summary, the
    /// search and the tags all want the text and nothing else. The pane, which
    /// does need to tell them apart, does not read this: it queries the store
    /// for the day itself.
    ///
    /// In the order a day is lived: the outings first, then the meals, the
    /// weigh-in last. That order is what picks the line standing for a day
    /// with no file of its own.
    let elsewhereNotes: [String]
```

L'init :

```swift
    init(date: DateKey, note: JournalNote? = nil, elsewhereNotes: [String] = []) {
        self.date = date
        self.note = note ?? JournalNote(date: date, text: "")
        self.elsewhereNotes = elsewhereNotes
    }
```

Puis, dans le corps du type, remplacer les quatre lectures de `activityNotes`
par `elsewhereNotes` : dans `tags`, dans `summary`, dans `matches(query:)` et
dans `excerpt(matching:)`. Enfin la signature de `merge` :

```swift
    static func merge(
        notes: [JournalNote], elsewhereNotes: [DateKey: [String]]
    ) -> [JournalDay] {
        var days: [JournalDay] = notes.map {
            JournalDay(
                date: $0.date, note: $0,
                elsewhereNotes: spoken(elsewhereNotes[$0.date])
            )
        }
        let written = Set(notes.map(\.date))
        for (date, texts) in elsewhereNotes where !written.contains(date) {
            let said = spoken(texts)
            guard !said.isEmpty else { continue }
            days.append(JournalDay(date: date, elsewhereNotes: said))
        }
        return days.sorted { $0.date > $1.date }
    }
```

Le commentaire de `merge` parle des « outings » : remplacer cette phrase par
« A day that exists only because something was written elsewhere is added only
when that text says something: a day trained on, eaten through and weighed in
silence is not a journal entry. »

- [ ] **Étape 2 : renommer chez les appelants**

Dans `Tests/JournalDayTests.swift`, remplacer les treize occurrences de
`activityNotes:` par `elsewhereNotes:` et l'unique lecture
`days[0].activityNotes` par `days[0].elsewhereNotes`. Ne toucher à rien
d'autre : les valeurs attendues sont la preuve que le renommage ne change rien.

Dans `Cairn/App/RootView.swift:370` :

```swift
        return JournalDay.merge(notes: app.journal.notes, elsewhereNotes: byDay)
```

- [ ] **Étape 3 : compiler et lancer toute la suite**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|Test run with"
```

Attendu : `Test run with 707 tests` — le compte d'avant le plan, inchangé :
un renommage n'ajoute pas de test. Si le compilateur signale
un `activityNotes` restant, c'est un appelant oublié : le corriger.

- [ ] **Étape 4 : commiter**

```bash
git add Cairn/Features/Journal/JournalDay.swift Cairn/App/RootView.swift Tests/JournalDayTests.swift
git commit -m "refactor(journal): activityNotes devient elsewhereNotes"
```

---

### Tâche 2 : la collecte des trois sources

**Fichiers :**
- Créer : `Cairn/Features/Journal/JournalDaySources.swift`
- Créer : `Tests/JournalDaySourcesTests.swift`
- Modifier : `Cairn/App/RootView.swift` (requêtes et `journalDays`)

**Interfaces consommées :** `JournalDay.merge(notes:elsewhereNotes:)` (tâche 1).

**Interfaces produites :**
```swift
@MainActor
enum JournalDaySources {
    static func elsewhereNotes(
        activities: [Activity], mealNotes: [MealNote], weights: [WeightEntry]
    ) -> [DateKey: [String]]
}
```

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `Tests/JournalDaySourcesTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Les sources d'un jour de journal")
@MainActor
struct JournalDaySourcesTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    /// Un contexte en mémoire : `MealNote` référence un `MealSlot`, et une
    /// relation SwiftData veut un store, même jetable.
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    @Test("un jour rassemble ses sorties, ses repas et sa pesée dans l'ordre")
    func groupsEverythingWrittenThatDay() throws {
        let context = try makeContext()
        let breakfast = MealSlot(name: "Petit-déj", sortOrder: 0, targetPct: 28)
        let dinner = MealSlot(name: "Dîner", sortOrder: 3, targetPct: 39)
        context.insert(breakfast)
        context.insert(dinner)

        let activity = Activity(stravaID: 1, name: "Footing", sportType: .run)
        // 2026-08-11 à 08:00 UTC : le jour se lit dans le calendrier local,
        // et une heure du matin ne bascule pas de jour en France.
        activity.startDate = Date(timeIntervalSince1970: 1_786_003_200)
        activity.activityDescription = "Jambes lourdes."
        context.insert(activity)

        let lateMeal = MealNote(
            dateKey: key("2026-08-11"), mealSlot: dinner, note: "Sushi."
        )
        let earlyMeal = MealNote(
            dateKey: key("2026-08-11"), mealSlot: breakfast, note: "Skyr."
        )
        context.insert(lateMeal)
        context.insert(earlyMeal)
        let weight = WeightEntry(
            dateKey: key("2026-08-11"), weightKg: 70.2, note: "Bien dormi."
        )
        context.insert(weight)

        let byDay = JournalDaySources.elsewhereNotes(
            activities: [activity], mealNotes: [lateMeal, earlyMeal],
            weights: [weight]
        )

        // Les sorties, puis les repas dans l'ordre de la journée, la pesée en
        // dernier — c'est cet ordre qui décide de la ligne résumant le jour.
        #expect(
            byDay[key("2026-08-11")]
                == ["Jambes lourdes.", "Skyr.", "Sushi.", "Bien dormi."]
        )
    }

    @Test("une pesée muette n'écrit rien")
    func asilentWeighInSaysNothing() throws {
        let context = try makeContext()
        let weight = WeightEntry(dateKey: key("2026-08-10"), weightKg: 70.2)
        context.insert(weight)
        let blank = WeightEntry(
            dateKey: key("2026-08-09"), weightKg: 70.4, note: "  \n "
        )
        context.insert(blank)

        let byDay = JournalDaySources.elsewhereNotes(
            activities: [], mealNotes: [], weights: [weight, blank]
        )
        #expect(byDay.isEmpty)
    }

    @Test("une note de repas suffit à faire exister un jour")
    func amealNoteAloneMakesADay() throws {
        let context = try makeContext()
        let lunch = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(lunch)
        let note = MealNote(
            dateKey: key("2026-08-08"), mealSlot: lunch, note: "Amie #Sushi."
        )
        context.insert(note)

        let days = JournalDay.merge(
            notes: [],
            elsewhereNotes: JournalDaySources.elsewhereNotes(
                activities: [], mealNotes: [note], weights: []
            )
        )
        #expect(days.map(\.date.raw) == ["2026-08-08"])
        #expect(days[0].summary == "Amie #Sushi.")
        // Le tag compte comme celui d'une sortie : c'est la même personne qui
        // l'a écrit, et la barre latérale doit le lister.
        #expect(days[0].tags.contains(JournalTag(name: "Sushi")!))
    }

    @Test("la recherche trouve un jour par le texte d'un repas, et le cite")
    func searchReachesAMealNote() throws {
        let context = try makeContext()
        let lunch = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(lunch)
        let meal = MealNote(
            dateKey: key("2026-08-08"), mealSlot: lunch,
            note: "Amie Sushi, pétage de bide."
        )
        context.insert(meal)
        let activity = Activity(stravaID: 2, name: "Footing", sportType: .run)
        activity.startDate = Date(timeIntervalSince1970: 1_785_744_000)
        activity.activityDescription = "Jambes lourdes."
        context.insert(activity)

        let days = JournalDay.merge(
            notes: [],
            elsewhereNotes: JournalDaySources.elsewhereNotes(
                activities: [activity], mealNotes: [meal], weights: []
            )
        )
        #expect(days.count == 1)
        // La sortie a écrit la première : c'est elle qui donne la ligne.
        #expect(days[0].summary == "Jambes lourdes.")
        #expect(days[0].matches(query: "sushi"))
        #expect(days[0].excerpt(matching: "sushi")?.contains("pétage") == true)
    }

    @Test("un repas sans note ne raconte rien")
    func anuntoldMealStaysOut() throws {
        let context = try makeContext()
        let lunch = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(lunch)
        let empty = MealNote(dateKey: key("2026-08-08"), mealSlot: lunch, note: "")
        context.insert(empty)

        #expect(
            JournalDaySources.elsewhereNotes(
                activities: [], mealNotes: [empty], weights: []
            ).isEmpty
        )
    }
}
```

- [ ] **Étape 2 : le lancer et le voir échouer**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalDaySourcesTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: cannot find 'JournalDaySources' in scope`.

- [ ] **Étape 3 : écrire la fonction**

Créer `Cairn/Features/Journal/JournalDaySources.swift` :

```swift
import Foundation
import SwiftData

/// Everything written about a day outside the vault, gathered per day.
///
/// A function and not a view's private helper: the collection is the rule that
/// decides which days the journal lists at all, and a rule worth stating is a
/// rule worth testing. `RootView` holds the queries; this holds the meaning.
@MainActor
enum JournalDaySources {
    /// - Returns: the texts of a day, in the order the day was lived — the
    ///   outings first, then the meals in the order they are eaten, the
    ///   weigh-in last. `JournalDay.summary` takes the first of them for a day
    ///   with no file, so this order is what a row reads.
    ///
    /// Blank texts never enter: a meal note opened and closed without a word
    /// must not make a day appear, and a weigh-in is a figure, not a sentence.
    /// The weigh-in's own comment is a sentence, and does count.
    static func elsewhereNotes(
        activities: [Activity], mealNotes: [MealNote], weights: [WeightEntry]
    ) -> [DateKey: [String]] {
        var byDay: [DateKey: [String]] = [:]

        func add(_ text: String?, to date: DateKey) {
            guard let text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            byDay[date, default: []].append(text)
        }

        // The day an outing belongs to is `DateKey` of its instant in this
        // Mac's calendar — the same rule `JournalDayActivities` filters the
        // recap by, so a day's row and a day's pane cannot disagree about
        // which outings are its own. Meals and weigh-ins need no such rule:
        // they are filed under a day, never under an instant.
        for activity in activities.sorted(by: { $0.startDate < $1.startDate }) {
            add(activity.activityDescription, to: DateKey(activity.startDate))
        }
        for meal in mealNotes.sorted(by: {
            ($0.mealSlot?.sortOrder ?? .max) < ($1.mealSlot?.sortOrder ?? .max)
        }) {
            guard let date = meal.dateKey else { continue }
            add(meal.note, to: date)
        }
        for weight in weights {
            guard let date = weight.dateKey else { continue }
            add(weight.note, to: date)
        }
        return byDay
    }
}
```

- [ ] **Étape 4 : le lancer et le voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalDaySourcesTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : `Test run with 5 tests in 1 suite passed`.

- [ ] **Étape 5 : brancher `RootView`**

Ajouter les deux requêtes sous `notedActivities` (vers la ligne 86) :

```swift
    /// The journal reads what was written in the food journal too — a meal's
    /// note, a weigh-in's comment. Unfiltered: both tables hold one row per
    /// day at most, where the activities needed narrowing to the few dozen
    /// carrying a note.
    @Query private var mealNotes: [MealNote]
    @Query private var weightEntries: [WeightEntry]
```

Puis remplacer le corps de `journalDays` (lignes 364-371) par :

```swift
    private var journalDays: [JournalDay] {
        JournalDay.merge(
            notes: app.journal.notes,
            elsewhereNotes: JournalDaySources.elsewhereNotes(
                activities: notedActivities, mealNotes: mealNotes,
                weights: weightEntries
            )
        )
    }
```

Et son commentaire de tête, qui décrit l'ancienne mécanique, devient :

```swift
    /// Every day the journal knows about: the vault's notes, and the days
    /// something was written about elsewhere — an outing, a meal, a weigh-in.
    ///
    /// The activities arrive already narrowed to the ones that wrote something
    /// (`notedActivities`), so this groups a few dozen rows rather than the
    /// whole library. Where each text belongs is `JournalDaySources`'s
    /// business, not this view's.
```

- [ ] **Étape 6 : toute la suite, puis commiter**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|✘|Test run with"
git add Cairn/Features/Journal/JournalDaySources.swift Tests/JournalDaySourcesTests.swift Cairn/App/RootView.swift Cairn.xcodeproj
git commit -m "feat(journal): les notes de repas et de pesée entrent dans la liste"
```

Attendu : 712 tests, tous verts.

---

### Tâche 3 : le bloc du volet

**Fichiers :**
- Créer : `Cairn/Features/Journal/JournalDayNutrition.swift`
- Créer : `Tests/JournalDayNutritionTests.swift`
- Modifier : `Cairn/Features/Journal/JournalDetailView.swift:155`

**Interfaces produites :**
```swift
struct JournalDayNutrition: View {
    init(date: DateKey)
    static func label(for note: MealNote) -> String
    static func weightLine(_ entry: WeightEntry) -> String
}
```

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `Tests/JournalDayNutritionTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Le bloc alimentation du volet du journal")
@MainActor
struct JournalDayNutritionTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    @Test("la note d'un repas est annoncée par le repas")
    func amealNoteIsNamedByItsMeal() throws {
        let context = try makeContext()
        let lunch = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(lunch)
        let note = MealNote(dateKey: key("2026-08-12"), mealSlot: lunch, note: "Sushi.")
        context.insert(note)

        #expect(JournalDayNutrition.label(for: note) == "Déjeuner")
    }

    @Test("un repas disparu ne laisse pas d'étiquette vide")
    func aslotlessNoteKeepsAName() throws {
        let context = try makeContext()
        let orphan = MealNote(dateKey: key("2026-08-12"), mealSlot: nil, note: "Sushi.")
        context.insert(orphan)

        // Supprimer un repas dans les réglages laisse ses notes derrière lui ;
        // une puce sans nom serait plus déroutante qu'un mot générique.
        #expect(JournalDayNutrition.label(for: orphan) == "Repas")
    }

    @Test("la pesée s'écrit avec sa virgule et son unité")
    func theweighInReadsAsAWeight() throws {
        let context = try makeContext()
        let entry = WeightEntry(
            dateKey: key("2026-08-12"), weightKg: 70.2, note: "Bien dormi."
        )
        context.insert(entry)

        // `Format.typedNumber` écrit 70,2 et non 70.2 : les chiffres du poids
        // se lisent en français partout ailleurs dans l'application.
        #expect(JournalDayNutrition.weightLine(entry) == "70,2 kg")
    }

    @Test("un poids rond ne traîne pas de décimale")
    func aroundWeightHasNoTrailingZero() throws {
        let context = try makeContext()
        let entry = WeightEntry(dateKey: key("2026-08-12"), weightKg: 70)
        context.insert(entry)

        #expect(JournalDayNutrition.weightLine(entry) == "70 kg")
    }
}
```

- [ ] **Étape 2 : le lancer et le voir échouer**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalDayNutritionTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: cannot find 'JournalDayNutrition' in scope`.

- [ ] **Étape 3 : écrire la vue**

Créer `Cairn/Features/Journal/JournalDayNutrition.swift` :

```swift
import SwiftUI
import SwiftData

/// What the day's food journal said in words — a meal's note, a weigh-in's
/// comment — beside the note written about the day itself.
///
/// A sister of `JournalDayActivities`, and silent on the same terms: a heading
/// over an empty list says less than no heading. Most days have neither.
///
/// Its own queries rather than a list handed down from `RootView`, for the
/// reason given there: the note's pane rebuilds on every keystroke, and these
/// filter on `dateKeyRaw`, a string equality, where the outings needed a range
/// of instants.
struct JournalDayNutrition: View {
    let date: DateKey

    /// Read against `JournalDetailView.noteSize` — the note this pane is for,
    /// at 15. The same pair as the activities' recap, so the two blocks under
    /// a note rank equally and neither shouts over the other.
    private static let noteSize: CGFloat = 14
    private static let headingSize: CGFloat = 13

    @Query private var mealNotes: [MealNote]
    @Query private var weights: [WeightEntry]

    init(date: DateKey) {
        self.date = date
        let raw = date.raw
        _mealNotes = Query(filter: #Predicate<MealNote> { $0.dateKeyRaw == raw })
        _weights = Query(filter: #Predicate<WeightEntry> { $0.dateKeyRaw == raw })
    }

    /// The meals that said something, in the order they are eaten.
    ///
    /// Sorted here and not in the query: the order lives on the slot, across a
    /// relationship, and a `SortDescriptor` cannot reach through one.
    private var spokenMeals: [MealNote] {
        mealNotes
            .filter { !Self.isBlank($0.note) }
            .sorted {
                ($0.mealSlot?.sortOrder ?? .max) < ($1.mealSlot?.sortOrder ?? .max)
            }
    }

    /// The day's weigh-in, and only when it carries a comment: the figure
    /// alone belongs to the food journal, which shows it already.
    private var spokenWeight: WeightEntry? {
        weights.first { !Self.isBlank($0.note) }
    }

    private static func isBlank(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The name a meal note is announced by. Never empty: deleting a meal in
    /// the settings leaves its notes behind, and a nameless chip would puzzle
    /// more than a generic word.
    static func label(for note: MealNote) -> String {
        let name = note.mealSlot?.name ?? ""
        return name.isEmpty ? "Repas" : name
    }

    /// The weight, written the way it is written everywhere else in the app:
    /// a comma, and no trailing zero on a round figure.
    static func weightLine(_ entry: WeightEntry) -> String {
        "\(Format.typedNumber(entry.weightKg)) kg"
    }

    var body: some View {
        if !spokenMeals.isEmpty || spokenWeight != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Alimentation du jour")
                    .font(.system(size: Self.headingSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(spokenMeals) { note in
                    block(Self.label(for: note), note.note)
                }
                if let spokenWeight {
                    block(Self.weightLine(spokenWeight), spokenWeight.note ?? "")
                }
            }
        }
    }

    /// One card: what it is, then what was written about it.
    ///
    /// The heading is a `Text` and the note is rendered — the meal's name and
    /// the weight are labels, the note is prose somebody wrote, and it is read
    /// here exactly as it is read in its own pane: Markdown, without the `#`
    /// of a tag.
    private func block(_ heading: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading)
                .font(.system(size: Self.headingSize))
                .foregroundStyle(.secondary)
            MarkdownText(
                markdown: note, baseSize: Self.noteSize, hidesTagHashes: true
            )
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 5))
    }
}
```

- [ ] **Étape 4 : le lancer et le voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalDayNutritionTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : `Test run with 4 tests in 1 suite passed`.

- [ ] **Étape 5 : poser le bloc dans le volet**

Dans `Cairn/Features/Journal/JournalDetailView.swift`, sous la ligne 155 :

```swift
            JournalDayActivities(date: day.date, onSelect: onSelectActivity)
            JournalDayNutrition(date: day.date)
```

Sous les activités et non au-dessus : on écrit son journal en pensant d'abord à
ce que le corps a fait de sa journée.

- [ ] **Étape 6 : compiler, lancer toute la suite, commiter**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|✘|Test run with"
git add Cairn/Features/Journal/JournalDayNutrition.swift Tests/JournalDayNutritionTests.swift Cairn/Features/Journal/JournalDetailView.swift Cairn.xcodeproj
git commit -m "feat(journal): le volet montre les notes de repas et la pesée du jour"
```

Attendu : 716 tests, tous verts.

- [ ] **Étape 7 : le vérifier à l'écran**

```bash
xcodebuild build -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build && open build/Build/Products/Debug/Cairn.app
```

Ouvrir le journal sur le 12 août 2026, qui porte une note de repas (« Amie
Sushi, pétage de bide… ») et une pesée. Attendu : le bloc apparaît sous les
activités, la note est rendue et non brute, et un jour sans note de repas ni
commentaire de pesée n'affiche aucun bloc.
