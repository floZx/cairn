# Exporter le journal en carnet PDF — plan d'implémentation

> **Pour un agent :** SOUS-COMPÉTENCE REQUISE — `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour dérouler ce plan tâche par
> tâche. Les étapes sont des cases à cocher (`- [ ]`).

**But :** produire depuis Cairn un PDF d'une période choisie — un carnet à
relire, une section par journée, avec les notes, les sorties, leurs cartes et
leurs courbes, les photos, l'alimentation et le poids.

**Architecture :** trois pièces pures et testables — la collecte, le rendu HTML,
le Markdown en HTML — plus une pièce impure qui fabrique les images, et une
dernière qui assemble et demande le PDF à `WKWebView`.

**Pile :** Swift 6, SwiftUI, SwiftData, MapKit, WebKit, Swift Testing. Projet
généré par XcodeGen.

**Spec :** `docs/specs/2026-08-12-export-journal-pdf-design.md`.

## Contraintes globales

- **Un carnet, pas une archive.** Le détail aliment par aliment, les tours et
  les champs Strava bruts n'entrent pas.
- **Un jour muet ne prend pas de place** : une journée n'entre que si elle porte
  au moins une note du coffre, une sortie, une note de repas ou de pesée, ou un
  poids.
- **Le document est autonome** : toutes les images en `data:` URI.
- **Aucun réglage d'apparence dans l'interface.** La feuille de style est la
  réponse.
- **Les unités sont celles de l'écran** : tout passe par `Format` — allure ou
  vitesse selon le sport, cadence en pas par minute à pied, poids à la virgule
  française.
- **Commentaires de code en anglais**, comme le reste du dépôt ; **noms de
  tests et chaînes affichées en français**.
- **Après tout ajout de fichier source : `xcodegen generate`.**
- Lancer les tests :
  `xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build`
  Ajouter `-only-testing:CairnTests/<Suite>` pour n'en lancer qu'une.
- La suite compte **721 tests** avant ce plan.

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `Cairn/Features/Shared/MarkdownHTML.swift` | **créé** : Markdown → HTML, adossé à `MarkdownParser` |
| `Cairn/Features/Export/JournalBook.swift` | **créé** : la collecte, pure |
| `Cairn/Features/Export/JournalBookHTML.swift` | **créé** : `[Journée] → String`, pure, feuille de style comprise |
| `Cairn/Features/Export/JournalBookAssets.swift` | **créé** : cartes, courbes, photos → `data:` URI |
| `Cairn/Features/Export/JournalBookExporter.swift` | **créé** : assemblage, `WKWebView.createPDF`, écriture |
| `Cairn/Features/Export/ExportJournalSheet.swift` | **créé** : les deux dates et la progression |
| `Cairn/App/AppEnvironment.swift` | modifié : un `requestExportJournalPDF` de plus |
| `Cairn/App/CairnApp.swift` | modifié : l'entrée de menu |
| `Cairn/App/RootView.swift` | modifié : branche la feuille |
| `Tests/MarkdownHTMLTests.swift` | **créé** |
| `Tests/JournalBookTests.swift` | **créé** |
| `Tests/JournalBookHTMLTests.swift` | **créé** |
| `Tests/JournalBookTrackSVGTests.swift` | **créé** |

L'ordre des tâches suit la chaîne : chaque pièce n'a besoin que des précédentes.

---

### Tâche 1 : le Markdown en HTML

Le carnet rend les mêmes notes que l'écran, avec le même parseur : une note ne
doit pas changer de forme selon qu'on la lit dans l'application ou dans le PDF.
`MarkdownParser.blocks(from:)` reconnaît déjà titres, puces, listes numérotées,
citations et paragraphes ; il ne reste que l'inline et l'échappement.

**Fichiers :**
- Créer : `Cairn/Features/Shared/MarkdownHTML.swift`
- Créer : `Tests/MarkdownHTMLTests.swift`

**Interfaces consommées :** `MarkdownParser.blocks(from:) -> [MarkdownBlock]`,
`MarkdownBlock.text`, `JournalTag.isAllowed(_:)`, `JournalTag.init?(name:)`.

**Interfaces produites :**
```swift
enum MarkdownHTML {
    static func render(_ markdown: String, hidingTagHashes: Bool = true) -> String
    static func escape(_ text: String) -> String
}
```

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `Tests/MarkdownHTMLTests.swift` :

```swift
import Testing
@testable import Cairn

@Suite("Markdown vers HTML")
struct MarkdownHTMLTests {
    @Test("les caractères réservés du HTML sont échappés")
    func escapesReservedCharacters() {
        #expect(MarkdownHTML.escape("a & b") == "a &amp; b")
        #expect(MarkdownHTML.escape("<script>") == "&lt;script&gt;")
        #expect(MarkdownHTML.escape("\"") == "&quot;")
        // L'esperluette d'abord, sinon &lt; devient &amp;lt;.
        #expect(MarkdownHTML.escape("&lt;") == "&amp;lt;")
    }

    @Test("chaque bloc du parseur a sa balise")
    func rendersEveryBlock() {
        #expect(MarkdownHTML.render("# Titre") == "<h1>Titre</h1>")
        #expect(MarkdownHTML.render("## Titre") == "<h2>Titre</h2>")
        #expect(MarkdownHTML.render("Bonjour.") == "<p>Bonjour.</p>")
        #expect(MarkdownHTML.render("> Cité") == "<blockquote>Cité</blockquote>")
    }

    @Test("les puces consécutives tiennent dans une seule liste")
    func groupsConsecutiveBullets() {
        let html = MarkdownHTML.render("- un\n- deux")
        #expect(html == "<ul><li>un</li><li>deux</li></ul>")
    }

    @Test("les listes numérotées gardent le numéro de l'auteur")
    func keepsTheAuthorsNumbering() {
        // Une liste qui commence à 3 est en général une erreur, mais la
        // renuméroter en douce est pire que la montrer.
        let html = MarkdownHTML.render("3. trois\n4. quatre")
        #expect(html == "<ol start=\"3\"><li>trois</li><li>quatre</li></ol>")
    }

    @Test("le gras, l'italique et le code passent en balises")
    func rendersInlineMarkup() {
        #expect(MarkdownHTML.render("un **gras**") == "<p>un <strong>gras</strong></p>")
        #expect(MarkdownHTML.render("un __gras__") == "<p>un <strong>gras</strong></p>")
        #expect(MarkdownHTML.render("un *penché*") == "<p>un <em>penché</em></p>")
        #expect(MarkdownHTML.render("un _penché_") == "<p>un <em>penché</em></p>")
        #expect(MarkdownHTML.render("du `code`") == "<p>du <code>code</code></p>")
    }

    @Test("le dièse d'un tag tombe, comme partout où une note se lit")
    func dropsTagHashes() {
        #expect(MarkdownHTML.render("Vu #Sam hier.") == "<p>Vu Sam hier.</p>")
        // `#2026` est une année, `# ` un titre : ni l'un ni l'autre n'est un tag.
        #expect(MarkdownHTML.render("En #2026.") == "<p>En #2026.</p>")
        #expect(
            MarkdownHTML.render("Vu #Sam.", hidingTagHashes: false)
                == "<p>Vu #Sam.</p>"
        )
    }

    @Test("le balisage ne peut pas injecter de HTML")
    func markupCannotInjectHTML() {
        #expect(
            MarkdownHTML.render("<b>gras</b>") == "<p>&lt;b&gt;gras&lt;/b&gt;</p>"
        )
        #expect(
            MarkdownHTML.render("# <img src=x>")
                == "<h1>&lt;img src=x&gt;</h1>"
        )
    }

    @Test("un texte vide ne produit rien")
    func emptyTextRendersNothing() {
        #expect(MarkdownHTML.render("") == "")
        #expect(MarkdownHTML.render("   \n  ") == "")
    }
}
```

- [ ] **Étape 2 : les lancer et les voir échouer**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MarkdownHTMLTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: cannot find 'MarkdownHTML' in scope`.

- [ ] **Étape 3 : écrire le rendu**

Créer `Cairn/Features/Shared/MarkdownHTML.swift` :

```swift
import Foundation

/// A note, as HTML — for the exported book.
///
/// Adossé au parseur de l'écran plutôt qu'à un second : `MarkdownParser`
/// decides what a heading, a bullet and a quotation are, and a note has to
/// come out the same shape in the book as in the pane. Only what the screen
/// leaves to `Text` — the inline markup — and what a file never needs —
/// escaping — are this type's own business.
enum MarkdownHTML {
    /// The characters that would otherwise be read as markup. Ampersand first:
    /// escaping it after `<` would turn `&lt;` into `&amp;lt;`.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func render(_ markdown: String, hidingTagHashes: Bool = true) -> String {
        var html = ""
        var openList: String?

        func closeList() {
            if let openList {
                html += "</\(openList)>"
            }
            openList = nil
        }

        for block in MarkdownParser.blocks(from: markdown) {
            let text = inline(block.text, hidingTagHashes: hidingTagHashes)
            switch block {
            case let .heading(level, _):
                closeList()
                html += "<h\(level)>\(text)</h\(level)>"
            case .paragraph:
                closeList()
                html += "<p>\(text)</p>"
            case .quote:
                closeList()
                html += "<blockquote>\(text)</blockquote>"
            case .bullet:
                if openList != "ul" {
                    closeList()
                    html += "<ul>"
                    openList = "ul"
                }
                html += "<li>\(text)</li>"
            case let .numbered(number, _):
                if openList != "ol" {
                    closeList()
                    // The author's own number, not a running count — the same
                    // rule `MarkdownBlock` states for the screen.
                    html += "<ol start=\"\(number)\">"
                    openList = "ol"
                }
                html += "<li>\(text)</li>"
            }
        }
        closeList()
        return html
    }

    /// Inline markup, over text that is escaped first: everything below works
    /// on a string where no `<` can be the author's, so a delimiter can be
    /// turned into a tag without a second thought.
    private static func inline(_ text: String, hidingTagHashes: Bool) -> String {
        var result = escape(text)
        result = spans(in: result, delimiter: "**", tag: "strong")
        result = spans(in: result, delimiter: "__", tag: "strong")
        result = spans(in: result, delimiter: "*", tag: "em")
        result = spans(in: result, delimiter: "_", tag: "em")
        result = spans(in: result, delimiter: "`", tag: "code")
        return hidingTagHashes ? withoutTagHashes(result) : result
    }

    /// Pairs of delimiters into tags, left to right. An unmatched delimiter is
    /// left where it is: a lone asterisk in a note is an asterisk.
    private static func spans(
        in text: String, delimiter: String, tag: String
    ) -> String {
        let parts = text.components(separatedBy: delimiter)
        guard parts.count > 2 else { return text }

        var result = parts[0]
        var index = 1
        while index < parts.count {
            // A closing delimiter is only a closing one if there is something
            // after it to close; the last odd part keeps its delimiter.
            if index + 1 < parts.count || parts.count % 2 == 1 {
                if index % 2 == 1 && index + 1 <= parts.count - 1 {
                    result += "<\(tag)>\(parts[index])</\(tag)>"
                } else {
                    result += parts[index]
                }
            } else {
                result += delimiter + parts[index]
            }
            index += 1
        }
        return result
    }

    /// Drops the `#` of every tag, by the rules `JournalTagScanner` states: the
    /// hash opens the run, `# ` is a heading and `#2026` is a year.
    private static func withoutTagHashes(_ text: String) -> String {
        var result = ""
        var previous: Character?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard character == "#", previous == nil || previous!.isWhitespace else {
                result.append(character)
                previous = character
                index = text.index(after: index)
                continue
            }
            var end = text.index(after: index)
            while end < text.endIndex, JournalTag.isAllowed(text[end]) {
                end = text.index(after: end)
            }
            let name = String(text[text.index(after: index)..<end])
            if JournalTag(name: name) != nil {
                result += name
            } else {
                result += "#" + name
            }
            previous = name.last ?? "#"
            index = end
        }
        return result
    }
}
```

- [ ] **Étape 4 : les lancer et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MarkdownHTMLTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : `Test run with 8 tests in 1 suite passed`. Si `spans(in:delimiter:tag:)`
échoue sur un cas, corriger l'implémentation, jamais l'assertion : c'est la
sortie attendue qui fait foi.

- [ ] **Étape 5 : commiter**

```bash
git add Cairn/Features/Shared/MarkdownHTML.swift Tests/MarkdownHTMLTests.swift
git commit -m "feat(export): le Markdown d'une note se rend en HTML"
```

---

### Tâche 2 : la collecte

**Fichiers :**
- Créer : `Cairn/Features/Export/JournalBook.swift`
- Créer : `Tests/JournalBookTests.swift`

**Interfaces consommées :** `JournalNote`, `JournalTag`, `Activity`,
`MealNote`, `WeightEntry`, `MealSlot`, `DateKey`, `SportType`.

**Interfaces produites :**
```swift
struct JournalBook: Equatable {
    struct Meal: Equatable {
        var name: String
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var note: String?
    }
    struct Day: Equatable {
        var date: DateKey
        var note: String
        var tags: [JournalTag]
        var activities: [Activity]
        var meals: [Meal]
        var weightKg: Double?
        var weightNote: String?
    }
    struct Totals: Equatable {
        var activityCount: Int
        var distance: Double
        var elevation: Double
        var movingTime: Int
        var bySport: [(sport: SportType, count: Int, distance: Double)]
        var firstWeightKg: Double?
        var lastWeightKg: Double?
    }
    var from: DateKey
    var to: DateKey
    var days: [Day]
    var totals: Totals

    static func build(
        from: DateKey, to: DateKey, notes: [JournalNote], activities: [Activity],
        entries: [FoodEntry], slots: [MealSlot], mealNotes: [MealNote],
        weights: [WeightEntry]
    ) -> JournalBook
}
```

`Totals.bySport` est un tableau de tuples, donc `Equatable` doit être écrit à la
main pour `Totals` — comparer les trois champs simples puis les tuples deux à
deux.

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `Tests/JournalBookTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("La collecte du carnet")
@MainActor
struct JournalBookTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    /// Une sortie le 11 août 2026 à 10:00 heure de Paris.
    private func makeRun(
        in context: ModelContext, id: Int64, at epoch: TimeInterval = 1_786_435_200,
        distance: Double = 10_000, elevation: Double = 100, movingTime: Int = 3000
    ) -> Activity {
        let activity = Activity(stravaID: id, name: "Footing", sportType: .run)
        activity.startDate = Date(timeIntervalSince1970: epoch)
        activity.distance = distance
        activity.totalElevationGain = elevation
        activity.movingTime = movingTime
        context.insert(activity)
        return activity
    }

    private func build(
        from: String = "2026-08-01", to: String = "2026-08-31",
        notes: [JournalNote] = [], activities: [Activity] = [],
        entries: [FoodEntry] = [], slots: [MealSlot] = [],
        mealNotes: [MealNote] = [], weights: [WeightEntry] = []
    ) -> JournalBook {
        JournalBook.build(
            from: key(from), to: key(to), notes: notes, activities: activities,
            entries: entries, slots: slots, mealNotes: mealNotes, weights: weights
        )
    }

    @Test("une journée muette n'entre pas dans le carnet")
    func asilentDayStaysOut() {
        #expect(build().days.isEmpty)
        #expect(build(notes: [JournalNote(date: key("2026-08-11"), text: "  ")]).days.isEmpty)
    }

    @Test("des aliments consignés sans un mot ne font pas une journée")
    func loggedFoodAloneIsNotAJournalDay() throws {
        // Consigner n'est pas écrire : la règle du journal vaut pour le carnet.
        // Le repas s'affichera si la journée existe pour une autre raison.
        let context = try makeContext()
        let slot = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(slot)
        let entry = try NutritionJournal.addEntry(
            in: context, dateKey: key("2026-08-03"), slot: slot, foodName: "Riz",
            kcal100: 350, protein100: 8, carbs100: 78, fat100: 1, grams: 200
        )

        #expect(build(entries: [entry], slots: [slot]).days.isEmpty)

        let withWeight = build(
            entries: [entry], slots: [slot],
            weights: [WeightEntry(dateKey: key("2026-08-03"), weightKg: 70.2)]
        )
        #expect(withWeight.days.count == 1)
        #expect(withWeight.days[0].meals.count == 1)
    }

    @Test("chacune des quatre sources fait exister une journée")
    func everySourceMakesADay() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(slot)

        let written = build(notes: [JournalNote(date: key("2026-08-02"), text: "Repos.")])
        #expect(written.days.map(\.date.raw) == ["2026-08-02"])

        let ran = build(activities: [makeRun(in: context, id: 1)])
        #expect(ran.days.map(\.date.raw) == ["2026-08-11"])

        let ate = build(
            slots: [slot],
            mealNotes: [MealNote(dateKey: key("2026-08-03"), mealSlot: slot, note: "Sushi.")]
        )
        #expect(ate.days.map(\.date.raw) == ["2026-08-03"])

        let weighed = build(weights: [WeightEntry(dateKey: key("2026-08-04"), weightKg: 70.2)])
        #expect(weighed.days.map(\.date.raw) == ["2026-08-04"])
        #expect(weighed.days[0].weightKg == 70.2)
    }

    @Test("la période est une borne des deux côtés")
    func therangeIsInclusiveAndExclusive() throws {
        let context = try makeContext()
        let inside = makeRun(in: context, id: 1)
        let book = build(from: "2026-08-11", to: "2026-08-11", activities: [inside])
        #expect(book.days.count == 1)

        #expect(build(from: "2026-08-12", to: "2026-08-31", activities: [inside]).days.isEmpty)
        #expect(build(from: "2026-07-01", to: "2026-08-10", activities: [inside]).days.isEmpty)
    }

    @Test("les journées sortent de la plus ancienne à la plus récente")
    func daysComeOutOldestFirst() {
        // Un carnet se lit dans le sens du temps, à l'inverse de la liste du
        // journal, qui met la dernière note en haut.
        let book = build(notes: [
            JournalNote(date: key("2026-08-11"), text: "b"),
            JournalNote(date: key("2026-08-02"), text: "a"),
        ])
        #expect(book.days.map(\.date.raw) == ["2026-08-02", "2026-08-11"])
    }

    @Test("les tags d'une journée sont ceux de sa note")
    func adayCarriesItsTags() {
        let book = build(notes: [JournalNote(date: key("2026-08-02"), text: "Vu #Sam.")])
        #expect(book.days[0].tags.map(\.name) == ["Sam"])
    }

    @Test("les repas d'une journée portent leurs totaux et leur note")
    func mealsCarryTheirTotals() throws {
        let context = try makeContext()
        let slot = MealSlot(name: "Déjeuner", sortOrder: 1, targetPct: 39)
        context.insert(slot)
        let entry = try NutritionJournal.addEntry(
            in: context, dateKey: key("2026-08-03"), slot: slot, foodName: "Riz",
            kcal100: 350, protein100: 8, carbs100: 78, fat100: 1, grams: 200
        )
        let note = MealNote(dateKey: key("2026-08-03"), mealSlot: slot, note: "Bien.")
        context.insert(note)

        let book = build(entries: [entry], slots: [slot], mealNotes: [note])
        #expect(book.days.count == 1)
        #expect(book.days[0].meals.count == 1)
        #expect(book.days[0].meals[0].name == "Déjeuner")
        #expect(book.days[0].meals[0].kcal == 700)
        #expect(book.days[0].meals[0].note == "Bien.")
    }

    @Test("les totaux additionnent la période et la répartissent par sport")
    func totalsAddUpAndSplitBySport() throws {
        let context = try makeContext()
        let run = makeRun(in: context, id: 1)
        let other = makeRun(in: context, id: 2, at: 1_786_521_600, distance: 30_000)
        other.sportType = .ride

        let book = build(activities: [run, other])
        #expect(book.totals.activityCount == 2)
        #expect(book.totals.distance == 40_000)
        #expect(book.totals.elevation == 200)
        #expect(book.totals.movingTime == 6000)
        // Le sport le plus parcouru d'abord : c'est ce qui a pesé sur la période.
        #expect(book.totals.bySport.map(\.sport) == [.ride, .run])
        #expect(book.totals.bySport[0].count == 1)
    }

    @Test("les poids de début et de fin encadrent la période")
    func weightsBookendTheRange() {
        let book = build(weights: [
            WeightEntry(dateKey: key("2026-08-20"), weightKg: 69.8),
            WeightEntry(dateKey: key("2026-08-02"), weightKg: 70.6),
        ])
        #expect(book.totals.firstWeightKg == 70.6)
        #expect(book.totals.lastWeightKg == 69.8)
    }
}
```

- [ ] **Étape 2 : les lancer et les voir échouer**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalBookTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: cannot find 'JournalBook' in scope`.

- [ ] **Étape 3 : écrire la collecte**

Créer `Cairn/Features/Export/JournalBook.swift`. Les points qui décident du
résultat, à respecter :

- **Le jour d'une sortie** est `DateKey(activity.startDate)` — le calendrier de
  ce Mac, la règle que `JournalDaySources` applique déjà. Une sortie rangée sous
  deux jours différents selon l'écran serait un défaut à elle seule.
- **Une journée entre** si sa note du coffre n'est pas blanche, ou si elle a au
  moins une sortie, ou au moins une note de repas ou de pesée non blanche, ou un
  poids. Des aliments consignés sans un mot ne suffisent pas : consigner n'est
  pas écrire, et c'est la règle que le journal applique déjà.
- **Un repas s'affiche** dans une journée qui existe dès qu'il a des aliments
  consignés **ou** une note — les deux règles sont distinctes, et le test
  `loggedFoodAloneIsNotAJournalDay` tient les deux à la fois.
- **Les repas** sont dans l'ordre de `MealSlot.sortOrder`, et leurs totaux se
  calculent avec `NutritionMath` comme le fait `NutritionDayModel` — pas une
  seconde arithmétique.
- **Les sorties d'une journée** sont dans l'ordre de `startDate`.
- **`bySport`** est trié par distance décroissante.
- **`firstWeightKg` / `lastWeightKg`** sont les pesées extrêmes *de la période*,
  pas la première et la dernière du magasin.

```swift
import Foundation
import SwiftData

/// Everything an exported book holds, gathered in one pure pass.
///
/// A value and not a view model: what a book contains is a decision worth
/// testing on its own — which days earn a section, in what order, with what
/// totals — and none of it needs a window to be true. The HTML, the maps and
/// the PDF all come later, from this.
struct JournalBook: Equatable {
    struct Meal: Equatable {
        var name: String
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var note: String?
    }

    struct Day: Equatable {
        var date: DateKey
        var note: String
        var tags: [JournalTag]
        var activities: [Activity]
        var meals: [Meal]
        var weightKg: Double?
        var weightNote: String?
    }

    struct Totals {
        var activityCount: Int
        var distance: Double
        var elevation: Double
        var movingTime: Int
        var bySport: [(sport: SportType, count: Int, distance: Double)]
        var firstWeightKg: Double?
        var lastWeightKg: Double?
    }

    var from: DateKey
    var to: DateKey
    var days: [Day]
    var totals: Totals

    static func build(
        from: DateKey, to: DateKey, notes: [JournalNote], activities: [Activity],
        entries: [FoodEntry], slots: [MealSlot], mealNotes: [MealNote],
        weights: [WeightEntry]
    ) -> JournalBook
}

/// Written by hand because `bySport` is an array of tuples, which Swift will
/// not synthesise a comparison for.
extension JournalBook.Totals: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool
}
```

Le corps de `build`, à écrire ainsi :

```swift
    static func build(
        from: DateKey, to: DateKey, notes: [JournalNote], activities: [Activity],
        entries: [FoodEntry], slots: [MealSlot], mealNotes: [MealNote],
        weights: [WeightEntry]
    ) -> JournalBook {
        func spoken(_ text: String?) -> String? {
            let trimmed = (text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : text
        }
        func inRange(_ date: DateKey) -> Bool { date >= from && date <= to }

        // The day an outing belongs to is its instant read in this Mac's
        // calendar — `JournalDaySources`' rule. A book and a list that filed
        // the same outing under two different days would be a defect on their
        // own.
        var activitiesByDay: [DateKey: [Activity]] = [:]
        for activity in activities.sorted(by: { $0.startDate < $1.startDate }) {
            let date = DateKey(activity.startDate)
            guard inRange(date) else { continue }
            activitiesByDay[date, default: []].append(activity)
        }

        var notesByDay: [DateKey: JournalNote] = [:]
        for note in notes where inRange(note.date) && spoken(note.text) != nil {
            notesByDay[note.date] = note
        }

        var weightsByDay: [DateKey: WeightEntry] = [:]
        for weight in weights {
            guard let date = weight.dateKey, inRange(date) else { continue }
            weightsByDay[date] = weight
        }

        let orderedSlots = slots.sorted { $0.sortOrder < $1.sortOrder }
        var mealsByDay: [DateKey: [Meal]] = [:]
        var spokenMealByDay: [DateKey: Bool] = [:]
        for (date, _) in Self.everyDay(
            activities: activitiesByDay, notes: notesByDay, weights: weightsByDay,
            mealNotes: mealNotes, entries: entries, from: from, to: to
        ) {
            let dayEntries = entries.filter { $0.dateKeyRaw == date.raw }
            var meals: [Meal] = []
            for slot in orderedSlots {
                let rows = dayEntries.filter {
                    $0.mealSlot?.persistentModelID == slot.persistentModelID
                }
                let note = spoken(
                    mealNotes.first {
                        $0.dateKeyRaw == date.raw
                            && $0.mealSlot?.persistentModelID == slot.persistentModelID
                    }?.note
                )
                guard !rows.isEmpty || note != nil else { continue }
                if note != nil { spokenMealByDay[date] = true }
                // La somme que `NutritionDayModel` écrit déjà pour l'écran :
                // `Macros(of:)` par portion, additionnées depuis `.zero`.
                let macros = rows.map(Macros.init(of:)).reduce(.zero, +)
                meals.append(
                    Meal(
                        name: slot.name, kcal: macros.kcal, protein: macros.protein,
                        carbs: macros.carbs, fat: macros.fat, note: note
                    )
                )
            }
            mealsByDay[date] = meals
        }

        var days: [Day] = []
        for date in Set(
            notesByDay.keys
        ).union(activitiesByDay.keys).union(weightsByDay.keys)
            .union(mealsByDay.keys).sorted() {
            let weight = weightsByDay[date]
            // Logged food alone is not a journal day; a weigh-in is, even
            // silent — it is the one source that earns its line as a figure.
            let earnsAPage = notesByDay[date] != nil
                || activitiesByDay[date] != nil
                || weight != nil
                || spokenMealByDay[date] == true
            guard earnsAPage else { continue }
            let note = notesByDay[date]
            days.append(
                Day(
                    date: date, note: note?.text ?? "",
                    tags: (note?.tags).map { $0.sorted() } ?? [],
                    activities: activitiesByDay[date] ?? [],
                    meals: mealsByDay[date] ?? [],
                    weightKg: weight?.weightKg,
                    weightNote: spoken(weight?.note)
                )
            )
        }

        return JournalBook(
            from: from, to: to, days: days,
            totals: totals(of: days, weights: weightsByDay)
        )
    }
```

`everyDay(...)` est un détail d'implémentation privé : l'ensemble des dates de la
période qu'au moins une source touche. `totals(of:weights:)` additionne les
sorties des journées retenues, groupe par sport et trie par distance
décroissante, et prend la première et la dernière pesée **de la période** par
ordre de date.

- [ ] **Étape 4 : les lancer et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalBookTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : `Test run with 9 tests in 1 suite passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Cairn/Features/Export/JournalBook.swift Tests/JournalBookTests.swift
git commit -m "feat(export): la collecte du carnet, une journée à la fois"
```

---

### Tâche 3 : la trace en SVG

Le repli quand aucune carte n'est disponible — et la pièce qui se teste sans
réseau. La projection existe déjà et elle est testée : `TrackThumbnail.points(for:in:)`
place une trace dans un rectangle en gardant ses proportions, longitude corrigée
par la latitude.

**Fichiers :**
- Créer : `Cairn/Features/Export/JournalBookTrackSVG.swift`
- Créer : `Tests/JournalBookTrackSVGTests.swift`

**Interfaces produites :**
```swift
enum JournalBookTrackSVG {
    static func svg(
        for coordinates: [Coordinate], size: CGSize, hex: String
    ) -> String?
}
```

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `Tests/JournalBookTrackSVGTests.swift` :

```swift
import Testing
import Foundation
@testable import Cairn

@Suite("La trace en SVG, pour le carnet sans carte")
struct JournalBookTrackSVGTests {
    private let square = CGSize(width: 200, height: 200)

    private var loop: [Coordinate] {
        [
            Coordinate(latitude: 45.75, longitude: 4.83),
            Coordinate(latitude: 45.76, longitude: 4.84),
            Coordinate(latitude: 45.75, longitude: 4.85),
        ]
    }

    @Test("une trace donne un SVG à ses dimensions")
    func drawsTheTrack() {
        let svg = JournalBookTrackSVG.svg(for: loop, size: square, hex: "#ff6600")
        #expect(svg?.hasPrefix("<svg") == true)
        #expect(svg?.contains("width=\"200\"") == true)
        #expect(svg?.contains("height=\"200\"") == true)
        #expect(svg?.contains("#ff6600") == true)
        // Une polyligne, pas une image : le PDF la garde nette à l'impression.
        #expect(svg?.contains("<polyline") == true)
    }

    @Test("sans trace, pas de SVG")
    func nothingToDraw() {
        #expect(JournalBookTrackSVG.svg(for: [], size: square, hex: "#000") == nil)
        #expect(
            JournalBookTrackSVG.svg(
                for: [Coordinate(latitude: 45.75, longitude: 4.83)],
                size: square, hex: "#000"
            ) == nil
        )
    }

    @Test("les points restent dans le cadre")
    func staysInsideTheBox() {
        let svg = JournalBookTrackSVG.svg(for: loop, size: square, hex: "#000")!
        // Les coordonnées du `points="x,y x,y"` : aucune hors du cadre.
        let numbers = svg
            .components(separatedBy: "points=\"")[1]
            .components(separatedBy: "\"")[0]
            .components(separatedBy: CharacterSet(charactersIn: " ,"))
            .compactMap(Double.init)
        #expect(!numbers.isEmpty)
        #expect(numbers.allSatisfy { $0 >= 0 && $0 <= 200 })
    }
}
```

- [ ] **Étape 2 : les lancer et les voir échouer**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalBookTrackSVGTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: cannot find 'JournalBookTrackSVG' in scope`.

- [ ] **Étape 3 : écrire le SVG**

Créer `Cairn/Features/Export/JournalBookTrackSVG.swift` :

```swift
import Foundation
import SwiftUI

/// A track as a vector polyline, for a book made without a map.
///
/// The projection is `TrackThumbnail`'s, reached rather than copied: the shape
/// of an outing is recognisable at forty points, and it is already fitted,
/// centred and corrected for the longitude's shrinking with latitude. A second
/// copy of that arithmetic would drift from the one on screen.
///
/// Vector and not an image, because a PDF keeps it sharp at any zoom and it
/// costs a few hundred bytes.
enum JournalBookTrackSVG {
    static func svg(
        for coordinates: [Coordinate], size: CGSize, hex: String
    ) -> String? {
        let points = TrackThumbnail.points(
            for: coordinates,
            in: CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        )
        guard points.count > 1 else { return nil }
        let list = points
            .map { "\(rounded($0.x)),\(rounded($0.y))" }
            .joined(separator: " ")
        return """
            <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(size.width))" \
            height="\(Int(size.height))" viewBox="0 0 \(Int(size.width)) \
            \(Int(size.height))"><polyline points="\(list)" fill="none" \
            stroke="\(hex)" stroke-width="2" stroke-linecap="round" \
            stroke-linejoin="round"/></svg>
            """
    }

    /// One decimal is plenty at these sizes, and it keeps the file small.
    private static func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}
```

- [ ] **Étape 4 : les lancer et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalBookTrackSVGTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : `Test run with 3 tests in 1 suite passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Cairn/Features/Export/JournalBookTrackSVG.swift Tests/JournalBookTrackSVGTests.swift
git commit -m "feat(export): la trace d'une sortie en SVG, pour un carnet sans carte"
```

---

### Tâche 4 : le HTML et sa feuille de style

**Fichiers :**
- Créer : `Cairn/Features/Export/JournalBookHTML.swift`
- Créer : `Tests/JournalBookHTMLTests.swift`

**Interfaces consommées :** `JournalBook` (tâche 2), `MarkdownHTML` (tâche 1),
`Format`, `SportType`.

**Interfaces produites :**
```swift
enum JournalBookHTML {
    /// Ce qu'une sortie a comme images, quand elles ont été fabriquées.
    struct Illustrations {
        var map: String?        // data: URI ou SVG en ligne
        var charts: [String]    // data: URI
        var photos: [String]    // data: URI
    }
    static func document(
        _ book: JournalBook, illustrations: [Int64: Illustrations]
    ) -> String
}
```

Les illustrations sont **indexées par `stravaID`** et passées de l'extérieur :
c'est ce qui garde cette pièce pure et testable sans réseau ni vue. Une sortie
sans entrée dans le dictionnaire s'écrit sans image, ce qui est aussi le cas
d'un export lancé hors ligne.

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `Tests/JournalBookHTMLTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Le HTML du carnet")
@MainActor
struct JournalBookHTMLTests {
    private func key(_ raw: String) -> DateKey { DateKey(raw: raw)! }

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    private func book(
        days: [JournalBook.Day], from: String = "2026-08-01", to: String = "2026-08-31"
    ) -> JournalBook {
        JournalBook(
            from: key(from), to: key(to), days: days,
            totals: JournalBook.Totals(
                activityCount: 0, distance: 0, elevation: 0, movingTime: 0,
                bySport: [], firstWeightKg: nil, lastWeightKg: nil
            )
        )
    }

    private func day(
        _ raw: String, note: String = "", activities: [Activity] = [],
        meals: [JournalBook.Meal] = [], weightKg: Double? = nil
    ) -> JournalBook.Day {
        JournalBook.Day(
            date: key(raw), note: note, tags: [], activities: activities,
            meals: meals, weightKg: weightKg, weightNote: nil
        )
    }

    @Test("le document est autonome : un seul fichier, style compris")
    func thedocumentStandsAlone() {
        let html = JournalBookHTML.document(book(days: [day("2026-08-02", note: "Repos.")]), illustrations: [:])
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<style>"))
        // Rien à charger de l'extérieur : ni feuille liée, ni image distante.
        #expect(!html.contains("<link"))
        #expect(!html.contains("src=\"http"))
    }

    @Test("la note d'une journée est rendue, pas recopiée")
    func thenoteIsRendered() {
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-02", note: "# Titre\n\nUn **gras**.")]),
            illustrations: [:]
        )
        #expect(html.contains("<h1>Titre</h1>"))
        #expect(html.contains("<strong>gras</strong>"))
        #expect(!html.contains("**gras**"))
    }

    @Test("un caractère réservé d'une note ne casse pas le document")
    func areservedCharacterIsEscaped() {
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-02", note: "Pain & <fromage>")]),
            illustrations: [:]
        )
        #expect(html.contains("Pain &amp; &lt;fromage&gt;"))
    }

    @Test("une journée sans sortie ne produit aucun bloc de sortie")
    func nooutingNoBlock() {
        let html = JournalBookHTML.document(
            book(days: [day("2026-08-02", note: "Repos.")]), illustrations: [:]
        )
        #expect(!html.contains("class=\"activity\""))
    }

    @Test("une sortie sans image ne laisse pas de balise vide")
    func amissingImageLeavesNoTag() throws {
        let context = try makeContext()
        let activity = Activity(stravaID: 7, name: "Footing", sportType: .run)
        activity.startDate = Date(timeIntervalSince1970: 1_786_435_200)
        activity.distance = 10_000
        activity.movingTime = 3000
        context.insert(activity)

        let html = JournalBookHTML.document(
            book(days: [day("2026-08-11", activities: [activity])]), illustrations: [:]
        )
        #expect(html.contains("class=\"activity\""))
        #expect(html.contains("Footing"))
        #expect(!html.contains("src=\"\""))
        #expect(!html.contains("<img"))
    }

    @Test("les images fournies sont posées dans la sortie")
    func illustrationsLandInTheOuting() throws {
        let context = try makeContext()
        let activity = Activity(stravaID: 7, name: "Footing", sportType: .run)
        activity.startDate = Date(timeIntervalSince1970: 1_786_435_200)
        context.insert(activity)

        let html = JournalBookHTML.document(
            book(days: [day("2026-08-11", activities: [activity])]),
            illustrations: [7: JournalBookHTML.Illustrations(
                map: "data:image/png;base64,AAA",
                charts: ["data:image/png;base64,BBB"],
                photos: ["data:image/png;base64,CCC"]
            )]
        )
        #expect(html.contains("data:image/png;base64,AAA"))
        #expect(html.contains("data:image/png;base64,BBB"))
        #expect(html.contains("data:image/png;base64,CCC"))
    }

    @Test("les chiffres sont ceux de l'écran, allure comprise")
    func figuresReadLikeTheApp() throws {
        let context = try makeContext()
        let activity = Activity(stravaID: 7, name: "Footing", sportType: .run)
        activity.startDate = Date(timeIntervalSince1970: 1_786_435_200)
        activity.distance = 10_000
        activity.movingTime = 3000
        activity.averageSpeed = 10_000 / 3000
        context.insert(activity)

        let html = JournalBookHTML.document(
            book(days: [day("2026-08-11", activities: [activity])]), illustrations: [:]
        )
        #expect(html.contains(Format.distance(10_000)))
        #expect(html.contains(Format.speed(10_000 / 3000, sport: .run)))
    }

    @Test("le repas et le poids d'une journée s'écrivent quand ils existent")
    func mealsAndWeightAppear() {
        let html = JournalBookHTML.document(
            book(days: [day(
                "2026-08-03",
                meals: [JournalBook.Meal(
                    name: "Déjeuner", kcal: 700, protein: 16, carbs: 156, fat: 2,
                    note: "Bien."
                )],
                weightKg: 70.2
            )]),
            illustrations: [:]
        )
        #expect(html.contains("Déjeuner"))
        #expect(html.contains("700"))
        #expect(html.contains("70,2 kg"))
    }

    @Test("la page de garde dit la période et ce qu'elle pèse")
    func thecoverSaysWhatThePeriodWeighs() {
        let full = JournalBook(
            from: key("2026-08-01"), to: key("2026-08-31"),
            days: [day("2026-08-02", note: "Repos.")],
            totals: JournalBook.Totals(
                activityCount: 12, distance: 140_000, elevation: 1_200,
                movingTime: 40_000, bySport: [(.run, 8, 90_000), (.ride, 4, 50_000)],
                firstWeightKg: 70.6, lastWeightKg: 69.8
            )
        )
        let html = JournalBookHTML.document(full, illustrations: [:])
        #expect(html.contains("class=\"cover\""))
        #expect(html.contains("12"))
        #expect(html.contains(Format.distance(140_000)))
        #expect(html.contains("Course"))
        #expect(html.contains("70,6"))
        #expect(html.contains("69,8"))
    }
}
```

- [ ] **Étape 2 : les lancer et les voir échouer**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalBookHTMLTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: cannot find 'JournalBookHTML' in scope`.

- [ ] **Étape 3 : écrire le document**

Créer `Cairn/Features/Export/JournalBookHTML.swift`. La sortie visée, pour une
journée avec une sortie illustrée — c'est cette structure que les tests
vérifient, et c'est elle qui fait foi :

```html
<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><title>Carnet — août 2026</title>
<style>/* la feuille ci-dessous */</style></head><body>
<section class="cover">
  <h1>Carnet</h1>
  <p class="period">Du 1er au 31 août 2026</p>
  <dl class="totals">
    <div><dt>Sorties</dt><dd>12</dd></div>
    <div><dt>Distance</dt><dd>140,0 km</dd></div>
    <div><dt>Dénivelé +</dt><dd>1200 m</dd></div>
    <div><dt>Temps</dt><dd>11 h 06</dd></div>
  </dl>
  <ul class="sports">
    <li><span class="sport">Course</span> 8 · 90,0 km</li>
    <li><span class="sport">Vélo</span> 4 · 50,0 km</li>
  </ul>
  <p class="weight">70,6 kg → 69,8 kg</p>
</section>
<section class="day">
  <h2>Mardi 11 août 2026</h2>
  <div class="note"><p>Jambes lourdes.</p></div>
  <ul class="tags"><li>Sam</li></ul>
  <article class="activity">
    <header><span class="time">06:52</span> <span class="sport">Course</span>
      <span class="name">Footing du matin</span></header>
    <figure class="map"><img src="data:image/png;base64,…" alt=""></figure>
    <dl class="figures">
      <div><dt>Distance</dt><dd>9,0 km</dd></div>
      <div><dt>Temps</dt><dd>48 min 25 s</dd></div>
      <div><dt>D+</dt><dd>32 m</dd></div>
      <div><dt>Allure</dt><dd>5:21/km</dd></div>
      <div><dt>FC moy.</dt><dd>132 bpm</dd></div>
    </dl>
    <figure class="chart"><img src="data:image/png;base64,…" alt=""></figure>
    <figure class="photo"><img src="data:image/png;base64,…" alt=""></figure>
    <div class="note"><p>Sensations correctes.</p></div>
  </article>
  <section class="food">
    <p class="weight">70,2 kg — bien dormi</p>
    <ul class="meals">
      <li><span class="meal">Déjeuner</span>
        <span class="macros">700 kcal · 16 P · 156 G · 2 L</span>
        <span class="note">Bien.</span></li>
    </ul>
  </section>
</section>
</body></html>
```

Le Swift qui produit ce document n'est pas écrit ici, et c'est délibéré : c'est
de l'assemblage de chaînes, la sortie visée ci-dessus le spécifie mieux qu'une
transcription, et les tests de l'étape 1 la vérifient. Les règles ci-dessous
sont, elles, obligatoires.

Règles de construction, toutes vérifiables :

- Chaque partie disparaît entièrement quand elle est vide — pas de `<div
  class="note"></div>`, pas de `<img src="">`, pas de `<figure>` sans image.
- Tout texte venu de l'utilisateur passe par `MarkdownHTML.render` (les notes)
  ou `MarkdownHTML.escape` (un nom d'activité, un nom de repas, un nom de tag).
- Tous les chiffres passent par `Format` : `distance`, `duration`, `elevation`,
  `speed(_:sport:)`, `heartrate`, `cadence(_:sport:)`, `typedNumber` pour le
  poids, `fullDate` pour la date d'une journée, `time(_:in:)` pour l'heure d'une
  sortie — dans le fuseau de la sortie, `activity.timeZone`.
- Le libellé de l'allure est « Allure » pour les sports qui se lisent en allure
  (`.run`, `.trailRun`, `.walk`, `.hike`, `.swim`) et « Vitesse » sinon. Cette
  liste est celle de `Format.speed(_:sport:)` : si l'une change, l'autre aussi.

La feuille de style, à écrire telle quelle :

```css
@page { size: A4; margin: 18mm 16mm; }
* { box-sizing: border-box; }
body {
  font: 11pt/1.5 -apple-system, "Helvetica Neue", sans-serif;
  color: #1c1c1e; margin: 0;
}
h1, h2, h3 { font-weight: 600; margin: 0 0 .4em; }
/* Une journée peut se couper entre deux sorties, jamais au milieu de l'une. */
.day { break-after: page; }
.day:last-child { break-after: auto; }
.activity, figure, .food, .cover { break-inside: avoid; }
.cover { height: 100%; break-after: page; }
.cover h1 { font-size: 34pt; letter-spacing: -.5pt; }
.cover .period { font-size: 13pt; color: #6c6c70; margin-bottom: 2em; }
.day > h2 {
  font-size: 17pt; border-bottom: 1px solid #d8d8dc;
  padding-bottom: .3em; margin-bottom: .8em;
}
.note { margin: .6em 0; }
.note p { margin: 0 0 .5em; }
.note blockquote {
  margin: .5em 0; padding-left: .8em; border-left: 2px solid #d8d8dc;
  color: #6c6c70; font-style: italic;
}
.tags { list-style: none; padding: 0; margin: .2em 0 1em; }
.tags li {
  display: inline-block; font-size: 8.5pt; color: #6c6c70;
  background: #f2f2f7; border-radius: 9pt; padding: 1pt 7pt; margin-right: 4pt;
}
.activity {
  margin: 1em 0; padding: .8em 1em; background: #f7f7f9; border-radius: 6pt;
}
.activity header { display: flex; gap: .6em; align-items: baseline; }
.activity .time { font-variant-numeric: tabular-nums; color: #6c6c70; }
.activity .name { font-weight: 600; }
.sport { color: #6c6c70; }
figure { margin: .7em 0; }
figure img { width: 100%; height: auto; border-radius: 4pt; display: block; }
figure.photo img { max-height: 90mm; object-fit: cover; }
dl.figures, dl.totals { display: flex; flex-wrap: wrap; gap: .2em 1.6em; margin: .6em 0; }
dl dt { font-size: 8.5pt; color: #6c6c70; }
dl dd { margin: 0; font-variant-numeric: tabular-nums; }
dl.totals dd { font-size: 15pt; }
.sports, .meals { list-style: none; padding: 0; margin: .4em 0; }
.meals li { margin: .2em 0; }
.meals .macros { font-variant-numeric: tabular-nums; color: #6c6c70; }
.food .weight { font-variant-numeric: tabular-nums; }
```

- [ ] **Étape 4 : les lancer et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalBookHTMLTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : `Test run with 9 tests in 1 suite passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Cairn/Features/Export/JournalBookHTML.swift Tests/JournalBookHTMLTests.swift
git commit -m "feat(export): le carnet en HTML, feuille de style comprise"
```

---

### Tâche 5 : les images

La seule pièce qui touche au réseau et à la vue. Aucun test automatique : elle
demande une carte, un rendu et du temps. Elle se vérifie à l'écran, à l'étape
suivante.

**Fichiers :**
- Créer : `Cairn/Features/Export/JournalBookAssets.swift`

**Interfaces consommées :** `JournalBook` (tâche 2),
`JournalBookHTML.Illustrations` (tâche 4), `JournalBookTrackSVG` (tâche 3),
`StreamSeriesBuilder`, `ActivityTrackModel`, `SportType.color`.

**Interfaces produites :**
```swift
@MainActor
enum JournalBookAssets {
    /// - Parameter progress: appelée à chaque image finie, (faites, total).
    static func illustrations(
        for book: JournalBook, progress: @escaping (Int, Int) -> Void
    ) async -> [Int64: JournalBookHTML.Illustrations]
}
```

- [ ] **Étape 1 : écrire la fabrique d'images**

Créer `Cairn/Features/Export/JournalBookAssets.swift`. Les décisions à
respecter :

- **La carte** : un instantané, la trace dessinée par-dessus. C'est le morceau
  qui se rate le plus facilement — un `MKMapSnapshotter` rend une image *sans*
  la trace, et `snapshot.point(for:)` est la seule chose qui sache où la poser :

```swift
    /// One map, drawn light: a book is printed on white paper, and a dark
    /// snapshot would come out of a printer as a grey slab.
    private static func map(
        for coordinates: [Coordinate], color: NSColor, size: CGSize
    ) async -> NSImage? {
        guard coordinates.count > 1 else { return nil }
        let points = coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        var rect = MKMapRect.null
        for point in points {
            let map = MKMapPoint(point)
            rect = rect.union(MKMapRect(x: map.x, y: map.y, width: 0, height: 0))
        }
        guard !rect.isNull else { return nil }

        let options = MKMapSnapshotter.Options()
        // 15 % of air around the track: a line drawn against the edge of the
        // frame reads as a line that continues past it.
        options.mapRect = rect.insetBy(
            dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.15
        )
        options.size = size
        options.appearance = NSAppearance(named: .aqua)
        options.showsBuildings = false

        guard let snapshot = try? await MKMapSnapshotter(options: options).start()
        else { return nil }

        let image = NSImage(size: snapshot.image.size)
        image.lockFocus()
        snapshot.image.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
        let path = NSBezierPath()
        path.lineWidth = 4
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        for (index, point) in points.enumerated() {
            let position = snapshot.point(for: point)
            index == 0 ? path.move(to: position) : path.line(to: position)
        }
        color.setStroke()
        path.stroke()
        image.unlockFocus()
        return image
    }
```
- **Le repli** : si le snapshot échoue — pas de réseau, région vide — la carte
  vaut `JournalBookTrackSVG.svg(for:size:hex:)` **en ligne dans le HTML**, pas
  en `data:` URI : un SVG en ligne se style et reste net. Une sortie sans trace
  du tout n'a pas de carte, et c'est très bien.
- **Les courbes** : `ImageRenderer` sur un `Chart` construit depuis
  `StreamSeriesBuilder.series(from:totalDistance:distancesMetres:sport:)`, une
  image par série d'altitude et de fréquence cardiaque, 1000 × 220 points,
  `scale = 2`. Les autres séries (puissance, cadence) n'entrent pas : le carnet
  n'est pas un tableau de bord.
- **Les photos** : `activity.orderedPhotos.compactMap(\.data)`, encodées telles
  quelles — elles sont déjà en JPEG dans le magasin. Une photo dont les octets
  ne se décodent pas est sautée.
- **La progression** : `progress(faites, total)` après chaque image, sur le fil
  principal. Le total est connu d'avance : une carte par sortie, plus ses
  courbes, plus ses photos.

- [ ] **Étape 2 : vérifier que ça compile**

```bash
xcodegen generate
xcodebuild build -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|BUILD"
```

Attendu : `** BUILD SUCCEEDED **`.

- [ ] **Étape 3 : commiter**

```bash
git add Cairn/Features/Export/JournalBookAssets.swift
git commit -m "feat(export): les cartes, les courbes et les photos du carnet"
```

---

### Tâche 6 : le PDF et l'entrée de menu

**Fichiers :**
- Créer : `Cairn/Features/Export/JournalBookExporter.swift`
- Créer : `Cairn/Features/Export/ExportJournalSheet.swift`
- Modifier : `Cairn/App/AppEnvironment.swift`
- Modifier : `Cairn/App/CairnApp.swift`
- Modifier : `Cairn/App/RootView.swift`

**Interfaces produites :**
```swift
@MainActor
enum JournalBookExporter {
    /// Rend le PDF d'un document HTML déjà complet.
    static func pdf(from html: String) async throws -> Data
}

struct ExportJournalSheet: View {
    init(from: DateKey, to: DateKey, onExport: @escaping (DateKey, DateKey) -> Void)
}
```

- [ ] **Étape 1 : écrire le rendu PDF**

Créer `Cairn/Features/Export/JournalBookExporter.swift` :

```swift
import WebKit
import AppKit

/// The book's HTML, turned into a paginated PDF.
///
/// WebKit does the one hard part: a day runs to ten lines or three pages
/// depending on how much was done, and the CSS says where a break may fall.
/// Neither `ImageRenderer` — one view per page, the splitting left to us — nor
/// Core Graphics knows how to do that.
@MainActor
enum JournalBookExporter {
    static func pdf(from html: String) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 794, height: 1123),
            configuration: configuration
        )
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        try await delegate.waitForLoad()
        // Le document entier, pas la partie visible : sans configuration,
        // `createPDF` pagine tout ce que la page contient.
        return try await webView.pdf()
    }

    /// A navigation delegate that hands its continuation back on `didFinish`.
    /// Held by the caller for the length of the load — a delegate is weak.
    private final class LoadWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var finished = false
        private var failure: Error?

        func waitForLoad() async throws {
            if finished { return }
            if let failure { throw failure }
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finished = true
            continuation?.resume()
            continuation = nil
        }

        func webView(
            _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
        ) {
            failure = error
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
```

- [ ] **Étape 2 : écrire la feuille**

Créer `Cairn/Features/Export/ExportJournalSheet.swift` : deux `DatePicker` —
« Du » et « Au », `displayedComponents: .date` — préremplis sur les dates
reçues, un bouton « Exporter… » par défaut et un bouton « Annuler »
(`.cancelAction`).

Pendant la fabrication, la feuille reste et remplace ses boutons par une
`ProgressView(value:total:)` et une ligne « image 3 sur 12 » : les instantanés
de cartes sont la partie lente, et une fenêtre muette pendant dix secondes passe
pour un gel. La feuille se ferme quand le fichier est écrit.

- [ ] **Étape 3 : brancher le menu et l'écriture**

Dans `Cairn/App/AppEnvironment.swift`, à côté de `requestExportGPX` :

```swift
    var requestExportJournalPDF: (() -> Void)?
```

Dans `Cairn/App/CairnApp.swift`, dans le `CommandGroup(replacing: .importExport)`,
après le bouton GPX :

```swift
                Button("Exporter le journal en PDF…") {
                    app.requestExportJournalPDF?()
                }
                .disabled(app.requestExportJournalPDF == nil)
```

Dans `Cairn/App/RootView.swift`, à côté de `app.requestExportGPX = …`, poser
`app.requestExportJournalPDF = { isExportingJournal = true }`, présenter
`ExportJournalSheet` sur cet état, préremplie du mois affiché
(`journalDay.monthStart` et `journalDay.monthEnd()`), et à l'export :

1. `JournalBook.build(...)` avec les requêtes déjà présentes dans la vue ;
2. **si `book.days.isEmpty`, s'arrêter là** avec l'alerte « Aucune journée à
   exporter sur cette période. » — un PDF réduit à sa page de garde serait une
   déception silencieuse ;
3. `JournalBookAssets.illustrations(for:progress:)`, la progression remontée à
   la feuille ;
4. `JournalBookHTML.document(book, illustrations:)` puis
   `JournalBookExporter.pdf(from:)` ;
5. `NSSavePanel`, `allowedContentTypes = [.pdf]`, nom proposé
   `Carnet 2026-08-01 — 2026-08-31.pdf`, puis écriture ;
6. tout échec d'écriture passe par la même alerte que l'export GPX.

- [ ] **Étape 4 : compiler et lancer toute la suite**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : 750 tests, tous verts (721 avant, plus 8 de la tâche 1, 9 de la
tâche 2, 3 de la tâche 3 et 9 de la tâche 4).

- [ ] **Étape 5 : commiter**

```bash
git add Cairn/Features/Export Cairn/App
git commit -m "feat(export): Fichier ▸ Exporter le journal en PDF"
```

- [ ] **Étape 6 : le vérifier à l'œil**

Ne pas faire soi-même : le propriétaire du dépôt s'en charge. Lui laisser la
commande.

```bash
xcodebuild build -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build && open build/Build/Products/Debug/Cairn.app
```

À regarder sur un mois bien rempli : les cartes sont là, aucune sortie n'est
coupée par un saut de page, les notes sont rendues et non brutes, et le poids
comme les allures se lisent à la française.
