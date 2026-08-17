# Tranche 2 — les notes du journal rejoignent la base

> **Pour les agents :** SOUS-SKILL REQUISE : utiliser
> `superpowers:subagent-driven-development` (recommandé) ou
> `superpowers:executing-plans` pour dérouler ce plan tâche par tâche. Les
> étapes sont en cases à cocher (`- [ ]`).

**But :** les notes du journal quittent le dossier Markdown pour SwiftData, sans
qu'un caractère de texte ni un octet d'image ne se perde.

**Architecture :** l'essentiel est du **retrait**. La moitié des 2 921 lignes du
journal n'existe que parce qu'un second écrivain — Obsidian — partage le
dossier. Ce qui reste est petit : une note par jour, du texte, des étiquettes.
Les octets des images sont matérialisés dans un cache dérivé pour que tout
l'aval continue de travailler sur des URL.

**Pile :** Swift 6.0, SwiftData, Swift Testing. **Aucune dépendance SPM.**

**Spécification :** `docs/specs/2026-08-17-journal-en-base-design.md`

## Contraintes globales

Elles s'appliquent à **toutes** les tâches.

- **Le dossier de l'utilisateur n'est jamais modifié ni supprimé.** Cairn le lit
  une fois et n'y écrit plus jamais rien. C'est ce qui rend une reprise
  automatique acceptable.
- **Le texte des notes ne change pas d'un caractère**, et les octets des images
  pas davantage. Ni reformatage, ni réencodage, ni réécriture de lien.
- **Aucune dépendance SPM.** `project.yml` ne gagne pas de bloc `packages:`.
- **Migrations additives seulement.** Propriétés nouvelles avec valeur par
  défaut ou optionnelles ; jamais de type modifié, jamais de contrainte
  d'unicité ajoutée. Voir l'avertissement en tête de `Cairn/Model/Activity.swift`.
- **Toute nouvelle propriété `uuid` à valeur par défaut doit être réparée par
  `StoreMaintenance`.** Un défaut SwiftData est une valeur *unique* appliquée à
  toutes les lignes existantes — c'est mesuré, et c'est écrit en tête de
  `Cairn/Model/StoreMaintenance.swift`.
- **Identifiants et commentaires de code en anglais, textes affichés et
  documentation en français.** Noms de tests en français, comme le reste de la
  suite.
- **Swift Testing**, jamais XCTest. **Concurrence stricte Swift 6.**
- **`xcodegen generate` après tout ajout ou suppression de fichier source.**
- **Aucun test ne touche au vrai dossier de l'utilisateur, à son vrai magasin,
  ni à `UserDefaults.standard`.** Suites jetables supprimées en `defer` ; voir
  `Tests/JournalStoreTests.swift` pour la convention en vigueur.
- Build et tests :
  ```bash
  xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
  ```
  Point de départ : **895 tests, 132 suites, ~7,5 s, verte.**
- **L'arbre doit compiler et la suite rester verte à la fin de chaque tâche.**
  L'ordre des tâches est choisi pour ça : il n'existe aucun moment où le projet
  est cassé « en attendant la tâche suivante ».

## Structure des fichiers

| Fichier | Sort |
|---|---|
| `Cairn/Features/Journal/JournalNote.swift` | la structure devient `JournalFileNote` — ce qu'un fichier dit à un instant |
| `Cairn/Model/JournalNote.swift` | **créé** — le `@Model`, ce que la base tient |
| `Cairn/Model/JournalAttachment.swift` | **créé** — le `@Model` des octets |
| `Cairn/Features/Journal/JournalAttachment.swift` | renommé `JournalAttachmentRules.swift` — nommage, lien, plafond de 2 048 px |
| `Cairn/Features/Journal/JournalAttachmentCache.swift` | **créé** — matérialise les octets sur disque |
| `Cairn/Features/Journal/JournalImport.swift` | **créé** — la reprise, une fois |
| `Cairn/Features/Journal/JournalMarkdownExport.swift` | **créé** — l'export |
| `Cairn/Features/Journal/JournalStore.swift` | réécrit sur SwiftData (623 lignes → nettement moins) |
| `Cairn/Features/Journal/JournalFolder.swift` | réduit à sa moitié lecture |
| `Cairn/Features/Journal/JournalReconciliation.swift` | **supprimé** |
| `Cairn/Model/StoreMaintenance.swift` | appelle la reprise |
| `Cairn/Model/ModelContainer+App.swift` | schéma 18 → 20 types |
| `Cairn/App/RootView.swift` | 34 points d'appel à `app.journal.` |
| `Cairn/App/AppEnvironment.swift` | le magasin prend un `ModelContainer` |
| `Cairn/Features/Settings/JournalSettingsView.swift` | le choix du dossier disparaît |
| `Cairn/Backup/BackupService.swift` | écrit l'export Markdown |
| `README.md` | trois passages |

---

### Tâche 1 : Libérer le nom `JournalNote`

Purement mécanique, et c'est ce qui permet à tout le reste de compiler à chaque
étape. La structure actuelle décrit ce qu'un **fichier** dit ; son propre
commentaire le dit déjà (« A value, not a model: the file is the truth, and this
is what one file says at one moment »). Elle prend donc le nom qui lui va, et
libère `JournalNote` pour le modèle.

**Fichiers :**
- Renommer : `Cairn/Features/Journal/JournalNote.swift` → `JournalFileNote.swift`
- Modifier : tout ce qui référence le type — `JournalFolder.swift`,
  `JournalStore.swift`, `JournalListView.swift`, `JournalDetailView.swift`,
  `JournalDay.swift`, `RootView.swift`, et les tests correspondants
- Renommer : `Tests/JournalNoteTests.swift` → `Tests/JournalFileNoteTests.swift`

**Interfaces :**
- Produit : `struct JournalFileNote: Identifiable, Equatable, Sendable` avec
  `date: DateKey`, `text: String`, `isReadable: Bool`, `tags: Set<JournalTag>`,
  `id: DateKey`, `isEmpty: Bool`, et l'initialiseur
  `init(date:text:isReadable:)`. **Aucun membre ne change** — seul le nom du
  type bouge.

- [ ] **Étape 1 : Recenser les usages**

```bash
grep -rn '\bJournalNote\b' Cairn Tests --include='*.swift' | wc -l
grep -rln '\bJournalNote\b' Cairn Tests --include='*.swift'
```

Note le compte : tu dois le retrouver à zéro après le renommage.

- [ ] **Étape 2 : Renommer**

Renomme le fichier, le type, et tous les usages. Le mot est distinctif, donc un
remplacement mot entier suffit — mais vérifie qu'aucun commentaire ne parle
d'autre chose sous ce nom.

```bash
git mv Cairn/Features/Journal/JournalNote.swift Cairn/Features/Journal/JournalFileNote.swift
git mv Tests/JournalNoteTests.swift Tests/JournalFileNoteTests.swift
```

Puis, dans chaque fichier concerné, `JournalNote` → `JournalFileNote`.
Renomme aussi la suite de tests (`@Suite("JournalNote")` → `"JournalFileNote"`)
et le nom de la structure de tests.

Adapte le commentaire de tête pour qu'il dise ce que le type est désormais : ce
qu'un fichier du dossier dit à un instant, par opposition à ce que la base
tient.

- [ ] **Étape 3 : Vérifier qu'il ne reste rien**

```bash
grep -rn '\bJournalNote\b' Cairn Tests --include='*.swift'
```

Attendu : **aucune ligne**.

- [ ] **Étape 4 : Lancer la suite complète**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

Attendu : SUCCÈS, 895 tests. Un renommage pur ne change aucun comportement ; si
un test tombe, c'est que le renommage a mordu ailleurs.

- [ ] **Étape 5 : Commit**

```bash
git add -A
git commit -m "refactor(journal): la structure lue sur disque devient JournalFileNote"
```

---

### Tâche 2 : Les deux modèles

**Fichiers :**
- Créer : `Cairn/Model/JournalNote.swift`
- Créer : `Cairn/Model/JournalAttachment.swift`
- Renommer : `Cairn/Features/Journal/JournalAttachment.swift` →
  `JournalAttachmentRules.swift` (et le type avec)
- Renommer : `Tests/JournalAttachmentTests.swift` →
  `Tests/JournalAttachmentRulesTests.swift`
- Modifier : `Cairn/Model/ModelContainer+App.swift` (schéma 18 → 20)
- Modifier : `Cairn/Model/StoreMaintenance.swift` (réparation des identités)
- Créer : `Tests/JournalModelTests.swift`

**Interfaces :**
- Consomme : `DateKey`, `JournalTag`, `JournalTagScanner` (existants).
- Produit :
  ```swift
  @Model final class JournalNote {
      var uuid: String
      var dateKeyRaw: String
      var text: String
      var tagsRaw: [String]
      var updatedAt: Date
      init(dateKey: DateKey, text: String)
      var dateKey: DateKey? { get }
      var tags: Set<JournalTag> { get }
      var isEmpty: Bool { get }
      func setText(_ text: String)      // met `tagsRaw` et `updatedAt` à jour
  }

  @Model final class JournalAttachment {
      var uuid: String
      var fileName: String
      var data: Data?                   // @Attribute(.externalStorage)
      var addedAt: Date
      init(fileName: String, data: Data)
  }
  ```
  et `enum JournalAttachmentRules` portant `folderName`, `allowedExtensions`,
  `maxPixels`, `fileName(for:extension:taken:)`, `link(to:)`,
  `appending(_:to:)` — **exactement les membres actuels de
  `JournalAttachment`**, sans changement de signature.

- [ ] **Étape 1 : Écrire les tests qui échouent**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Modèles du journal")
struct JournalModelTests {
    /// Les étiquettes étaient dérivées à la construction, ce qu'un `@Model` ne
    /// permet pas. Elles deviennent une colonne — donc quelque chose doit la
    /// tenir à jour, et c'est `setText`.
    @Test func ecrireUnTexteMetLesEtiquettesAJour() {
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "")
        #expect(note.tags.isEmpty)

        note.setText("Sortie longue #course avec #cotes")

        #expect(note.tags.count == 2)
        #expect(note.tagsRaw.sorted() == ["cotes", "course"])
    }

    /// Un texte sans étiquette en vide la colonne, plutôt que d'y laisser
    /// celles du texte précédent.
    @Test func retirerUneEtiquetteLaRetireDeLaColonne() {
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "#course")
        note.setText("plus rien")
        #expect(note.tagsRaw.isEmpty)
    }

    /// La règle qui existait sur la structure et qui reste vraie : une note
    /// blanche est une note vide.
    @Test func uneNoteBlancheEstVide() {
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "  \n\n ")
        #expect(note.isEmpty)
    }

    /// Écrite puis relue, une note garde son identité et son texte.
    @Test func uneNoteSurvitAuDisque() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "bonjour")
        let expected = note.uuid
        context.insert(note)
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<JournalNote>())
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.uuid == expected)
        #expect(reloaded.first?.text == "bonjour")
    }

    /// Les octets d'une pièce jointe vivent en stockage externe, comme les
    /// photos de sorties, et son nom de fichier est sa clé.
    @Test func unePieceJointeGardeSesOctetsEtSonNom() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let bytes = Data(repeating: 0xAB, count: 512)
        context.insert(JournalAttachment(fileName: "2026-08-17-1.jpg", data: bytes))
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<JournalAttachment>())
        #expect(reloaded.first?.fileName == "2026-08-17-1.jpg")
        #expect(reloaded.first?.data == bytes)
    }
}
```

Vérifie la signature réelle de `JournalTagScanner.tags(in:)` et la forme de
`JournalTag` dans `Cairn/Features/Journal/JournalTag.swift` avant d'écrire
`tagsRaw` — le test suppose que l'étiquette se réduit à une chaîne sans le
croisillon. Si ce n'est pas le cas, adapte le test au type réel plutôt que
l'inverse.

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalModelTests
```

Attendu : ÉCHEC à la compilation, `cannot find 'JournalNote' in scope` (le nom
est libre depuis la tâche 1).

- [ ] **Étape 3 : Écrire les deux modèles**

`Cairn/Model/JournalNote.swift` et `Cairn/Model/JournalAttachment.swift`, sur le
patron des modèles voisins. `JournalAttachment.data` porte
`@Attribute(.externalStorage)`, comme `ActivityPhoto.data`. Aucune macro
`#Index` ni `#Unique` : le dépôt paie déjà cher toute contrainte ajoutée.

`setText(_:)` est le seul chemin d'écriture du texte, et il pose `tagsRaw` et
`updatedAt` ensemble — un texte écrit sans ses étiquettes serait une note qui
disparaît des filtres.

- [ ] **Étape 4 : Renommer `JournalAttachment` en `JournalAttachmentRules`**

```bash
git mv Cairn/Features/Journal/JournalAttachment.swift Cairn/Features/Journal/JournalAttachmentRules.swift
git mv Tests/JournalAttachmentTests.swift Tests/JournalAttachmentRulesTests.swift
```

Renomme le type et ses usages (`JournalFolder.swift` s'en sert pour
`folderName`). **Aucune signature ne change** : ce type ne touche à aucun
disque, il nomme et compose du Markdown, et c'est exactement ce qui reste vrai.

- [ ] **Étape 5 : Déclarer les modèles au schéma et les réparer**

Ajoute `JournalNote.self` et `JournalAttachment.self` au tableau
`AppModelContainer.schema` — il passe de dix-huit à vingt types. Un modèle
nouveau est une migration légère, comme le note déjà le commentaire du bloc
nutrition.

Puis **ajoute les deux à la réparation d'identités de `StoreMaintenance.run`**.
La contrainte globale l'exige : un défaut SwiftData est une valeur unique
appliquée à toutes les lignes existantes. Ici les tables naissent vides, donc la
réparation ne trouvera rien — mais un magasin restauré depuis une sauvegarde
future en aurait besoin, et l'oubli ne se verrait que là.

Le test de `StoreMaintenance` compare la liste réparée à
`MirrorEngine.bootstrapOrder`. Ces deux modèles **ne traversent pas** le miroir,
donc cette comparaison ne vaut plus telle quelle : adapte-la pour qu'elle
distingue « les seize qui traversent » de « tout ce qui porte un uuid », plutôt
que de retirer la garantie.

- [ ] **Étape 6 : Lancer la suite complète**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

Attendu : SUCCÈS. Une migration de schéma se vérifie sur toute la suite.

- [ ] **Étape 7 : Commit**

```bash
git add -A
git commit -m "feat(journal): la note et sa pièce jointe deviennent des modèles"
```

---

### Tâche 3 : Le cache des pièces jointes

C'est lui qui rend vraie l'affirmation « les vues ne bougent pas ».
`attachmentsBase: URL?` descend de `RootView` jusqu'à `MarkdownText` et
`JournalThumbnails`, qui résolvent `pieces-jointes/x.jpg` contre un dossier
réel. Des octets en base n'ont pas d'URL : on leur en fabrique une.

**Fichiers :**
- Créer : `Cairn/Features/Journal/JournalAttachmentCache.swift`
- Créer : `Tests/JournalAttachmentCacheTests.swift`

**Interfaces :**
- Consomme : `JournalAttachment` (tâche 2), `AppModelContainer.directory`.
- Produit :
  ```swift
  enum JournalAttachmentCache {
      /// `<Application Support>/Cairn/cache/journal-attachments/`
      static var directory: URL { get }
      /// Writes the bytes under `fileName` if absent. Returns its URL.
      @discardableResult
      static func materialise(_ attachment: JournalAttachment) throws -> URL?
      /// Materialises everything the store holds that is missing on disk.
      @discardableResult
      static func rebuild(_ context: ModelContext) throws -> Int
  }
  ```

- [ ] **Étape 1 : Écrire les tests qui échouent**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Cache des pièces jointes")
struct JournalAttachmentCacheTests {
    /// Le cache reconstruit ce qui manque, et rend le compte de ce qu'il a
    /// écrit — c'est ce qui le rend testable et son idempotence vérifiable.
    @Test func laReconstructionEcritCeQuiManque() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(
            JournalAttachment(
                fileName: "2026-08-17-1.jpg", data: Data(repeating: 0x01, count: 8)
            )
        )
        try context.save()

        let written = try JournalAttachmentCache.rebuild(context)
        #expect(written == 1)

        let url = JournalAttachmentCache.directory.appending(path: "2026-08-17-1.jpg")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == Data(repeating: 0x01, count: 8))
    }

    /// Relancée, elle n'écrit rien : le fichier est déjà là. Sans quoi chaque
    /// lancement réécrirait toutes les images du journal.
    @Test func laReconstructionEstIdempotente() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(
            JournalAttachment(
                fileName: "2026-08-17-2.jpg", data: Data(repeating: 0x02, count: 8)
            )
        )
        try context.save()

        _ = try JournalAttachmentCache.rebuild(context)
        #expect(try JournalAttachmentCache.rebuild(context) == 0)
    }

    /// Une pièce jointe sans octets ne produit aucun fichier — et surtout
    /// aucun fichier vide, qui se lirait comme une image corrompue.
    @Test func unePieceSansOctetsNeProduitAucunFichier() throws {
        let attachment = JournalAttachment(fileName: "vide.jpg", data: Data())
        attachment.data = nil
        #expect(try JournalAttachmentCache.materialise(attachment) == nil)
    }
}
```

**Attention :** ces tests écrivent dans le vrai dossier de cache de
l'application. Rends `directory` injectable, ou fais écrire les tests dans un
dossier jetable qu'ils suppriment en `defer` — la contrainte globale l'exige, et
`Tests/JournalStoreTests.swift` montre la convention du dépôt pour ça. Adapte
les tests ci-dessus en conséquence plutôt que de les recopier tels quels.

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalAttachmentCacheTests
```

Attendu : ÉCHEC, `cannot find 'JournalAttachmentCache' in scope`.

- [ ] **Étape 3 : Écrire le cache**

Le dossier est `AppModelContainer.directory.appending(path: "cache/journal-attachments")`,
créé au besoin. `materialise` n'écrit que si le fichier manque : les octets ne
changent jamais après coup, le nom de fichier étant la clé.

Documente qu'il est **dérivé et reconstructible**, au même titre que `off.db` :
le supprimer ne perd rien.

- [ ] **Étape 4 : Lancer les tests et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalAttachmentCacheTests
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Commit**

```bash
xcodegen generate
git add -A
git commit -m "feat(journal): un cache dérivé donne une URL aux pièces jointes"
```

---

### Tâche 4 : La reprise

**Fichiers :**
- Créer : `Cairn/Features/Journal/JournalImport.swift`
- Créer : `Tests/JournalImportTests.swift`

**Interfaces :**
- Consomme : `JournalFolder.notes(in:)` et `JournalAttachmentRules.folderName`
  (existants), `JournalNote` et `JournalAttachment` (tâche 2).
- Produit :
  ```swift
  enum JournalImport {
      struct Outcome: Equatable {
          var notes: Int
          var attachments: Int
          /// File names that could not be decoded, imported byte-for-byte anyway.
          var unreadable: [String]
      }
      /// Runs once. Returns nil when it did nothing because it had already run.
      static func runIfNeeded(
          _ context: ModelContext, folderPath: String?, defaults: UserDefaults
      ) throws -> Outcome?
  }
  ```

- [ ] **Étape 1 : Écrire les tests qui échouent**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Reprise du journal")
struct JournalImportTests {
    /// Un dossier jetable, avec ses notes et ses images.
    private func makeFolder(
        notes: [String: String], attachments: [String: Data] = [:]
    ) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, text) in notes {
            try text.write(
                to: url.appending(path: "\(name).md"), atomically: true, encoding: .utf8
            )
        }
        if !attachments.isEmpty {
            let sub = url.appending(path: JournalAttachmentRules.folderName)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            for (name, bytes) in attachments {
                try bytes.write(to: sub.appending(path: name))
            }
        }
        return url
    }

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "journal-import-tests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func discard(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    /// Le cas nominal : les notes et les images entrent en base.
    @Test func laRepriseLitLesNotesEtLesImages() throws {
        let folder = try makeFolder(
            notes: ["2026-08-16": "hier", "2026-08-17": "aujourd'hui #course"],
            attachments: ["2026-08-17-1.jpg": Data(repeating: 0x7F, count: 16)]
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let outcome = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )

        #expect(outcome?.notes == 2)
        #expect(outcome?.attachments == 1)
        #expect(try context.fetch(FetchDescriptor<JournalNote>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<JournalAttachment>()).count == 1)
    }

    /// Relancée, elle ne fait rien du tout — pas « rien de nouveau », rien.
    /// C'est le marqueur qui l'arrête, pas un dédoublonnage.
    @Test func laRepriseNeSeFaitQuUneFois() throws {
        let folder = try makeFolder(notes: ["2026-08-17": "une note"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        _ = try JournalImport.runIfNeeded(context, folderPath: folder.path, defaults: defaults)
        let second = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )

        #expect(second == nil)
        #expect(try context.fetch(FetchDescriptor<JournalNote>()).count == 1)
    }

    /// Un dossier introuvable ne se marque PAS fait : un disque débranché ou
    /// un iCloud pas encore descendu perdrait tout le journal.
    @Test func unDossierIntrouvableNeSeMarquePasFait() throws {
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())
        let absent = "/tmp/journal-qui-nexiste-pas-\(UUID().uuidString)"

        _ = try? JournalImport.runIfNeeded(context, folderPath: absent, defaults: defaults)

        // Le dossier revient : la reprise doit encore avoir lieu.
        let folder = try makeFolder(notes: ["2026-08-17": "retrouvée"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let outcome = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )
        #expect(outcome?.notes == 1)
    }

    /// Aucun dossier n'a jamais été désigné : marqueur posé tout de suite,
    /// rien à faire, et jamais rien à refaire.
    @Test func sansDossierLaRepriseSeMarqueFaiteImmediatement() throws {
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let first = try JournalImport.runIfNeeded(context, folderPath: nil, defaults: defaults)
        #expect(first?.notes == 0)

        let second = try JournalImport.runIfNeeded(context, folderPath: nil, defaults: defaults)
        #expect(second == nil)
    }

    /// Un fichier illisible est repris quand même, ses octets conservés, et
    /// signalé. Boucler dessus indéfiniment serait pire.
    @Test func unFichierIllisibleEstRepisEtSignale() throws {
        let folder = try makeFolder(notes: ["2026-08-16": "lisible"])
        defer { try? FileManager.default.removeItem(at: folder) }
        // Des octets qui ne sont pas de l'UTF-8 valide.
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(
            to: folder.appending(path: "2026-08-17.md")
        )
        let (defaults, suiteName) = freshDefaults()
        defer { discard(suiteName) }
        let context = ModelContext(try AppModelContainer.inMemory())

        let outcome = try JournalImport.runIfNeeded(
            context, folderPath: folder.path, defaults: defaults
        )

        #expect(outcome?.unreadable == ["2026-08-17.md"])
        #expect(outcome?.notes == 2)
    }
}
```

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalImportTests
```

Attendu : ÉCHEC, `cannot find 'JournalImport' in scope`.

- [ ] **Étape 3 : Écrire la reprise**

Le marqueur est une clé de `UserDefaults` explicite — jamais déduite de « la
base est vide », un journal sans note étant un état légitime. Range-la à côté
des autres, dans `JournalSettings`.

**Toutes** les images de `pieces-jointes/` sont reprises, y compris celles
qu'aucune note ne cite : une image orpheline ne coûte rien, une image manquante
casse une note.

`JournalFolder.notes(in:)` rend déjà un `JournalFileNote` par fichier, avec
`isReadable` à faux quand le décodage échoue. Pour ces fichiers-là, relis les
octets bruts et conserve-les tels quels plutôt que d'écrire une note vide.

Le dossier n'est **jamais** modifié : pas de déplacement, pas de suppression,
pas même une écriture de marqueur à l'intérieur.

- [ ] **Étape 4 : Lancer les tests et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalImportTests
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Commit**

```bash
xcodegen generate
git add -A
git commit -m "feat(journal): la reprise lit le dossier une fois, sans jamais y écrire"
```

---

### Tâche 5 : L'export Markdown et l'aller-retour

**C'est la tâche qui porte la garantie de toute la tranche.** Le test
d'aller-retour est ce qui dit que rien ne se perd.

**Fichiers :**
- Créer : `Cairn/Features/Journal/JournalMarkdownExport.swift`
- Créer : `Tests/JournalMarkdownExportTests.swift`

**Interfaces :**
- Consomme : `JournalNote`, `JournalAttachment` (tâche 2),
  `JournalAttachmentRules.folderName`, `JournalFolder.fileName(for:)`,
  `JournalImport` (tâche 4).
- Produit :
  ```swift
  enum JournalMarkdownExport {
      /// Writes one `AAAA-MM-JJ.md` per note plus `pieces-jointes/` into
      /// `destination`, which it creates. Returns how many notes it wrote.
      @discardableResult
      static func write(_ context: ModelContext, to destination: URL) throws -> Int
  }
  ```

- [ ] **Étape 1 : Écrire le test d'aller-retour, d'abord**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Export Markdown du journal")
struct JournalMarkdownExportTests {
    /// LA garantie de la tranche : un dossier repris puis réexporté est le
    /// même dossier. « Le même » veut dire : mêmes noms de fichiers, textes
    /// identiques au caractère près, images identiques aux octets près.
    /// Ni reformatage, ni réencodage, ni réécriture de lien.
    @Test func unDossierRepisPuisExporteEstLeMeme() throws {
        let source = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-aller-\(UUID().uuidString)")
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-retour-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        // Un texte qui piège un exportateur trop zélé : avant-propos YAML,
        // lignes vides, accents, et un lien d'image à ne pas réécrire.
        let texts = [
            "2026-08-16": "---\ntitre: hier\n---\n\nUne sortie très longue.\n\n#course\n",
            "2026-08-17": "Aujourd'hui.\n\n![](pieces-jointes/2026-08-17-1.jpg)\n",
        ]
        for (name, text) in texts {
            try text.write(
                to: source.appending(path: "\(name).md"), atomically: true, encoding: .utf8
            )
        }
        let attachmentsFolder = source.appending(path: JournalAttachmentRules.folderName)
        try FileManager.default.createDirectory(
            at: attachmentsFolder, withIntermediateDirectories: true
        )
        let bytes = Data((0..<256).map { UInt8($0 % 256) })
        try bytes.write(to: attachmentsFolder.appending(path: "2026-08-17-1.jpg"))

        let defaults = UserDefaults(suiteName: "journal-roundtrip-\(UUID().uuidString)")!
        let context = ModelContext(try AppModelContainer.inMemory())
        _ = try JournalImport.runIfNeeded(
            context, folderPath: source.path, defaults: defaults
        )

        try JournalMarkdownExport.write(context, to: destination)

        // Les mêmes noms de notes.
        let exported = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        #expect(Set(exported.filter { $0.hasSuffix(".md") })
                    == Set(texts.keys.map { "\($0).md" }))

        // Les mêmes textes, au caractère près.
        for (name, text) in texts {
            let written = try String(
                contentsOf: destination.appending(path: "\(name).md"), encoding: .utf8
            )
            #expect(written == text)
        }

        // Les mêmes octets d'image.
        let exportedImage = destination
            .appending(path: JournalAttachmentRules.folderName)
            .appending(path: "2026-08-17-1.jpg")
        #expect(try Data(contentsOf: exportedImage) == bytes)
    }

    /// Un journal vide produit un dossier vide, pas une erreur : la sauvegarde
    /// tourne aussi sur une installation qui n'a jamais pris de note.
    @Test func unJournalVideProduitUnDossierVide() throws {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-vide-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        let context = ModelContext(try AppModelContainer.inMemory())

        #expect(try JournalMarkdownExport.write(context, to: destination) == 0)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }
}
```

- [ ] **Étape 2 : Lancer le test et le voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalMarkdownExportTests
```

Attendu : ÉCHEC, `cannot find 'JournalMarkdownExport' in scope`.

- [ ] **Étape 3 : Écrire l'export**

Un fichier `AAAA-MM-JJ.md` par note, écrit en UTF-8 sans rien ajouter ni
retirer — pas de saut de ligne final « pour faire propre », pas de
normalisation. Le dossier `pieces-jointes/` n'est créé que s'il y a des pièces
jointes.

Si le test d'aller-retour échoue sur un caractère, **c'est l'export qui a tort**,
jamais le test : le texte que l'utilisateur a écrit est ce qui doit ressortir.

- [ ] **Étape 4 : Lancer le test et le voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalMarkdownExportTests
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Commit**

```bash
xcodegen generate
git add -A
git commit -m "feat(journal): l'export Markdown, et l'aller-retour qui le prouve"
```

---

### Tâche 6 : Le magasin réécrit

La grosse tâche, et elle est surtout faite de suppressions. À aborder avec les
cinq tâches précédentes en place : la reprise, l'export et le cache existent
déjà et sont prouvés.

**Fichiers :**
- Réécrire : `Cairn/Features/Journal/JournalStore.swift`
- Réduire : `Cairn/Features/Journal/JournalFolder.swift` (moitié lecture seule)
- Supprimer : `Cairn/Features/Journal/JournalReconciliation.swift`
- Supprimer : `Tests/JournalReconciliationTests.swift`
- Réécrire : `Tests/JournalStoreTests.swift`
- Réduire : `Tests/JournalFolderTests.swift`
- Modifier : `Cairn/Features/Journal/JournalListView.swift`,
  `JournalDetailView.swift`, `JournalThumbnails.swift` — là où `isReadable`,
  `conflict`, `loadError` et `writeFailure` étaient lus

**Interfaces :**
- Consomme : `JournalNote`, `JournalAttachment`, `JournalAttachmentCache`,
  `JournalAttachmentRules`.
- Produit : `JournalStore` avec `init(container: ModelContainer)` et l'API que
  `RootView` appelle déjà — `notes`, `note(for:)`, `text(for:)`,
  `beginEditing(_:)`, `append(_:for:)`, `update(_:for:)`, `saveNow()`,
  `openToday()`, `open(_:)`, `delete(_:)`, `textRevision`,
  `attachmentsBase: URL`. **Disparaissent :** `choose(_:)`, `folder`,
  `loadError`, `conflict`, `dismissConflict()`, `reloadConflicted()`,
  `reload()`, `pendingWriteFailure`, `writeFailure`, `observe(...)`.

- [ ] **Étape 1 : Réécrire les tests du magasin**

Ouvre `Tests/JournalStoreTests.swift` et trie ses tests un par un selon cette
règle : **un test qui ne mentionne ni fichier, ni dossier, ni conflit, ni échec
d'écriture décrit le journal et doit survivre.** Tous les autres décrivaient le
disque et s'en vont avec lui.

Ce qui survit, réécrit sur le magasin SwiftData : ouvrir aujourd'hui, écrire un
texte et le relire, une note devenue blanche qui disparaît, passer d'une note à
l'autre, `textRevision` qui bouge quand le magasin impose sa copie.

Ce qui s'en va : le surveillant et ses événements, les écritures qui échouent,
le refus de changer de note tant qu'une écriture a échoué, les fichiers
illisibles, la réconciliation, le changement de dossier.

Le montage s'allège d'autant : plus de dossier jetable, plus de préférences
jetables, juste `ModelContext(try AppModelContainer.inMemory())`. Si le fichier
réécrit ne fait pas moins de la moitié de ses 623 lignes actuelles, c'est que
quelque chose du disque a survécu sans raison — cherche-le.

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalStoreTests
```

Attendu : ÉCHEC à la compilation — `JournalStore` ne prend pas encore de
`ModelContainer`.

- [ ] **Étape 3 : Réécrire le magasin**

Le texte vit dans `JournalNote.text`, l'écriture passe par `setText` et
`context.save()`. Une note devenue vide est supprimée, comme aujourd'hui un
fichier vide l'était — la règle est dans `JournalFileNote.isEmpty` et reste
vraie.

Une pièce jointe déposée devient un `JournalAttachment` — les octets réduits à
2 048 px par les règles existantes — puis est matérialisée dans le cache, et le
lien Markdown est ajouté au texte par `JournalAttachmentRules.appending(_:to:)`.

`attachmentsBase` n'est plus optionnel : c'est le dossier de cache, qui existe
toujours. Les vues qui testaient `attachmentsBase == nil` pour désactiver
l'ajout de photo n'ont plus de raison de le faire.

`textRevision` survit, amaigri : l'éditeur doit encore savoir quand la copie du
magasin l'emporte — chargement d'une autre note, suppression — mais plus jamais
parce que le fichier a changé sous ses doigts.

- [ ] **Étape 4 : Supprimer ce qui n'a plus d'objet**

`JournalReconciliation.swift` et son fichier de tests. Le surveillant FSEvents.
Dans `JournalFolder.swift` : `write(_:for:in:)`, `remove(_:in:)`,
`copyAttachment(...)`, `writeAttachment(...)`, `url(for:in:)` — tout ce qui
écrit. **Gardent leur place :** `fileExtension`, `fileName(for:)`,
`date(fromFileName:)`, `notes(in:)`, `attachmentsFolder(in:)`, `reduced(_:)` et
`reduced(at:)`, qui servent encore à la reprise et à la réduction d'image.

Réduis `Tests/JournalFolderTests.swift` en conséquence : ce qui portait sur
l'écriture s'en va, ce qui portait sur le nommage et la lecture reste.

- [ ] **Étape 5 : Lancer la suite complète**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

Attendu : SUCCÈS. Les quatorze fichiers de tests qui ignorent d'où vient le
texte doivent passer **sans avoir été touchés** — c'est la mesure de ce que le
changement de couche ne casse pas.

- [ ] **Étape 6 : Commit**

```bash
git add -A
git commit -m "refactor(journal): le magasin passe sur SwiftData, le dossier s'efface"
```

---

### Tâche 7 : Le branchement

**Fichiers :**
- Modifier : `Cairn/App/AppEnvironment.swift`
- Modifier : `Cairn/App/RootView.swift` (34 points d'appel à `app.journal.`)
- Modifier : `Cairn/App/CairnApp.swift`
- Modifier : `Cairn/Model/StoreMaintenance.swift`
- Modifier : `Cairn/Features/Settings/JournalSettingsView.swift`
- Créer : `Tests/JournalWiringTests.swift`

**Interfaces :**
- Consomme : `JournalStore(container:)` (tâche 6), `JournalImport.runIfNeeded`
  (tâche 4), `JournalAttachmentCache.rebuild` (tâche 3), `JournalNotice`
  (existant).
- Produit : `AppEnvironment.journal` construit avec le conteneur.
- **Change une signature existante :** `StoreMaintenance.run(_ context:
  ModelContext) throws -> Int` devient `run(_ context: ModelContext, defaults:
  UserDefaults = .standard) throws -> Int`. La reprise a besoin de lire le
  chemin du dossier, et un test ne doit jamais toucher aux préférences réelles —
  d'où le paramètre, avec une valeur par défaut pour l'application. Les
  appelants existants (`CairnApp.init`, `StoreMaintenanceTests`) continuent de
  compiler.

- [ ] **Étape 1 : Écrire les tests qui échouent**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Branchement du journal")
@MainActor
struct JournalWiringTests {
    /// La reprise a lieu à la maintenance du magasin, pas au premier affichage
    /// du journal : une note écrite avant qu'on ouvre l'onglet serait sinon
    /// invisible.
    @Test func laMaintenanceDeclencheLaReprise() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "reprise".write(
            to: folder.appending(path: "2026-08-17.md"), atomically: true, encoding: .utf8
        )

        let (defaults, suiteName) = freshJournalDefaults()
        defer { discardJournalDefaults(suiteName) }
        defaults.set(folder.path, forKey: JournalSettings.folderPathKey)

        try StoreMaintenance.run(context, defaults: defaults)

        #expect(try context.fetch(FetchDescriptor<JournalNote>()).count == 1)
    }

    /// Le journal n'attend plus qu'on lui désigne un dossier : il est
    /// utilisable dès la construction de l'environnement.
    @Test func leJournalEstUtilisableSansDossier() throws {
        let container = try AppModelContainer.inMemory()
        let environment = AppEnvironment(container: container)
        let today = environment.journal.openToday()
        environment.journal.update("une note", for: today)
        environment.journal.saveNow()

        #expect(environment.journal.text(for: today) == "une note")
    }
}
```

Écris `freshJournalDefaults()` / `discardJournalDefaults(_:)` sur le patron de
`freshCursor()` / `discard(_:)` de `Tests/MirrorTestSupport.swift`. **Ne renomme
rien dans ce fichier** : le miroir en dépend.

`AppEnvironment.init` porte déjà des paramètres injectables (`store:`,
`mirrorTransport:`, `mirrorCursor:`) ; si tes tests ont besoin d'injecter des
préférences pour le journal, suis le même patron plutôt que d'en inventer un.

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalWiringTests
```

Attendu : ÉCHEC à la compilation.

- [ ] **Étape 3 : Brancher**

`AppEnvironment` construit `JournalStore(container:)`. `StoreMaintenance.run`
appelle `JournalImport.runIfNeeded` puis `JournalAttachmentCache.rebuild` — dans
cet ordre, le cache ne pouvant matérialiser que ce qui est déjà en base.

Dans `RootView`, les 34 points d'appel : `app.journal.folder` disparaît de
partout (`onChange`, le message « choisissez un dossier », `attachmentsBase`),
`pendingWriteFailure` et `dismissConflict()` avec lui, et `choose(url)` avec le
sélecteur de dossier qui l'appelait.

Dans `JournalSettingsView`, la section de choix du dossier s'en va. Si le
fichier n'a plus d'objet, supprime-le et retire son onglet de `SettingsScene`.

`JournalSettings.folderPathKey` **reste** : la reprise le lit encore, une fois,
sur les installations qui l'ont. Ajoute-lui la clé du marqueur de reprise.

**Les fichiers illisibles doivent être signalés**, faute de quoi
`JournalImport.Outcome.unreadable` est calculé pour personne. `JournalNotice`
existe déjà et sert exactement à ça : porte la liste jusqu'à lui, en français,
une fois, à la reprise. Un fichier repris imparfaitement et signalé vaut mieux
qu'un fichier repris imparfaitement en silence — c'est la seule trace qu'aura
l'utilisateur qu'une note mérite un coup d'œil. Lis
`Cairn/Features/Journal/JournalNotice.swift` pour savoir sous quelle forme il
prend ce qu'on lui donne.

- [ ] **Étape 4 : Lancer la suite complète**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Vérifier dans l'application**

Lance l'application. Le journal doit s'ouvrir directement, sans demander de
dossier. Écris une note, ajoute-lui une image par glissée-déposée, relance :
tout doit être là. Ouvre le carnet PDF : l'image doit y figurer.

- [ ] **Étape 6 : Commit**

```bash
git add -A
git commit -m "feat(journal): le journal s'ouvre sans qu'on lui désigne un dossier"
```

---

### Tâche 8 : La sauvegarde et le README

**Fichiers :**
- Modifier : `Cairn/Backup/BackupService.swift`
- Modifier : `README.md`
- Modifier : `Tests/BackupServiceTests.swift` (ou le fichier de tests existant
  de la sauvegarde ; s'il n'y en a pas, créer `Tests/JournalBackupTests.swift`)

**Interfaces :**
- Consomme : `JournalMarkdownExport.write(_:to:)` (tâche 5).

- [ ] **Étape 1 : Écrire le test qui échoue**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Le journal dans la sauvegarde")
struct JournalBackupTests {
    /// La sauvegarde écrit le journal en Markdown à côté de la base, sans quoi
    /// la promesse « vos notes ressortent en Markdown » ne tient que si on y
    /// pense — c'est-à-dire jamais.
    @Test func laSauvegardeEcritLeJournalEnMarkdown() throws {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "sauvegardée")
        context.insert(note)
        try context.save()

        try BackupService.writeJournalMarkdown(context, into: destination, stamp: "2026-08-17-0900")

        let folder = destination.appending(path: "journal-markdown-2026-08-17-0900")
        let text = try String(
            contentsOf: folder.appending(path: "2026-08-17.md"), encoding: .utf8
        )
        #expect(text == "sauvegardée")
    }
}
```

Lis `Cairn/Backup/BackupService.swift` avant d'écrire ce test : il a déjà une
façon de composer ses horodatages (`journal-AAAA-MM-JJ-HHMM.sqlite.gz`) et une
politique de conservation. Reprends-les au lieu d'en inventer, et adapte la
signature ci-dessus à ce que le service expose réellement.

- [ ] **Étape 2 : Lancer le test et le voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalBackupTests
```

Attendu : ÉCHEC, la méthode n'existe pas.

- [ ] **Étape 3 : Écrire l'export dans la sauvegarde**

Un dossier `journal-markdown-AAAA-MM-JJ-HHMM/` à côté du `.sqlite.gz`, soumis à
la **même politique de conservation** que les sauvegardes existantes — sans
quoi les exports s'accumuleraient indéfiniment pendant que les bases tournent.

- [ ] **Étape 4 : Corriger le README**

Trois passages :

1. **« Emplacement des données »** — le paragraphe « Les notes du journal font
   exception : elles vivent dans le dossier que vous avez désigné, et nulle part
   ailleurs. Cairn n'en garde aucune copie — ni ici, ni dans la sauvegarde. »
   devient faux et doit disparaître. Dis ce qui le remplace : les notes sont
   dans la base, donc dans la sauvegarde, **et** exportées en Markdown à côté.
2. **« Journal »** — tout ce qui décrit le coffre, le choix du dossier et la
   compatibilité Obsidian. Explique ce qui a été gagné (les notes entrent dans
   la sauvegarde) et ce qui a été perdu (l'édition depuis Obsidian), sans
   maquiller le second.
3. **« Sauvegarde »** — l'export Markdown rejoint la liste de ce que le dossier
   de sauvegarde contient.

Suis le ton du README : de la prose qui explique le pourquoi, pas des listes à
puces.

- [ ] **Étape 5 : Lancer la suite complète**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

Attendu : SUCCÈS.

- [ ] **Étape 6 : Commit**

```bash
xcodegen generate
git add -A
git commit -m "feat(journal): la sauvegarde emporte les notes en Markdown"
```

---

## Ce que la tranche 2 ne fait pas

À vérifier avant de la déclarer finie — chacun de ces points est délibéré.

- **Aucun réseau, aucun front.** `JournalNote` et `JournalAttachment` ne
  conforment pas `MirrorRow`, aucune table `journal_note` n'est ajoutée à
  `supabase/schema.sql`, et le garde-fou `Tests/MirrorRowSchemaTests.swift`
  reste vert sans être touché.
- **Aucun pont vers Obsidian.** Le dossier est lu une fois puis oublié. Il n'y a
  plus de saisie mobile jusqu'à la tranche 4, et c'est assumé.
- **Le dossier de l'utilisateur n'est pas supprimé.** Ses fichiers restent où
  ils sont, intacts.
