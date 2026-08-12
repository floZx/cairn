# La fiche d'une activité, resserrée — plan d'implémentation

> **Statut** : abandonné le 12 août 2026. Le plan a été exécuté puis annulé —
> voir la spec pour ce qui a été essayé.

> **Pour un agent :** SOUS-COMPÉTENCE REQUISE — `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour dérouler ce plan tâche par
> tâche. Les étapes sont des cases à cocher (`- [ ]`).

**But :** rendre la présentation « fiche » de la liste des activités plus dense
et plus parlante — libellés retirés, allure ajoutée, colonnes vides plutôt que
zéros, et un demi-gras sur le premier chiffre des sorties notables.

**Architecture :** la règle — quels chiffres une activité porte, lequel prend la
graisse — sort de la vue dans une fonction pure et testée ; la vue ne fait plus
que la dessiner.

**Pile :** Swift 6, SwiftUI, SwiftData, Swift Testing.

**Spec :** `docs/specs/2026-08-12-fiche-activite-design.md`.

## Contraintes globales

- **Cinq colonnes, toujours dans le même ordre** — distance, durée, dénivelé,
  allure, fréquence cardiaque — pour que deux lignes voisines s'alignent quoi
  qu'elles portent. Une mesure absente laisse sa colonne vide, jamais un zéro.
- **La graisse est le seul appui ajouté** : ni couleur, ni corps plus grand, ni
  fond. Une taille différente casserait l'alignement des colonnes.
- **Notable** : au moins 90 minutes en mouvement, ou au moins 20 km. Les deux
  nombres vivent côte à côte, nommés, dans le type.
- **Les unités passent par `Format`** : `distance`, `durationCompact`,
  `elevation`, `speed(_:sport:)`, `heartrate`. Aucune arithmétique nouvelle.
- La hauteur de la fiche (42 pt) et la vignette (44 pt) ne bougent pas.
- **Commentaires de code en anglais**, noms de tests en français.
- La suite compte **755 tests** avant ce plan.
- Lancer les tests :
  `xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build`

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `Cairn/Features/ActivityList/ActivityCard.swift` | modifié : la règle en statiques, puis la vue qui la dessine |
| `Tests/ActivityCardsTests.swift` | modifié : la suite existante gagne les tests de la règle |

---

### Tâche 1 : la règle, en fonctions pures

**Fichiers :**
- Modifier : `Cairn/Features/ActivityList/ActivityCard.swift`
- Modifier : `Tests/ActivityCardsTests.swift`

**Interfaces produites :**
```swift
extension ActivityCard {
    struct Figure: Equatable {
        var value: String?
        var isLeading: Bool
    }
    static func isNotable(_ activity: Activity) -> Bool
    static func figures(for activity: Activity) -> [Figure]
}
```

- [ ] **Étape 1 : écrire les tests qui échouent**

À ajouter dans `Tests/ActivityCardsTests.swift`, dans une nouvelle suite au
bout du fichier :

```swift
@Suite("Les chiffres d'une fiche")
@MainActor
struct ActivityCardFiguresTests {
    private func makeActivity(
        sport: SportType = .run, distance: Double = 9_000,
        movingTime: Int = 2_905, elevation: Double = 32,
        heartrate: Double? = 132
    ) -> Activity {
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: sport)
        activity.distance = distance
        activity.movingTime = movingTime
        activity.totalElevationGain = elevation
        activity.averageHeartrate = heartrate
        activity.averageSpeed = movingTime > 0 ? distance / Double(movingTime) : 0
        return activity
    }

    @Test("une course porte ses cinq chiffres, allure comprise")
    func arunCarriesFiveFigures() {
        let figures = ActivityCard.figures(for: makeActivity())
        #expect(figures.count == 5)
        #expect(figures[0].value == Format.distance(9_000))
        #expect(figures[1].value == Format.durationCompact(2_905))
        #expect(figures[2].value == Format.elevation(32))
        #expect(figures[3].value?.contains("/km") == true)
        #expect(figures[4].value == Format.heartrate(132))
    }

    @Test("une séance en salle laisse ses colonnes vides plutôt que des zéros")
    func agymSessionLeavesBlanks() {
        let session = makeActivity(
            sport: .workout, distance: 0, movingTime: 1_560, elevation: 0,
            heartrate: 86
        )
        let figures = ActivityCard.figures(for: session)
        // Les places ne bougent pas : deux lignes voisines restent alignées.
        #expect(figures.count == 5)
        #expect(figures[0].value == nil)
        #expect(figures[1].value == Format.durationCompact(1_560))
        #expect(figures[2].value == nil)
        #expect(figures[3].value == nil)
        #expect(figures[4].value == Format.heartrate(86))
    }

    @Test("sans cardio, la dernière colonne reste vide")
    func nomonitorNoHeartRate() {
        let figures = ActivityCard.figures(for: makeActivity(heartrate: nil))
        #expect(figures[4].value == nil)
    }

    @Test("l'allure se lit dans l'unité du sport")
    func paceReadsBySport() {
        // La même règle que partout : `Format.speed` décide, pas une seconde.
        let swim = makeActivity(sport: .swim, distance: 1_000, movingTime: 1_500)
        #expect(ActivityCard.figures(for: swim)[3].value?.contains("/100 m") == true)
        let ride = makeActivity(sport: .ride, distance: 32_400, movingTime: 7_200)
        #expect(ActivityCard.figures(for: ride)[3].value?.contains("km/h") == true)
    }

    @Test("une sortie notable se compte en temps ou en distance")
    func notableCountsTimeOrDistance() {
        // 48 minutes de footing : la sortie ordinaire d'une semaine.
        #expect(!ActivityCard.isNotable(makeActivity()))
        // Deux heures de vélo tranquille.
        #expect(
            ActivityCard.isNotable(
                makeActivity(sport: .ride, distance: 15_000, movingTime: 7_200)
            )
        )
        // 25 km de trail, même s'ils allaient vite.
        #expect(
            ActivityCard.isNotable(
                makeActivity(sport: .trailRun, distance: 25_000, movingTime: 5_000)
            )
        )
    }

    @Test("la graisse va au premier chiffre écrit, pas à la première colonne")
    func theleadingFigureIsTheFirstWritten() {
        let trail = makeActivity(sport: .trailRun, distance: 25_700, movingTime: 10_920)
        #expect(ActivityCard.figures(for: trail)[0].isLeading)

        // Une longue séance en salle n'a pas de distance : la graisse tombe
        // sur sa durée, la première chose qu'elle ait à dire.
        let session = makeActivity(
            sport: .workout, distance: 0, movingTime: 6_000, elevation: 0
        )
        let figures = ActivityCard.figures(for: session)
        #expect(!figures[0].isLeading)
        #expect(figures[1].isLeading)
    }

    @Test("une sortie ordinaire ne met la graisse nulle part")
    func anordinaryOutingIsNotEmphasised() {
        #expect(ActivityCard.figures(for: makeActivity()).allSatisfy { !$0.isLeading })
    }
}
```

- [ ] **Étape 2 : les lancer et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/ActivityCardFiguresTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: type 'ActivityCard' has no member 'figures'`.

- [ ] **Étape 3 : écrire la règle**

À ajouter dans `ActivityCard.swift`, en extension sous le type :

```swift
extension ActivityCard {
    /// One column of the figures row. `nil` where the activity has no such
    /// measurement — an empty column, never a zero: a gym session has no
    /// distance, which is not the same as having a distance of zero.
    struct Figure: Equatable {
        var value: String?
        /// True on the first figure actually written, and only on a notable
        /// outing. See `isNotable`.
        var isLeading = false
    }

    /// What makes an outing stand out in a list of twenty.
    ///
    /// Two thresholds and not one, because one sport is not measured like
    /// another: three hours of cycling and 25 km of trail are both an outing
    /// one remembers, an hour of jogging is not. Written side by side so
    /// moving the line takes a second.
    static let notableMovingTime = 90 * 60
    static let notableDistance: Double = 20_000

    static func isNotable(_ activity: Activity) -> Bool {
        activity.movingTime >= notableMovingTime
            || activity.distance >= notableDistance
    }

    /// The five columns, always in the same order, so two neighbouring rows
    /// line up whatever they carry.
    static func figures(for activity: Activity) -> [Figure] {
        var values: [String?] = [
            activity.distance > 0 ? Format.distance(activity.distance) : nil,
            // The one measurement an activity always has.
            Format.durationCompact(activity.movingTime),
            activity.totalElevationGain > 0
                ? Format.elevation(activity.totalElevationGain) : nil,
            activity.averageSpeed > 0
                ? Format.speed(activity.averageSpeed, sport: activity.sportType)
                : nil,
            activity.averageHeartrate.map(Format.heartrate),
        ]
        // `Format.heartrate` answers with a dash for the zero Strava sends on
        // some manual entries; here that means the column is empty.
        if values[4] == "—" { values[4] = nil }

        var figures = values.map { Figure(value: $0) }
        if isNotable(activity),
           let first = figures.firstIndex(where: { $0.value != nil }) {
            figures[first].isLeading = true
        }
        return figures
    }
}
```

- [ ] **Étape 4 : les lancer et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/ActivityCardFiguresTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : `Test run with 7 tests in 1 suite passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Cairn/Features/ActivityList/ActivityCard.swift Tests/ActivityCardsTests.swift
git commit -m "refactor(activités): les chiffres d'une fiche sortent de la vue"
```

---

### Tâche 2 : la fiche les dessine

**Fichiers :**
- Modifier : `Cairn/Features/ActivityList/ActivityCard.swift`

**Interfaces consommées :** `ActivityCard.figures(for:)` (tâche 1).

- [ ] **Étape 1 : remplacer la colonne de blocs**

Les cinq propriétés `distanceBlock`, `durationBlock`, `elevationBlock`,
`heartrateBlock` et la fonction `block(_:_:)` disparaissent. `figures` devient :

```swift
    /// The figures, one line, no labels.
    ///
    /// The labels went because every value already carries its unit — "9,0 km"
    /// under a caption reading "Distance" said the same thing twice, twenty
    /// times down a list, and cost half the height of the card. The eye now
    /// runs down a column of figures instead of re-reading four words.
    private var figures: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.figures(for: activity).enumerated()), id: \.offset) {
                _, figure in
                Text(figure.value ?? "")
                    // Emphasis by weight alone: on twenty rows it is enough to
                    // bring out the month's three long outings, where a larger
                    // body would break the alignment of the columns and shout.
                    .font(
                        .subheadline
                            .weight(figure.isLeading ? .semibold : .regular)
                            .monospacedDigit()
                    )
                    .lineLimit(1)
                    // Rather than truncating: a number cut short reads as
                    // another number, where a slightly smaller one reads as
                    // itself.
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.columnWidth, alignment: .leading)
            }
        }
    }

    /// Five columns where there were four, and no labels under them: each one
    /// gives up a little width, and the name gains what is left over.
    private static let columnWidth: CGFloat = 62
```

Le commentaire de `figures` qui parlait de « value above label » et de blocs
est remplacé par celui ci-dessus. Le reste de la vue — vignette, nom, date,
marqueurs, hauteur — ne bouge pas.

- [ ] **Étape 2 : compiler et lancer toute la suite**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : 762 tests, tous verts.

- [ ] **Étape 3 : commiter**

```bash
git add Cairn/Features/ActivityList/ActivityCard.swift
git commit -m "style(activités): la fiche perd ses libellés et gagne son allure"
```

- [ ] **Étape 4 : le vérifier à l'écran**

Ne pas faire soi-même : le propriétaire du dépôt s'en charge.

```bash
xcodebuild build -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build && open build/Build/Products/Debug/Cairn.app
```

À regarder : les cinq colonnes s'alignent d'une ligne à l'autre, une séance en
salle laisse ses colonnes vides sans décaler ses voisines, et la graisse tombe
sur les trails sans que la liste devienne bruyante.
