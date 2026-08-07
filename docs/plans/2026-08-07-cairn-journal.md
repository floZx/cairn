# Le journal devient la référence — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une activité peut naître dans l'application, être éditée sans qu'une synchro Strava l'écrase, et être supprimée sans revenir.

**Architecture:** Trois champs et un modèle s'ajoutent au schéma. `ImportMapper` gagne un point de contrôle unique par lequel passent ses vingt-cinq affectations, qui refuse d'écrire un champ que l'utilisateur a touché. L'interface d'édition est une feuille modale dont le cœur est un type valeur pur, `ActivityDraft`, testable sans vue.

**Tech Stack:** Swift 6.3 en mode langage Swift 6, SwiftData, SwiftUI + AppKit, Swift Testing, XcodeGen.

Conception : [docs/specs/2026-08-07-cairn-design.md](../specs/2026-08-07-cairn-design.md).

Ce plan couvre les **lots 1 et 2** du spec. L'import GPX (lot 3) et le renommage en Cairn (lot 4) auront chacun leur plan : le premier est un sous-système indépendant, le second doit venir en dernier pour ne pas mêler une réécriture massive à des changements de comportement.

## Global Constraints

- Cible macOS 15.0, Swift 6 language mode, concurrence stricte. Le projet compile sans avertissement — un avertissement est un échec de tâche.
- Tests avec **Swift Testing** (`import Testing`, `@Test`, `#expect`). Jamais XCTest.
- Identifiants et commentaires en **anglais**. Chaînes affichées à l'utilisateur en **français**.
- `xcodegen generate` après l'ajout de tout fichier source, sans quoi la compilation échoue sur un fichier introuvable.
- Compilation et tests : `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build`. Le `-derivedDataPath build` n'est pas cosmétique : sans lui deux bundles de même identifiant coexistent et LaunchServices sert une icône générique.
- Ne jamais lancer l'application ni prendre de capture d'écran. La vérification se fait par la compilation et les tests.
- Aucune écriture vers Strava, sous aucune forme.
- Les commentaires expliquent **pourquoi**, pas quoi. Densité et style de ceux du dépôt.

## Déviation assumée par rapport au spec

Le spec fait de `uuid` la clé unique. **Ce plan ne déclare aucune contrainte d'unicité.**

Modifier une contrainte d'unicité est ce qui fait basculer une migration SwiftData de légère à impossible, et l'échec ne coûterait pas un bug mais la base de l'utilisateur. Retirer une contrainte est sûr ; en ajouter une ne l'est pas. L'unicité de `stravaID` est de toute façon garantie par le `fetch-or-create` de `ImportMapper`, qui est le mécanisme réel, et la tâche 3 la couvre par un test de réimport.

## File Structure

**Créés :**

| Fichier | Responsabilité |
|---|---|
| `StravaLocal/Model/ActivityField.swift` | Les clés des champs éditables. Un enum plutôt que des chaînes : une faute de frappe passerait en silence et le seul symptôme serait une édition écrasée. |
| `StravaLocal/Model/ActivitySource.swift` | D'où vient une activité : Strava, saisie, fichier. |
| `StravaLocal/Model/DiscardedActivity.swift` | La pierre tombale d'une activité Strava supprimée. |
| `StravaLocal/Features/ActivityEditor/ActivityDraft.swift` | Le cœur pur de l'édition : valeurs saisies, validation, champs réellement modifiés, application au modèle. Aucune vue, donc entièrement testable. |
| `StravaLocal/Features/ActivityEditor/ActivityEditorSheet.swift` | La feuille modale, pour l'édition comme pour l'ajout. |
| `StravaLocal/Features/Settings/DiscardedActivitiesSection.swift` | La liste des activités écartées, et leur retour. Une section des réglages de synchronisation, pas un onglet : on l'ouvre deux fois par an, et elle parle de ce dont parle cet onglet — ce que la synchro ne doit pas ramener. |
| `Tests/ActivityDraftTests.swift` | |
| `Tests/EditProtectionTests.swift` | |
| `Tests/DiscardedActivityTests.swift` | |

**Modifiés :**

| Fichier | Changement |
|---|---|
| `StravaLocal/Model/Activity.swift:6-9` | `#Unique` retiré, `uuid` indexé, quatre champs ajoutés. |
| `StravaLocal/Model/ModelContainer+App.swift:5-8` | `DiscardedActivity` au schéma. |
| `StravaLocal/Sync/ImportMapper.swift:22-90` | Point de contrôle `assign`, garde sur la source, garde sur les écartées. |
| `StravaLocal/Sync/SyncEngine.swift` | Les identifiants écartés ne sont pas mis en file. |
| `StravaLocal/App/RootView.swift` | Barre d'outils : ajouter, éditer, supprimer. Feuille et confirmation. |
| `StravaLocal/App/StravaLocalApp.swift` | Commandes ⌘N, ⌘E, ⌘⌫. Passage de renseignement des `uuid` au lancement. |
| `StravaLocal/Features/Settings/SyncSettingsView.swift` | Accueille la section des activités écartées. |
| `StravaLocal/Features/ActivityDetail/ActivityDetailView.swift` | Mention de la source et de la date d'édition. |

---

### Task 1: Les clés de champ et la source

**Files:**
- Create: `StravaLocal/Model/ActivityField.swift`
- Create: `StravaLocal/Model/ActivitySource.swift`
- Test: `Tests/ActivityDraftTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces: `enum ActivityField: String, CaseIterable, Sendable` avec les cas `name`, `sportType`, `startDate`, `distance`, `movingTime`, `totalElevationGain`, `notes`, `isCommute`, `isTrainer` et `var displayName: String`. `enum ActivitySource: String, CaseIterable, Sendable` avec `strava`, `manual`, `file`, `var displayName: String` et `var isSynced: Bool`.

- [ ] **Step 1: Write the failing test**

Dans `Tests/ActivityDraftTests.swift` :

```swift
import Testing
@testable import StravaLocal

@Suite("ActivityField et ActivitySource")
struct ActivityFieldTests {
    @Test("chaque champ a une clé stable et un libellé")
    func fieldsAreStable() {
        // The raw values are persisted in `Activity.editedFields`. Renaming one
        // would silently unprotect every activity already edited, and the only
        // symptom would be an overwritten edit at the next sync.
        #expect(ActivityField.name.rawValue == "name")
        #expect(ActivityField.startDate.rawValue == "startDate")
        #expect(ActivityField.totalElevationGain.rawValue == "totalElevationGain")
        #expect(ActivityField.allCases.count == 9)
        #expect(ActivityField.allCases.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("seule la source Strava est concernée par la synchro")
    func onlyStravaIsSynced() {
        #expect(ActivitySource.strava.isSynced)
        #expect(ActivitySource.manual.isSynced == false)
        #expect(ActivitySource.file.isSynced == false)
        #expect(ActivitySource(rawValue: "strava") == .strava)
        // An unknown raw value must not crash a store written by a later version.
        #expect(ActivitySource(rawValue: "healthkit") == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:StravaLocalTests/ActivityFieldTests`
Expected: FAIL, `cannot find 'ActivityField' in scope`.

- [ ] **Step 3: Write minimal implementation**

`StravaLocal/Model/ActivityField.swift` :

```swift
import Foundation

/// A field the user may edit, and therefore one the sync must not overwrite.
///
/// An enum rather than free strings because the raw values are persisted in
/// `Activity.editedFields`: a typo would compile, protect nothing, and show up
/// only as an edit silently overwritten at the next sync.
enum ActivityField: String, CaseIterable, Sendable {
    case name
    case sportType
    case startDate
    case distance
    case movingTime
    case totalElevationGain
    case notes
    case isCommute
    case isTrainer

    var displayName: String {
        switch self {
        case .name: "Nom"
        case .sportType: "Sport"
        case .startDate: "Date"
        case .distance: "Distance"
        case .movingTime: "Durée"
        case .totalElevationGain: "Dénivelé positif"
        case .notes: "Notes"
        case .isCommute: "Domicile-travail"
        case .isTrainer: "Home-trainer"
        }
    }
}
```

`StravaLocal/Model/ActivitySource.swift` :

```swift
import Foundation

/// Where an activity came from.
///
/// The sync only ever touches what it brought itself; anything entered here or
/// read from a file is the user's, whatever Strava may later say about a
/// coincidentally similar outing.
enum ActivitySource: String, CaseIterable, Sendable {
    case strava
    case manual
    case file

    var displayName: String {
        switch self {
        case .strava: "Strava"
        case .manual: "Saisie manuelle"
        case .file: "Fichier importé"
        }
    }

    /// Whether a Strava sync may update this activity at all.
    var isSynced: Bool { self == .strava }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate` puis la commande de test de l'étape 2.
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Model/ActivityField.swift StravaLocal/Model/ActivitySource.swift Tests/ActivityDraftTests.swift
git commit -m "feat(model): clés de champ éditable et source d'activité

Les clés sont persistées dans editedFields, d'où un enum plutôt que des
chaînes libres : une faute de frappe compilerait, ne protégerait rien, et
ne se verrait qu'à une édition écrasée par la synchro suivante."
```

---

### Task 2: Le schéma accueille l'édition locale

**Files:**
- Modify: `StravaLocal/Model/Activity.swift:6-9` (macros) et la liste des propriétés
- Modify: `StravaLocal/Model/ModelContainer+App.swift:5-8`
- Create: `StravaLocal/Model/DiscardedActivity.swift`
- Test: `Tests/DiscardedActivityTests.swift`

**Interfaces:**
- Consumes: `ActivityField`, `ActivitySource` (tâche 1).
- Produces: sur `Activity` — `var uuid: String`, `var sourceRaw: String`, `var editedFieldsRaw: [String]`, `var editedAt: Date?`, et les accès calculés `var source: ActivitySource { get set }`, `var editedFields: Set<ActivityField> { get set }`, `func markEdited(_ fields: Set<ActivityField>)`, `func isEdited(_ field: ActivityField) -> Bool`. Modèle `DiscardedActivity` avec `stravaID: Int64`, `discardedAt: Date`, `name: String`, `init(stravaID:name:discardedAt:)`.

- [ ] **Step 1: Write the failing test**

`Tests/DiscardedActivityTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("Édition locale et pierres tombales")
@MainActor
struct DiscardedActivityTests {
    @Test("une activité neuve a un uuid, vient de Strava et n'est pas éditée")
    func defaultsAreSane() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        context.insert(activity)

        #expect(activity.uuid.isEmpty == false)
        #expect(activity.source == .strava)
        #expect(activity.editedFields.isEmpty)
        #expect(activity.editedAt == nil)
    }

    @Test("les champs édités survivent à un aller-retour en base")
    func editedFieldsPersist() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let activity = Activity(stravaID: 2, name: "Sortie", sportType: .run)
        context.insert(activity)
        activity.markEdited([.name, .distance])
        try context.save()

        let reloaded = try ModelContext(container)
            .fetch(FetchDescriptor<Activity>()).first
        #expect(reloaded?.editedFields == [.name, .distance])
        #expect(reloaded?.isEdited(.name) == true)
        #expect(reloaded?.isEdited(.movingTime) == false)
        #expect(reloaded?.editedAt != nil)
    }

    @Test("une clé inconnue en base est ignorée, pas fatale")
    func toleratesUnknownKeys() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = Activity(stravaID: 3, name: "Sortie", sportType: .run)
        context.insert(activity)
        // As a store written by a later version would contain.
        activity.editedFieldsRaw = ["name", "someFutureField"]

        #expect(activity.editedFields == [.name])
    }

    @Test("une pierre tombale retient l'identifiant et le nom")
    func discardedRemembers() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let stone = DiscardedActivity(stravaID: 42, name: "Sortie du matin")
        context.insert(stone)
        try context.save()

        let found = try context.fetch(FetchDescriptor<DiscardedActivity>()).first
        #expect(found?.stravaID == 42)
        // The name is kept so the settings screen can say what was discarded:
        // a bare identifier would make the list impossible to review.
        #expect(found?.name == "Sortie du matin")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:StravaLocalTests/DiscardedActivityTests`
Expected: FAIL, `value of type 'Activity' has no member 'uuid'`.

- [ ] **Step 3: Write minimal implementation**

Dans `StravaLocal/Model/Activity.swift`, remplacer les deux macros :

```swift
    #Index<Activity>([\.startDate], [\.stravaID], [\.uuid], [\.minLat], [\.maxLat], [\.minLon], [\.maxLon])
```

Le `#Unique<Activity>([\.stravaID])` est supprimé sans remplacement, avec ce commentaire au-dessus de `#Index` :

```swift
    // No uniqueness constraint any more. An activity created here has no Strava
    // identifier, and several zeroes would violate one — while *changing* a
    // constraint is exactly what turns a lightweight SwiftData migration into a
    // store that will not open. Removing one is safe; adding one is not.
    // Uniqueness of `stravaID` is guaranteed where it always really was: the
    // fetch-or-create in `ImportMapper`, covered by a re-import test.
```

Ajouter après `var stravaID: Int64 = 0` :

```swift
    /// Stable local identity, independent of Strava. Assigned once, at creation.
    var uuid: String = UUID().uuidString
    var sourceRaw: String = ActivitySource.strava.rawValue
    /// Raw keys of `ActivityField`, persisted. See `editedFields`.
    var editedFieldsRaw: [String] = []
    var editedAt: Date?
```

Et, près de `var sportType`, les accès :

```swift
    var source: ActivitySource {
        get { ActivitySource(rawValue: sourceRaw) ?? .strava }
        set { sourceRaw = newValue.rawValue }
    }

    /// The fields the user has edited, which the sync must leave alone.
    ///
    /// Unknown raw values are dropped rather than trapped on: a store written by
    /// a later version must still open in an older build.
    var editedFields: Set<ActivityField> {
        get { Set(editedFieldsRaw.compactMap(ActivityField.init(rawValue:))) }
        set { editedFieldsRaw = newValue.map(\.rawValue).sorted() }
    }

    func isEdited(_ field: ActivityField) -> Bool { editedFields.contains(field) }

    /// Adds to what the user has already claimed rather than replacing it: two
    /// successive edits of different fields must both stay protected.
    func markEdited(_ fields: Set<ActivityField>) {
        guard !fields.isEmpty else { return }
        editedFields = editedFields.union(fields)
        editedAt = Date()
    }
```

`StravaLocal/Model/DiscardedActivity.swift` :

```swift
import Foundation
import SwiftData

/// A Strava activity the user deleted, kept so it stays deleted.
///
/// The journal is the reference, so a deletion is a decision — and a full
/// resync must not undo it. Only the Strava identifier matters for that; the
/// name is kept so the settings screen can say what was discarded, a bare
/// number being impossible to review.
@Model
final class DiscardedActivity {
    #Index<DiscardedActivity>([\.stravaID])

    var stravaID: Int64 = 0
    var name: String = ""
    var discardedAt: Date = Date.distantPast

    init(stravaID: Int64, name: String, discardedAt: Date = Date()) {
        self.stravaID = stravaID
        self.name = name
        self.discardedAt = discardedAt
    }
}
```

Dans `StravaLocal/Model/ModelContainer+App.swift`, ajouter au schéma :

```swift
    static let schema = Schema([
        Activity.self, ActivityStreams.self, Athlete.self,
        Lap.self, Gear.self, SyncState.self, DiscardedActivity.self,
    ])
```

- [ ] **Step 4: Run the whole suite to verify nothing regressed**

Run: `xcodegen generate` puis `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build`
Expected: PASS, tous les tests existants compris. Zéro avertissement.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Model Tests/DiscardedActivityTests.swift project.yml
git commit -m "feat(model): identité locale, source, champs édités, pierres tombales

La contrainte d'unicité sur stravaID est retirée sans remplacement : une
activité créée ici n'a pas d'identifiant Strava, et plusieurs zéros la
violeraient — or modifier une contrainte est ce qui fait basculer une
migration légère en base illisible. L'unicité reste garantie là où elle
l'était réellement, dans le fetch-or-create du mapper."
```

---

### Task 3: La synchro n'écrase plus ce qui a été édité

**Files:**
- Modify: `StravaLocal/Sync/ImportMapper.swift:22-90`
- Test: `Tests/EditProtectionTests.swift`

**Interfaces:**
- Consumes: `Activity.isEdited(_:)`, `Activity.source` (tâche 2).
- Produces: rien de nouveau publiquement. `ImportMapper.upsert(summary:)` et `upsert(detail:)` respectent désormais `editedFields` et `source`.

- [ ] **Step 1: Write the failing test**

`Tests/EditProtectionTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("Protection des champs édités")
@MainActor
struct EditProtectionTests {
    private func summary(id: Int64, name: String, distance: Double) -> SummaryActivityDTO {
        try! FixtureLoader.decode(
            SummaryActivityDTO.self, from: "summary_activity",
            patching: ["id": id, "name": name, "distance": distance]
        )
    }

    @Test("un champ édité survit à un réimport, un champ intact est mis à jour")
    func protectsOnlyWhatWasEdited() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        let imported = try mapper.upsert(
            summary: summary(id: 7, name: "Nom de Strava", distance: 10_000)
        )
        imported.name = "Mon nom"
        imported.markEdited([.name])

        // Strava sends a new name AND a corrected distance.
        let again = try mapper.upsert(
            summary: summary(id: 7, name: "Nom de Strava v2", distance: 11_000)
        )

        // Both assertions matter. The first is the protection; the second is what
        // distinguishes field-by-field protection from freezing the activity —
        // without it, a rename would stop every future correction.
        #expect(again.name == "Mon nom")
        #expect(again.distance == 11_000)
    }

    @Test("une activité qui ne vient pas de Strava n'est jamais touchée")
    func leavesLocalActivitiesAlone() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        let manual = Activity(stravaID: 0, name: "Séance salle", sportType: .workout)
        manual.source = .manual
        manual.distance = 0
        context.insert(manual)

        // A Strava activity that happens to carry id 0 must not capture it.
        _ = try mapper.upsert(summary: summary(id: 0, name: "Autre", distance: 5_000))

        #expect(manual.name == "Séance salle")
        #expect(manual.distance == 0)
        #expect(manual.source == .manual)
    }

    @Test("réimporter deux fois ne duplique pas, sans contrainte d'unicité")
    func reimportDoesNotDuplicate() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        _ = try mapper.upsert(summary: summary(id: 9, name: "Sortie", distance: 8_000))
        _ = try mapper.upsert(summary: summary(id: 9, name: "Sortie", distance: 8_000))

        // This is the guarantee that replaces the dropped #Unique constraint.
        #expect(try context.fetch(FetchDescriptor<Activity>()).count == 1)
    }
}
```

Si `FixtureLoader.decode(_:from:patching:)` n'existe pas, l'ajouter dans `Tests/FixtureLoader.swift` :

```swift
    /// Decodes a fixture with a few top-level values replaced.
    ///
    /// Editing protection has to be tested against the same payload twice with
    /// one field changed; a second fixture file per case would drift from the
    /// first.
    static func decode<T: Decodable>(
        _ type: T.Type, from name: String, patching values: [String: Any]
    ) throws -> T {
        let data = try data(from: name)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for (key, value) in values { object[key] = value }
        let patched = try JSONSerialization.data(withJSONObject: object)
        return try decoder.decode(type, from: patched)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:StravaLocalTests/EditProtectionTests`
Expected: FAIL sur `again.name == "Mon nom"` — la valeur observée est `"Nom de Strava v2"`.

- [ ] **Step 3: Write minimal implementation**

Dans `ImportMapper`, ajouter le point de contrôle et l'utiliser. Au-dessus de `upsert(summary:)` :

```swift
    /// Writes a field unless the user has claimed it.
    ///
    /// Every assignment in `upsert(summary:)` goes through here, and that is the
    /// point: a field written directly would be a silent hole in the protection,
    /// impossible to spot by reading twenty-five similar lines.
    private func assign<Value>(
        _ field: ActivityField,
        on activity: Activity,
        _ keyPath: ReferenceWritableKeyPath<Activity, Value>,
        _ value: Value
    ) {
        guard !activity.isEdited(field) else { return }
        activity[keyPath: keyPath] = value
    }
```

Au début de `upsert(summary:)`, après la récupération ou la création :

```swift
        // Nothing the sync brought, nothing for it to update. Guards against a
        // manual activity being captured by a Strava identifier of 0.
        guard activity.source.isSynced else { return activity }
```

Puis remplacer les affectations des champs éditables. Les six concernées :

```swift
        assign(.name, on: activity, \.name, dto.name)
        assign(.sportType, on: activity, \.sportTypeRaw,
               SportType(stravaValue: dto.sport_type).rawValue)
        // Both properties behind one key, deliberately: the user edits a single
        // "Date" field, and protecting one of the two would leave every sort and
        // filter reading a value the sync had quietly put back.
        assign(.startDate, on: activity, \.startDate, dto.start_date)
        assign(.startDate, on: activity, \.startLocalDate, dto.start_date_local)
        assign(.distance, on: activity, \.distance, dto.distance)
        assign(.movingTime, on: activity, \.movingTime, dto.moving_time)
        assign(.totalElevationGain, on: activity, \.totalElevationGain,
               dto.total_elevation_gain)
        assign(.isCommute, on: activity, \.isCommute, dto.commute ?? false)
        assign(.isTrainer, on: activity, \.isTrainer, dto.trainer ?? false)
```

Les autres champs — vitesse, cardio, puissance, cadence, kudos, records, géométrie — restent en affectation directe : ils ne sont pas éditables, donc rien à protéger.

Dans `upsert(detail:)`, la seule affectation éditable est la description :

```swift
        assign(.notes, on: activity, \.activityDescription, dto.description)
```

Et la même garde de source en tête de `upsert(detail:)`.

- [ ] **Step 4: Run the whole suite**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build`
Expected: PASS. Les tests existants de `ImportMapperTests` doivent passer sans modification — une régression là signifierait que la garde de source est trop large.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Sync/ImportMapper.swift Tests/EditProtectionTests.swift Tests/FixtureLoader.swift
git commit -m "feat(sync): ne plus écraser un champ édité localement

Un point de contrôle unique par lequel passent les affectations éditables :
écrire un champ directement serait un trou silencieux dans la protection,
impossible à repérer en relisant vingt-cinq lignes semblables.

Le test vérifie les deux moitiés du contrat — le champ édité survit, et le
champ intact est bien mis à jour. Sans la seconde, un simple renommage
arrêterait toute correction ultérieure."
```

---

### Task 4: Une activité supprimée ne revient pas

**Files:**
- Modify: `StravaLocal/Sync/ImportMapper.swift`
- Modify: `StravaLocal/Sync/SyncEngine.swift`
- Test: `Tests/DiscardedActivityTests.swift` (ajouts)

**Interfaces:**
- Consumes: `DiscardedActivity` (tâche 2).
- Produces: `ImportMapper.isDiscarded(stravaID: Int64) throws -> Bool` et `ImportMapper.discard(_ activity: Activity) throws`, `ImportMapper.restore(_ stone: DiscardedActivity) throws`.

- [ ] **Step 1: Write the failing test**

Ajouter dans `Tests/DiscardedActivityTests.swift` :

```swift
    @Test("une activité écartée n'est pas réimportée")
    func discardedStaysDiscarded() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)

        let imported = try mapper.upsert(
            summary: try FixtureLoader.decode(
                SummaryActivityDTO.self, from: "summary_activity", patching: ["id": 11]
            )
        )
        try mapper.discard(imported)

        #expect(try context.fetch(FetchDescriptor<Activity>()).isEmpty)
        #expect(try mapper.isDiscarded(stravaID: 11))

        // A full resync sends it again; it must not come back.
        _ = try mapper.upsert(
            summary: try FixtureLoader.decode(
                SummaryActivityDTO.self, from: "summary_activity", patching: ["id": 11]
            )
        )
        #expect(try context.fetch(FetchDescriptor<Activity>()).isEmpty)
    }

    @Test("annuler l'écart la laisse revenir au passage suivant")
    func restoringLetsItBack() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let mapper = ImportMapper(context: context)
        let stone = DiscardedActivity(stravaID: 12, name: "Sortie")
        context.insert(stone)

        try mapper.restore(stone)

        #expect(try mapper.isDiscarded(stravaID: 12) == false)
        _ = try mapper.upsert(
            summary: try FixtureLoader.decode(
                SummaryActivityDTO.self, from: "summary_activity", patching: ["id": 12]
            )
        )
        #expect(try context.fetch(FetchDescriptor<Activity>()).count == 1)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:StravaLocalTests/DiscardedActivityTests`
Expected: FAIL, `value of type 'ImportMapper' has no member 'discard'`.

- [ ] **Step 3: Write minimal implementation**

Dans `ImportMapper` :

```swift
    func isDiscarded(stravaID: Int64) throws -> Bool {
        guard stravaID != 0 else { return false }
        var descriptor = FetchDescriptor<DiscardedActivity>(
            predicate: #Predicate { $0.stravaID == stravaID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty == false
    }

    /// Deletes an activity, and remembers it if Strava would send it again.
    ///
    /// A local activity leaves no stone: nothing would ever re-create it, and a
    /// row saying "never import identifier 0" would be a trap.
    func discard(_ activity: Activity) throws {
        if activity.source.isSynced, activity.stravaID != 0 {
            context.insert(
                DiscardedActivity(stravaID: activity.stravaID, name: activity.name)
            )
        }
        context.delete(activity)
        try context.save()
    }

    func restore(_ stone: DiscardedActivity) throws {
        context.delete(stone)
        try context.save()
    }
```

Et en tête de `upsert(summary:)`, **avant** la récupération ou la création :

```swift
        // Checked before anything is created, so a discarded activity costs
        // neither a row nor, in phase B, a request against the quota.
        guard try !isDiscarded(stravaID: dto.id) else {
            throw ImportSkip.discarded
        }
```

avec, au bas du fichier :

```swift
/// Not an error: a deliberate skip the sync counts as handled.
enum ImportSkip: Error {
    case discarded
}
```

Dans `SyncEngine`, la boucle de la phase A attrape ce cas sans le compter comme un échec — chercher l'appel à `upsert(summary:)` et l'entourer :

```swift
                do {
                    let activity = try mapper.upsert(summary: dto)
                    // …file d'attente des streams inchangée…
                } catch ImportSkip.discarded {
                    continue
                }
```

- [ ] **Step 4: Run the whole suite**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Sync Tests/DiscardedActivityTests.swift
git commit -m "feat(sync): une activité supprimée ne revient pas à la resynchro

La vérification a lieu avant toute création, donc une activité écartée ne
coûte ni ligne en base ni requête sur le quota en phase B.

Une activité locale ne laisse pas de pierre tombale : rien ne la
recréerait, et une ligne disant « ne jamais importer l'identifiant 0 »
serait un piège."
```

---

### Task 5: Le cœur de l'édition, sans interface

**Files:**
- Create: `StravaLocal/Features/ActivityEditor/ActivityDraft.swift`
- Test: `Tests/ActivityDraftTests.swift` (ajouts)

**Interfaces:**
- Consumes: `ActivityField`, `ActivitySource`, `Activity.markEdited(_:)`.
- Produces: `struct ActivityDraft: Equatable` avec `var name: String`, `var sport: SportType`, `var startLocalDate: Date`, `var distanceKm: Double`, `var movingMinutes: Double`, `var elevationGain: Double`, `var notes: String`, `var isCommute: Bool`, `var isTrainer: Bool` ; `init(_ activity: Activity)`, `init(startingOn date: Date)`, `var validationMessage: String?`, `func changedFields(comparedTo activity: Activity) -> Set<ActivityField>`, `func apply(to activity: Activity)`, `func makeActivity() -> Activity`.

- [ ] **Step 1: Write the failing test**

Ajouter dans `Tests/ActivityDraftTests.swift` :

```swift
@Suite("ActivityDraft")
@MainActor
struct ActivityDraftTests {
    private func makeActivity(in context: ModelContext) -> Activity {
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        activity.distance = 10_000
        activity.movingTime = 3_600
        activity.totalElevationGain = 250
        activity.startLocalDate = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(activity)
        return activity
    }

    @Test("les unités du formulaire sont celles de l'utilisateur")
    func convertsUnitsAtTheBoundary() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let draft = ActivityDraft(makeActivity(in: context))

        // Kilometres and minutes in the form, metres and seconds in the model:
        // the conversion lives here so no view has to know about it.
        #expect(draft.distanceKm == 10)
        #expect(draft.movingMinutes == 60)
        #expect(draft.elevationGain == 250)
    }

    @Test("enregistrer sans rien changer ne fige aucun champ")
    func changingNothingMarksNothing() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        let draft = ActivityDraft(activity)

        draft.apply(to: activity)

        // Otherwise merely opening the sheet would stop the sync updating this
        // activity for ever, with nothing on screen to say so.
        #expect(activity.editedFields.isEmpty)
        #expect(activity.editedAt == nil)
    }

    @Test("seuls les champs réellement modifiés sont marqués")
    func marksOnlyWhatChanged() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        var draft = ActivityDraft(activity)
        draft.name = "Mon nom"
        draft.distanceKm = 12

        #expect(draft.changedFields(comparedTo: activity) == [.name, .distance])
        draft.apply(to: activity)

        #expect(activity.name == "Mon nom")
        #expect(activity.distance == 12_000)
        #expect(activity.editedFields == [.name, .distance])
        #expect(activity.editedAt != nil)
    }

    @Test("deux éditions successives s'accumulent")
    func editsAccumulate() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context)
        var first = ActivityDraft(activity)
        first.name = "Mon nom"
        first.apply(to: activity)

        var second = ActivityDraft(activity)
        second.elevationGain = 400
        second.apply(to: activity)

        // The second edit must not release the first.
        #expect(activity.editedFields == [.name, .totalElevationGain])
    }

    @Test("un brouillon invalide dit pourquoi")
    func explainsWhyItIsInvalid() {
        var draft = ActivityDraft(startingOn: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(draft.validationMessage != nil)   // no name yet

        draft.name = "Séance salle"
        draft.movingMinutes = 0
        #expect(draft.validationMessage != nil)   // no duration

        draft.movingMinutes = 45
        #expect(draft.validationMessage == nil)

        draft.distanceKm = -1
        #expect(draft.validationMessage != nil)   // negative distance
    }

    @Test("un brouillon neuf produit une activité locale sans identifiant Strava")
    func createsALocalActivity() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        var draft = ActivityDraft(startingOn: Date(timeIntervalSince1970: 1_700_000_000))
        draft.name = "Renforcement"
        draft.sport = .workout
        draft.movingMinutes = 45

        let created = draft.makeActivity()
        context.insert(created)

        #expect(created.stravaID == 0)
        #expect(created.source == .manual)
        #expect(created.movingTime == 2_700)
        // Nothing to protect: the sync ignores this activity outright, so a set of
        // "edited" fields would be noise.
        #expect(created.editedFields.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:StravaLocalTests/ActivityDraftTests`
Expected: FAIL, `cannot find 'ActivityDraft' in scope`.

- [ ] **Step 3: Write minimal implementation**

`StravaLocal/Features/ActivityEditor/ActivityDraft.swift` :

```swift
import Foundation

/// What the editing sheet holds, and everything it knows how to decide.
///
/// A value type with no view in sight, which is what makes the interesting part
/// testable: which fields the user actually changed, whether the whole is
/// coherent, and what to write back. The sheet becomes a set of bindings.
///
/// Units are the user's — kilometres and minutes — and the conversion to the
/// model's metres and seconds happens here, so no view has to know about it.
struct ActivityDraft: Equatable {
    var name: String
    var sport: SportType
    var startLocalDate: Date
    var distanceKm: Double
    var movingMinutes: Double
    var elevationGain: Double
    var notes: String
    var isCommute: Bool
    var isTrainer: Bool

    init(_ activity: Activity) {
        name = activity.name
        sport = activity.sportType
        startLocalDate = activity.startLocalDate
        distanceKm = activity.distance / 1000
        movingMinutes = Double(activity.movingTime) / 60
        elevationGain = activity.totalElevationGain
        notes = activity.activityDescription ?? ""
        isCommute = activity.isCommute
        isTrainer = activity.isTrainer
    }

    /// An empty draft for a session that never went through a watch.
    init(startingOn date: Date) {
        name = ""
        sport = .workout
        startLocalDate = date
        distanceKm = 0
        movingMinutes = 0
        elevationGain = 0
        notes = ""
        isCommute = false
        isTrainer = false
    }

    /// Why this cannot be saved, or nil if it can.
    ///
    /// A message rather than a Bool so the sheet can say what is missing instead
    /// of merely greying out a button.
    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Le nom ne peut pas être vide."
        }
        if movingMinutes <= 0 {
            return "La durée doit être supérieure à zéro."
        }
        if distanceKm < 0 || elevationGain < 0 {
            return "Distance et dénivelé ne peuvent pas être négatifs."
        }
        return nil
    }

    /// The fields whose value differs from the activity's.
    ///
    /// Compared field by field rather than assumed from what the sheet touched:
    /// typing in a field and undoing it must not count as an edit.
    func changedFields(comparedTo activity: Activity) -> Set<ActivityField> {
        var changed: Set<ActivityField> = []
        let original = ActivityDraft(activity)
        if name != original.name { changed.insert(.name) }
        if sport != original.sport { changed.insert(.sportType) }
        if startLocalDate != original.startLocalDate { changed.insert(.startDate) }
        if distanceKm != original.distanceKm { changed.insert(.distance) }
        if movingMinutes != original.movingMinutes { changed.insert(.movingTime) }
        if elevationGain != original.elevationGain {
            changed.insert(.totalElevationGain)
        }
        if notes != original.notes { changed.insert(.notes) }
        if isCommute != original.isCommute { changed.insert(.isCommute) }
        if isTrainer != original.isTrainer { changed.insert(.isTrainer) }
        return changed
    }

    /// Writes the values, and claims only the fields that moved.
    func apply(to activity: Activity) {
        let changed = changedFields(comparedTo: activity)
        write(to: activity)
        // Only for what the sync could otherwise overwrite. On a local activity
        // every field is the user's, so a set of claims would be noise.
        if activity.source.isSynced {
            activity.markEdited(changed)
        }
    }

    /// A brand-new local activity.
    func makeActivity() -> Activity {
        let activity = Activity(stravaID: 0, name: name, sportType: sport)
        activity.source = .manual
        write(to: activity)
        return activity
    }

    private func write(to activity: Activity) {
        activity.name = name.trimmingCharacters(in: .whitespaces)
        activity.sportType = sport
        activity.startLocalDate = startLocalDate
        // Both, because every sort and filter reads `startDate` while the user
        // only ever sees the local one.
        activity.startDate = startLocalDate
        activity.distance = distanceKm * 1000
        activity.movingTime = Int(movingMinutes * 60)
        // Elapsed time is not editable and would otherwise stay below moving
        // time, which reads as a bug in the detail pane.
        activity.elapsedTime = max(activity.elapsedTime, activity.movingTime)
        activity.totalElevationGain = elevationGain
        activity.activityDescription = notes.isEmpty ? nil : notes
        activity.isCommute = isCommute
        activity.isTrainer = isTrainer
    }
}
```

- [ ] **Step 4: Run the whole suite**

Run: `xcodegen generate` puis `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Features/ActivityEditor Tests/ActivityDraftTests.swift project.yml
git commit -m "feat(edition): ActivityDraft, le cœur testable de l'édition

Un type valeur sans vue : c'est ce qui rend testable la partie
intéressante — quels champs ont réellement bougé, la cohérence de
l'ensemble, ce qu'on réécrit. La feuille se réduira à des liaisons.

Les champs sont comparés un à un plutôt que déduits de ce que la feuille a
touché : saisir puis annuler ne doit pas compter comme une édition."
```

---

### Task 6: La feuille d'édition

**Files:**
- Create: `StravaLocal/Features/ActivityEditor/ActivityEditorSheet.swift`
- Modify: `StravaLocal/App/RootView.swift`
- Modify: `StravaLocal/Features/ActivityDetail/ActivityDetailView.swift`

**Interfaces:**
- Consumes: `ActivityDraft` (tâche 5).
- Produces: `struct ActivityEditorSheet: View` avec `init(mode: ActivityEditorSheet.Mode, onSave: (ActivityDraft) -> Void)` et `enum Mode { case edit(Activity), create }`.

- [ ] **Step 1: Write the sheet**

`StravaLocal/Features/ActivityEditor/ActivityEditorSheet.swift` :

```swift
import SwiftUI

/// The one form for editing an activity and for creating one.
///
/// A modal sheet rather than inline fields, for a reason that is not cosmetic:
/// an explicit Save is what tells us which fields the user actually meant to
/// change, which is exactly what `editedFields` must contain. Inline editing
/// would freeze a field on a stray keystroke.
struct ActivityEditorSheet: View {
    enum Mode {
        case edit(Activity)
        case create
    }

    let mode: Mode
    let onSave: (ActivityDraft) -> Void

    @State private var draft: ActivityDraft
    @Environment(\.dismiss) private var dismiss

    init(mode: Mode, onSave: @escaping (ActivityDraft) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case let .edit(activity):
            _draft = State(initialValue: ActivityDraft(activity))
        case .create:
            _draft = State(initialValue: ActivityDraft(startingOn: Date()))
        }
    }

    private var title: String {
        switch mode {
        case .edit: "Modifier l'activité"
        case .create: "Nouvelle activité"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Nom", text: $draft.name)
                    Picker("Sport", selection: $draft.sport) {
                        ForEach(SportType.allCases) { sport in
                            Label(sport.displayName, systemImage: sport.symbolName)
                                .tag(sport)
                        }
                    }
                    DatePicker("Date", selection: $draft.startLocalDate)
                }

                Section("Chiffres") {
                    OptionalNumberField(
                        title: "Distance", unit: "km",
                        value: Binding(
                            get: { draft.distanceKm == 0 ? nil : draft.distanceKm },
                            set: { draft.distanceKm = $0 ?? 0 }
                        )
                    )
                    OptionalNumberField(
                        title: "Durée", unit: "min",
                        value: Binding(
                            get: { draft.movingMinutes == 0 ? nil : draft.movingMinutes },
                            set: { draft.movingMinutes = $0 ?? 0 }
                        )
                    )
                    OptionalNumberField(
                        title: "D+", unit: "m",
                        value: Binding(
                            get: { draft.elevationGain == 0 ? nil : draft.elevationGain },
                            set: { draft.elevationGain = $0 ?? 0 }
                        )
                    )
                }

                Section("Notes") {
                    // First `TextEditor` in the project, so no house style to
                    // follow — and it arrives borderless, which reads as nothing
                    // at all beside the bordered fields above it.
                    TextEditor(text: $draft.notes)
                        .font(.body)
                        .frame(minHeight: 70)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor))
                        )
                }

                Section {
                    Toggle("Domicile-travail", isOn: $draft.isCommute)
                    Toggle("Home-trainer", isOn: $draft.isTrainer)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                // The reason rather than a greyed-out button with no explanation.
                if let message = draft.validationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.validationMessage != nil)
            }
            .padding(12)
        }
        .frame(width: 460, height: 560)
        .navigationTitle(title)
    }
}
```

- [ ] **Step 2: Wire it into RootView**

Dans `RootView`, ajouter l'état et la présentation :

```swift
    /// Which editor is open, if any. One state rather than two booleans: the two
    /// modes are exclusive and a pair of flags would let both be true.
    @State private var editor: ActivityEditorSheet.Mode?
```

`ActivityEditorSheet.Mode` doit être `Identifiable` pour `sheet(item:)`. L'ajouter dans le fichier de la feuille :

```swift
extension ActivityEditorSheet.Mode: Identifiable {
    var id: String {
        switch self {
        case let .edit(activity): "edit-\(activity.uuid)"
        case .create: "create"
        }
    }
}
```

Puis sur `splitView` :

```swift
        .sheet(item: $editor) { mode in
            ActivityEditorSheet(mode: mode) { draft in
                switch mode {
                case let .edit(activity):
                    draft.apply(to: activity)
                case .create:
                    let created = draft.makeActivity()
                    modelContext.insert(created)
                    selectedActivities = [created.id]
                }
                try? modelContext.save()
            }
        }
```

avec `@Environment(\.modelContext) private var modelContext` sur `RootView`.

Et deux entrées de barre d'outils, dans `syncToolbar` :

```swift
            // Grouped, not three loose buttons: the toolbar already carries three
            // items, and six side by side is where it stops reading as a toolbar.
            // These three act on the selected activity and belong together.
            ToolbarItemGroup {
                Button {
                    editor = .create
                } label: {
                    Label("Nouvelle activité", systemImage: "plus")
                }
                .help("Ajouter une activité saisie à la main")

                Button {
                    if let selected { editor = .edit(selected) }
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                .disabled(selected == nil)
                .help("Modifier l'activité sélectionnée")

                Button {
                    pendingDeletion = selected
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                .disabled(selected == nil)
                .help("Supprimer l'activité sélectionnée")
            }
```

- [ ] **Step 3: Show the source and the edit date in the detail pane**

Dans `ActivityDetailView`, sous la date, ajouter :

```swift
            if activity.source != .strava || activity.editedAt != nil {
                // Said outright: an activity the sync will not update is a
                // different thing from one it will, and nothing else on screen
                // would tell you which you are looking at.
                HStack(spacing: 6) {
                    if activity.source != .strava {
                        Label(activity.source.displayName, systemImage: "pencil.and.list.clipboard")
                    }
                    if let editedAt = activity.editedAt {
                        Label(
                            "Modifiée le \(Format.dateOnly(editedAt))",
                            systemImage: "pencil"
                        )
                        .help(
                            "Champs protégés de la synchro : "
                                + activity.editedFields
                                    .map(\.displayName).sorted()
                                    .joined(separator: ", ")
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
```

- [ ] **Step 4: Build and run the whole suite**

Run: `xcodegen generate` puis `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build`
Expected: PASS, zéro avertissement.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Features/ActivityEditor StravaLocal/App/RootView.swift StravaLocal/Features/ActivityDetail/ActivityDetailView.swift project.yml
git commit -m "feat(edition): feuille d'édition et d'ajout

Une feuille modale et non des champs en ligne, pour une raison qui n'est
pas cosmétique : un Enregistrer explicite dit quels champs l'utilisateur a
voulu changer, ce qui est exactement ce que editedFields doit contenir.

Le détail annonce la source et la date d'édition : une activité que la
synchro ne mettra plus à jour est autre chose qu'une activité normale, et
rien d'autre à l'écran ne le dirait."
```

---

### Task 7: La suppression, et son écran de rattrapage

**Files:**
- Modify: `StravaLocal/App/RootView.swift`
- Create: `StravaLocal/Features/Settings/DiscardedActivitiesSection.swift`
- Modify: `StravaLocal/Features/Settings/SyncSettingsView.swift`

**Interfaces:**
- Consumes: `ImportMapper.discard(_:)`, `ImportMapper.restore(_:)` (tâche 4).
- Produces: `struct DiscardedActivitiesSection: View`, dont le corps est une `Section` destinée au `Form` de `SyncSettingsView`.

- [ ] **Step 1: Add the delete command with confirmation**

Dans `RootView` :

```swift
    /// The activity awaiting a delete confirmation, if any.
    @State private var pendingDeletion: Activity?
```

Sur `splitView` :

```swift
        .confirmationDialog(
            pendingDeletion.map { "Supprimer « \($0.name) » ?" } ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let pendingDeletion {
                    delete(pendingDeletion)
                }
                pendingDeletion = nil
            }
            Button("Annuler", role: .cancel) { pendingDeletion = nil }
        } message: {
            // Two different consequences, so two different texts. Telling the
            // user a Strava activity "will be deleted" would be a half-truth:
            // what makes it stay deleted is a record they can undo in settings.
            if pendingDeletion?.source == .strava {
                Text(
                    "Elle ne reviendra pas lors d'une resynchronisation. "
                        + "Les réglages permettent d'annuler cet écart."
                )
            } else {
                Text("Cette activité n'existe que dans le journal : elle sera perdue.")
            }
        }
```

et la méthode :

```swift
    private func delete(_ activity: Activity) {
        selectedActivities.remove(activity.id)
        try? ImportMapper(context: modelContext).discard(activity)
    }
```

Le bouton de barre d'outils est déjà posé en tâche 6, dans le groupe des trois
actions sur l'activité — il n'y a rien à ajouter ici.

- [ ] **Step 2: The settings screen**

`StravaLocal/Features/Settings/DiscardedActivitiesSection.swift`. C'est une
`Section`, pas un écran : elle s'insère dans le `Form` de `SyncSettingsView`, à la
suite des réglages de synchronisation.

```swift
import SwiftUI
import SwiftData

/// The activities discarded from the journal, and the way back.
///
/// Without this screen a deletion would be both permanent and invisible, which
/// is the worst of the two: the point of a tombstone is that a resync cannot
/// undo the decision, not that the decision cannot be revisited.
struct DiscardedActivitiesSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiscardedActivity.discardedAt, order: .reverse)
    private var discarded: [DiscardedActivity]

    var body: some View {
        Section {
                if discarded.isEmpty {
                    Text("Aucune activité écartée.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(discarded) { stone in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stone.name)
                                Text("Écartée le \(Format.dateOnly(stone.discardedAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Réintégrer") {
                                try? ImportMapper(context: modelContext).restore(stone)
                            }
                        }
                    }
                }
            } header: {
                Text("Activités écartées")
            } footer: {
                Text(
                    "Ces activités Strava ont été supprimées du journal et ne "
                        + "reviendront pas lors d'une synchronisation. Les "
                        + "réintégrer les laissera revenir au passage suivant."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
    }
}
```

Dans `SyncSettingsView`, à la fin de son `Form` :

```swift
            DiscardedActivitiesSection()
```

- [ ] **Step 3: Add the keyboard commands**

Les commandes vivent dans l'`App`, l'état dans la vue. Une fermeture posée sur
`AppEnvironment` est le plus petit pont entre les deux ; une notification en serait
un plus gros pour rien.

Dans `AppEnvironment` :

```swift
    /// Installed by `RootView` so the menu bar can reach the window's own state.
    ///
    /// Nil until a window exists, which is exactly what disables the menu items:
    /// there is nothing to add an activity to before then.
    var requestNewActivity: (() -> Void)?
    var requestEditSelection: (() -> Void)?
    var requestDeleteSelection: (() -> Void)?
```

Dans `RootView`, sur `splitView` :

```swift
        .onAppear {
            app.requestNewActivity = { editor = .create }
            app.requestEditSelection = { if let selected { editor = .edit(selected) } }
            app.requestDeleteSelection = { pendingDeletion = selected }
        }
```

Dans `StravaLocalApp`, un groupe de commandes après « Nouveau » :

```swift
            CommandGroup(after: .newItem) {
                Button("Nouvelle activité") { app.requestNewActivity?() }
                    .keyboardShortcut("n")
                    .disabled(app.requestNewActivity == nil)
                Button("Modifier l'activité") { app.requestEditSelection?() }
                    .keyboardShortcut("e")
                    .disabled(app.requestEditSelection == nil)
                Button("Supprimer l'activité") { app.requestDeleteSelection?() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(app.requestDeleteSelection == nil)
            }
```

Les fermetures étant réinstallées à chaque apparition, elles capturent l'état
courant de la vue et non celui du premier lancement.

- [ ] **Step 4: Build and run the whole suite**

Run: `xcodegen generate` puis `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build`
Expected: PASS, zéro avertissement.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/App StravaLocal/Features/Settings project.yml
git commit -m "feat(journal): suppression avec pierre tombale et écran de rattrapage

La confirmation dit laquelle des deux suppressions elle est : une activité
Strava ne reviendra pas à la resynchro, une activité locale est perdue. Ce
ne sont pas les mêmes conséquences, ce ne peut pas être le même texte.

L'écran des écartées existe parce qu'une suppression à la fois définitive
et invisible serait le pire des deux : une pierre tombale doit empêcher une
resynchro de défaire la décision, pas empêcher de la revoir."
```

---

### Task 8: Les uuid des lignes existantes

**Files:**
- Modify: `StravaLocal/App/StravaLocalApp.swift`
- Create: `StravaLocal/Model/StoreMaintenance.swift`
- Test: `Tests/StoreMaintenanceTests.swift`

**Interfaces:**
- Consumes: `Activity.uuid`.
- Produces: `enum StoreMaintenance { static func run(_ context: ModelContext) throws -> Int }`, qui rend le nombre de lignes complétées.

- [ ] **Step 1: Write the failing test**

`Tests/StoreMaintenanceTests.swift` :

```swift
import Testing
import SwiftData
@testable import StravaLocal

@Suite("StoreMaintenance")
@MainActor
struct StoreMaintenanceTests {
    @Test("les activités sans uuid en reçoivent un, les autres sont laissées")
    func fillsMissingIdentifiers() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let old = Activity(stravaID: 1, name: "Ancienne", sportType: .run)
        old.uuid = ""   // as a row written before the field existed
        let recent = Activity(stravaID: 2, name: "Récente", sportType: .run)
        let keptUUID = recent.uuid
        context.insert(old)
        context.insert(recent)

        #expect(try StoreMaintenance.run(context) == 1)

        #expect(old.uuid.isEmpty == false)
        // Untouched, because reassigning would break anything already keyed on it.
        #expect(recent.uuid == keptUUID)
    }

    @Test("des uuid dupliqués sont départagés, un seul étant conservé")
    func breaksTiesBetweenDuplicates() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        // The case that matters, and the reason this does not merely look for
        // empty strings: a SwiftData property default is a single value in the
        // managed model, so a lightweight migration may well give every existing
        // row the *same* generated uuid. None would be empty, and a backfill
        // looking only for empties would leave 840 activities sharing an identity
        // that views use as a key.
        let first = Activity(stravaID: 1, name: "Une", sportType: .run)
        let second = Activity(stravaID: 2, name: "Deux", sportType: .run)
        let third = Activity(stravaID: 3, name: "Trois", sportType: .run)
        for activity in [first, second, third] {
            activity.uuid = "same-for-every-migrated-row"
            context.insert(activity)
        }

        #expect(try StoreMaintenance.run(context) == 2)

        let uuids = [first, second, third].map(\.uuid)
        #expect(Set(uuids).count == 3)
        #expect(uuids.allSatisfy { !$0.isEmpty })
    }

    @Test("relancer la maintenance ne fait rien de plus")
    func isIdempotent() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        activity.uuid = ""
        context.insert(activity)

        #expect(try StoreMaintenance.run(context) == 1)
        // It runs at every launch, so a second pass must be a no-op.
        #expect(try StoreMaintenance.run(context) == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:StravaLocalTests/StoreMaintenanceTests`
Expected: FAIL, `cannot find 'StoreMaintenance' in scope`.

- [ ] **Step 3: Write minimal implementation**

`StravaLocal/Model/StoreMaintenance.swift` :

```swift
import Foundation
import SwiftData

/// The one place for everything that has to happen once to an existing store.
///
/// A single entry point rather than a mechanism per field: the next migration
/// will want somewhere obvious to live, and two of them scattered across the
/// launch path would be two to find.
enum StoreMaintenance {
    /// Gives every activity an identity of its own.
    ///
    /// Two cases, and the second is why this does not merely look for empty
    /// strings. A SwiftData property default is a single value in the managed
    /// model, so a lightweight migration may give every existing row the *same*
    /// generated uuid — none empty, all identical, and views keying off it would
    /// treat hundreds of activities as one. Rather than bet on which of the two
    /// SwiftData does, handle both.
    ///
    /// Returns how many rows were changed, which is what makes it testable and
    /// its idempotence checkable.
    @discardableResult
    static func run(_ context: ModelContext) throws -> Int {
        let activities = try context.fetch(FetchDescriptor<Activity>())
        var seen: Set<String> = []
        var changed = 0

        for activity in activities {
            // First claimant of a duplicated uuid keeps it; the rest are reissued.
            // Reassigning them all would churn identities that are already fine.
            if activity.uuid.isEmpty || seen.contains(activity.uuid) {
                activity.uuid = UUID().uuidString
                changed += 1
            }
            seen.insert(activity.uuid)
        }

        guard changed > 0 else { return 0 }
        try context.save()
        return changed
    }
}
```

- [ ] **Step 4: Call it at launch**

Dans `StravaLocalApp.init`, à côté de l'appel existant à `DemoData.populateIfNeeded` :

```swift
        // Before any view reads an activity. Failing is not worth a crash: the
        // rows keep an empty uuid and the next launch tries again.
        try? StoreMaintenance.run(ModelContext(container))
```

- [ ] **Step 5: Run the whole suite and commit**

Run: `xcodegen generate` puis `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build`
Expected: PASS.

```bash
git add StravaLocal/Model/StoreMaintenance.swift StravaLocal/App/StravaLocalApp.swift Tests/StoreMaintenanceTests.swift project.yml
git commit -m "feat(model): compléter les uuid des lignes existantes au lancement

SwiftData donne à une nouvelle propriété sa valeur par défaut pour chaque
ligne existante, et une valeur par défaut ne peut pas être un UUID neuf par
ligne : toutes les activités migrées partageraient le même.

Un point d'entrée unique pour tout ce qui doit arriver une fois, plutôt
qu'un mécanisme par champ à retrouver plus tard dans le chemin de
lancement."
```

---

### Task 9: Documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite the opening and add a section**

Remplacer le paragraphe d'ouverture par :

```markdown
Journal local de vos activités physiques sur macOS. Vos données vous appartiennent
et vivent sur votre disque : Strava n'est qu'une des façons de l'alimenter, aux
côtés de la saisie manuelle.
```

Ajouter après « Synchronisation » :

```markdown
## Le journal est la référence

Une activité peut naître ici, être corrigée ici, et disparaître ici. La
synchronisation Strava alimente le journal ; elle ne le commande pas.

**Édition (⌘E).** Nom, sport, date, distance, durée, dénivelé, notes et marqueurs
sont modifiables. Un champ que vous modifiez est **protégé champ par champ** : une
resynchronisation continuera d'apporter les corrections de Strava sur les autres,
mais ne touchera plus celui-là. Le détail de l'activité indique ce qui est protégé.

Les séries mesurées — cardio, puissance, cadence, altitude — et la trace ne sont
pas modifiables : elles viennent de l'appareil, et aucune valeur unique saisie à la
main n'aurait de sens.

**Ajout (⌘N).** Une séance sans montre s'ajoute à la main. Elle n'a pas
d'identifiant Strava et la synchronisation l'ignore entièrement.

**Suppression (⌘⌫).** Une activité Strava supprimée laisse une trace discrète qui
l'empêche de revenir à la resynchronisation suivante. Les réglages, onglet
« Écartées », les listent et permettent de les réintégrer.

Rien n'est jamais écrit chez Strava. L'API le permettrait — `PUT /activities/{id}`
accepte le nom, la description, le sport et le matériel — mais c'est un choix :
aucune autorisation d'écriture n'est demandée, aucun quota n'est consommé, et une
panne de leur côté ne peut pas abîmer votre journal.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: le journal est la référence, la synchro l'alimente"
```

---

## Self-Review

**Couverture du spec.** Les six décisions et chaque section du modèle et des gestes ont une tâche : identité et champs (T2), protection (T3), pierres tombales (T4), cœur d'édition (T5), feuille et ajout (T6), suppression et rattrapage (T7), lignes existantes (T8). Les sections « Import GPX » et « Le renommage » du spec ne sont **pas** couvertes : elles font l'objet des lots 3 et 4, annoncés en tête de ce plan.

**Écart connu, assumé et signalé** : le spec fait de `uuid` la clé unique ; ce plan ne déclare aucune contrainte d'unicité, pour ne pas risquer une migration impossible. L'unicité est couverte par le test de réimport de la tâche 3.

**Cohérence des types.** `ActivityField` et `ActivitySource` (T1) sont consommés tels quels par T2, T3, T5. `ActivityDraft.apply(to:)` et `makeActivity()` sont produits en T5 et appelés en T6. `ImportMapper.discard(_:)` et `restore(_:)` sont produits en T4 et appelés en T7. `StoreMaintenance.run(_:)` rend un `Int` en T8, testé comme tel.

**Points où l'implémenteur devra juger.** Deux, signalés dans les tâches plutôt que masqués : l'emplacement exact de la garde `ImportSkip.discarded` dans la boucle de `SyncEngine` dépend de la forme actuelle de la boucle (T4, étape 3), et le passage de `requestNewActivity` par `AppEnvironment` peut se révéler inutile si les commandes de menu atteignent déjà l'état de la fenêtre (T7, étape 3).
