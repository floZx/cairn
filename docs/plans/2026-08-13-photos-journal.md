# Des photos dans les notes du journal — plan d'implémentation

> **Pour un agent :** SOUS-COMPÉTENCE REQUISE — `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour dérouler ce plan tâche par
> tâche. Les étapes sont des cases à cocher (`- [ ]`).

**But :** poser une photo dans une note du journal — glissée-déposée, collée ou
choisie — et la voir dans Cairn, dans Obsidian et dans le carnet PDF.

**Architecture :** la règle (quel nom, quelle ligne) est une fonction pure ;
`JournalFolder` reste le seul à toucher au disque ; le parseur gagne un bloc
image que trois rendus savent dessiner — l'écran, et le HTML du carnet.

**Pile :** Swift 6, SwiftUI, SwiftData, AppKit, Swift Testing.

**Spec :** `docs/specs/2026-08-13-photos-journal-design.md`.

## Contraintes globales

- **Le coffre reste lisible par une autre application** : un fichier image à
  côté des notes, un lien Markdown standard `![](pieces-jointes/…)`, rien de
  caché ailleurs.
- **Le dossier des pièces jointes s'appelle `pieces-jointes`.**
- **Le nom d'un fichier est `AAAA-MM-JJ-N.ext`** : le jour de la note, puis le
  premier numéro libre. Extension d'origine, en minuscules.
- **La ligne s'ajoute à la fin de la note**, jamais au curseur.
- **Formats acceptés : JPEG, PNG, HEIC.** Tout autre fichier est refusé avec un
  message qui le nomme.
- **Une image introuvable affiche son nom**, jamais un cadre vide.
- **Commentaires de code en anglais**, noms de tests en français.
- **Après tout ajout de fichier source : `xcodegen generate`.**
- La suite compte **757 tests** avant ce plan.
- Lancer les tests :
  `xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build`

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `Cairn/Features/Journal/JournalAttachment.swift` | **créé** : la règle — nom du fichier, ligne à écrire |
| `Cairn/Features/Journal/JournalFolder.swift` | modifié : copier une pièce jointe |
| `Cairn/Features/Shared/MarkdownBlock.swift` | modifié : le bloc image |
| `Cairn/Features/Shared/MarkdownText.swift` | modifié : dessiner une image, résolue contre un dossier |
| `Cairn/Features/Journal/JournalDetailView.swift` | modifié : les trois gestes |
| `Cairn/Features/Shared/MarkdownHTML.swift` | modifié : le bloc image, avec sa table |
| `Cairn/Features/Export/JournalBookAssets.swift` | modifié : encoder les images des notes |
| `Cairn/Features/Export/JournalBookHTML.swift` | modifié : passer la table au rendu |
| `Tests/JournalAttachmentTests.swift` | **créé** |
| `Tests/JournalFolderTests.swift`, `Tests/MarkdownTests.swift`, `Tests/MarkdownHTMLTests.swift` | modifiés |

---

### Tâche 1 : la règle — nom du fichier et ligne à écrire

**Fichiers :**
- Créer : `Cairn/Features/Journal/JournalAttachment.swift`
- Créer : `Tests/JournalAttachmentTests.swift`

**Interfaces produites :**
```swift
enum JournalAttachment {
    static let folderName = "pieces-jointes"
    static let allowedExtensions: Set<String>
    static func fileName(
        for date: DateKey, extension ext: String, taken: Set<String>
    ) -> String
    static func link(to fileName: String) -> String
    static func appending(_ links: [String], to text: String) -> String
}
```

- [ ] **Étape 1 : écrire les tests qui échouent**

Créer `Tests/JournalAttachmentTests.swift` :

```swift
import Testing
import Foundation
@testable import Cairn

@Suite("Les pièces jointes du journal")
struct JournalAttachmentTests {
    private let day = DateKey(raw: "2026-08-13")!

    @Test("le nom prend le premier numéro libre du jour")
    func nameTakesTheFirstFreeNumber() {
        #expect(
            JournalAttachment.fileName(for: day, extension: "jpg", taken: [])
                == "2026-08-13-1.jpg"
        )
        #expect(
            JournalAttachment.fileName(
                for: day, extension: "jpg",
                taken: ["2026-08-13-1.jpg", "2026-08-13-2.png"]
            ) == "2026-08-13-3.jpg"
        )
        // Le numéro est libre quelle que soit l'extension prise : deux fichiers
        // qui ne diffèrent que par elle se confondraient à la lecture.
        #expect(
            JournalAttachment.fileName(
                for: day, extension: "png", taken: ["2026-08-13-1.jpg"]
            ) == "2026-08-13-2.png"
        )
    }

    @Test("l'extension descend en minuscules")
    func theExtensionIsLowercased() {
        #expect(
            JournalAttachment.fileName(for: day, extension: "JPG", taken: [])
                == "2026-08-13-1.jpg"
        )
    }

    @Test("le lien est du Markdown standard, pas une syntaxe d'Obsidian")
    func thelinkIsPlainMarkdown() {
        #expect(
            JournalAttachment.link(to: "2026-08-13-1.jpg")
                == "![](pieces-jointes/2026-08-13-1.jpg)"
        )
    }

    @Test("la ligne s'ajoute à la fin sans doubler les sauts de ligne")
    func linksLandAtTheEnd() {
        let link = JournalAttachment.link(to: "2026-08-13-1.jpg")
        // Une note vide n'ouvre pas sur une ligne blanche.
        #expect(JournalAttachment.appending([link], to: "") == link)
        // Une note sans saut de ligne final en gagne un.
        #expect(
            JournalAttachment.appending([link], to: "Jambes lourdes.")
                == "Jambes lourdes.\n\n\(link)"
        )
        // Une note qui en a déjà n'en gagne pas deux.
        #expect(
            JournalAttachment.appending([link], to: "Jambes lourdes.\n\n")
                == "Jambes lourdes.\n\n\(link)"
        )
    }

    @Test("plusieurs fichiers donnent plusieurs lignes, dans l'ordre")
    func severalFilesKeepTheirOrder() {
        let first = JournalAttachment.link(to: "2026-08-13-1.jpg")
        let second = JournalAttachment.link(to: "2026-08-13-2.jpg")
        #expect(
            JournalAttachment.appending([first, second], to: "Note.")
                == "Note.\n\n\(first)\n\(second)"
        )
    }

    @Test("seules les images entrent")
    func onlyImagesAreAccepted() {
        #expect(JournalAttachment.allowedExtensions.contains("jpg"))
        #expect(JournalAttachment.allowedExtensions.contains("jpeg"))
        #expect(JournalAttachment.allowedExtensions.contains("png"))
        #expect(JournalAttachment.allowedExtensions.contains("heic"))
        #expect(!JournalAttachment.allowedExtensions.contains("pdf"))
        #expect(!JournalAttachment.allowedExtensions.contains("md"))
    }
}
```

- [ ] **Étape 2 : les lancer et les voir échouer**

```bash
xcodegen generate
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalAttachmentTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: cannot find 'JournalAttachment' in scope`.

- [ ] **Étape 3 : écrire la règle**

Créer `Cairn/Features/Journal/JournalAttachment.swift` :

```swift
import Foundation

/// What a photo dropped on a note becomes: a file name, and a line of
/// Markdown.
///
/// A value-only piece, like everything in this feature that is not
/// `JournalFolder`: naming a file and appending a line are decisions worth
/// testing, and neither needs a disk to be made.
enum JournalAttachment {
    /// Beside the notes, not among them: a vault whose root fills with images
    /// is a vault where the notes get hard to find.
    static let folderName = "pieces-jointes"

    /// What a journal takes. Anything else dropped on a note is refused out
    /// loud — a file ignored in silence is a file one believes was added.
    static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]

    /// `AAAA-MM-JJ-N.ext`, N being the first free number of that day.
    ///
    /// The original name is dropped on purpose: it comes from a camera or a
    /// screenshot, it says nothing, and two "IMG_4032.jpg" would eventually
    /// meet. The number is free regardless of extension — two files differing
    /// only by theirs would read as the same photo.
    static func fileName(
        for date: DateKey, extension ext: String, taken: Set<String>
    ) -> String {
        let stems = Set(taken.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent })
        var number = 1
        while stems.contains("\(date.raw)-\(number)") { number += 1 }
        return "\(date.raw)-\(number).\(ext.lowercased())"
    }

    /// Plain Markdown, not Obsidian's `![[…]]`: Obsidian reads both, and the
    /// book's HTML has no reason to learn a syntax one application owns.
    static func link(to fileName: String) -> String {
        "![](\(folderName)/\(fileName))"
    }

    /// The links at the end of the note, each on its own line.
    ///
    /// A blank line before them when there is text to separate from, and none
    /// when the note is empty or already ends in one: a note that opens on a
    /// blank line looks like a note someone started by accident.
    static func appending(_ links: [String], to text: String) -> String {
        guard !links.isEmpty else { return text }
        let body = links.joined(separator: "\n")
        guard !text.isEmpty else { return body }
        if text.hasSuffix("\n\n") { return text + body }
        if text.hasSuffix("\n") { return text + "\n" + body }
        return text + "\n\n" + body
    }
}
```

- [ ] **Étape 4 : les lancer et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalAttachmentTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : `Test run with 6 tests in 1 suite passed`.

- [ ] **Étape 5 : commiter**

```bash
git add Cairn/Features/Journal/JournalAttachment.swift Tests/JournalAttachmentTests.swift
git commit -m "feat(journal): la règle de nommage et d'insertion d'une pièce jointe"
```

---

### Tâche 2 : écrire la pièce jointe sur le disque

**Fichiers :**
- Modifier : `Cairn/Features/Journal/JournalFolder.swift`
- Modifier : `Tests/JournalFolderTests.swift`

**Interfaces consommées :** `JournalAttachment` (tâche 1).

**Interfaces produites :**
```swift
extension JournalFolder {
    static func attachmentsFolder(in folder: URL) -> URL
    /// - Returns: le nom du fichier écrit.
    @discardableResult
    static func copyAttachment(
        from source: URL, for date: DateKey, in folder: URL
    ) throws -> String
    @discardableResult
    static func writeAttachment(
        _ data: Data, extension ext: String, for date: DateKey, in folder: URL
    ) throws -> String
}
```

- [ ] **Étape 1 : écrire les tests qui échouent**

À ajouter dans `Tests/JournalFolderTests.swift`, en réutilisant son
`makeFolder()` :

```swift
    @Test("une pièce jointe copiée prend son nom du jour")
    func acopiedAttachmentIsRenamed() throws {
        let folder = try makeFolder()
        let source = folder.appending(path: "IMG_4032.JPG")
        try Data([0xFF, 0xD8]).write(to: source)

        let name = try JournalFolder.copyAttachment(
            from: source, for: DateKey(raw: "2026-08-13")!, in: folder
        )
        #expect(name == "2026-08-13-1.jpg")

        let written = JournalFolder.attachmentsFolder(in: folder)
            .appending(path: name)
        #expect(FileManager.default.fileExists(atPath: written.path))
        // L'original n'est pas déplacé : la photo reste où elle était.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("deux pièces jointes du même jour ne se marchent pas dessus")
    func twoAttachmentsOfTheSameDayCoexist() throws {
        let folder = try makeFolder()
        let day = DateKey(raw: "2026-08-13")!
        let first = try JournalFolder.writeAttachment(
            Data([0x89]), extension: "png", for: day, in: folder
        )
        let second = try JournalFolder.writeAttachment(
            Data([0x89]), extension: "png", for: day, in: folder
        )
        #expect(first == "2026-08-13-1.png")
        #expect(second == "2026-08-13-2.png")
    }

    @Test("le dossier des pièces jointes se crée au besoin")
    func theattachmentsFolderIsCreated() throws {
        let folder = try makeFolder()
        let attachments = JournalFolder.attachmentsFolder(in: folder)
        #expect(!FileManager.default.fileExists(atPath: attachments.path))

        _ = try JournalFolder.writeAttachment(
            Data([0x89]), extension: "png",
            for: DateKey(raw: "2026-08-13")!, in: folder
        )
        #expect(FileManager.default.fileExists(atPath: attachments.path))
    }

    @Test("une pièce jointe n'est pas une note")
    func anattachmentIsNotANote() throws {
        let folder = try makeFolder()
        try JournalFolder.write("Note.", for: DateKey(raw: "2026-08-13")!, in: folder)
        _ = try JournalFolder.writeAttachment(
            Data([0x89]), extension: "png",
            for: DateKey(raw: "2026-08-13")!, in: folder
        )
        // Le listing est plat par nature : le sous-dossier n'y entre pas.
        #expect(try JournalFolder.notes(in: folder).count == 1)
    }
```

- [ ] **Étape 2 : les lancer et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalFolderTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: type 'JournalFolder' has no member 'copyAttachment'`.

- [ ] **Étape 3 : écrire la copie**

À ajouter dans `JournalFolder.swift` :

```swift
    static func attachmentsFolder(in folder: URL) -> URL {
        folder.appending(path: JournalAttachment.folderName)
    }

    /// Copies a picture into the vault under a name of the journal's own.
    ///
    /// Copied and not moved: the photo the user dropped goes on living where
    /// it was, in a library or a download folder, and a journal that swallowed
    /// originals would be a journal one stops dropping things on.
    @discardableResult
    static func copyAttachment(
        from source: URL, for date: DateKey, in folder: URL
    ) throws -> String {
        let name = try prepareName(
            extension: source.pathExtension, for: date, in: folder
        )
        try FileManager.default.copyItem(
            at: source, to: attachmentsFolder(in: folder).appending(path: name)
        )
        return name
    }

    /// The same, from bytes — what a paste hands over: the clipboard carries
    /// an image far more often than it carries a file.
    @discardableResult
    static func writeAttachment(
        _ data: Data, extension ext: String, for date: DateKey, in folder: URL
    ) throws -> String {
        let name = try prepareName(extension: ext, for: date, in: folder)
        try data.write(
            to: attachmentsFolder(in: folder).appending(path: name)
        )
        return name
    }

    /// The free name, the folder made ready to receive it.
    private static func prepareName(
        extension ext: String, for date: DateKey, in folder: URL
    ) throws -> String {
        let attachments = attachmentsFolder(in: folder)
        try FileManager.default.createDirectory(
            at: attachments, withIntermediateDirectories: true
        )
        let taken = Set(
            (try? FileManager.default.contentsOfDirectory(
                atPath: attachments.path
            )) ?? []
        )
        return JournalAttachment.fileName(
            for: date, extension: ext, taken: taken
        )
    }
```

- [ ] **Étape 4 : les lancer et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/JournalFolderTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : les tests d'origine plus les quatre nouveaux, tous verts.

- [ ] **Étape 5 : commiter**

```bash
git add Cairn/Features/Journal/JournalFolder.swift Tests/JournalFolderTests.swift
git commit -m "feat(journal): copier une photo dans le coffre, à côté des notes"
```

---

### Tâche 3 : le bloc image du parseur, et son rendu à l'écran

**Fichiers :**
- Modifier : `Cairn/Features/Shared/MarkdownBlock.swift`
- Modifier : `Cairn/Features/Shared/MarkdownText.swift`
- Modifier : `Tests/MarkdownTests.swift`

**Interfaces produites :**
```swift
enum MarkdownBlock {
    case image(path: String, alt: String)   // en plus des cinq existantes
}
extension MarkdownText {
    /// Le dossier contre lequel un chemin relatif se résout. Nil : pas d'image.
    var attachmentsBase: URL? { get set }
}
```

- [ ] **Étape 1 : écrire les tests qui échouent**

À ajouter dans `Tests/MarkdownTests.swift` :

```swift
    @Test("une ligne qui n'est qu'une image devient un bloc image")
    func alineThatIsOnlyAnImageBecomesAnImageBlock() {
        #expect(
            MarkdownParser.blocks(from: "![](pieces-jointes/2026-08-13-1.jpg)")
                == [.image(path: "pieces-jointes/2026-08-13-1.jpg", alt: "")]
        )
        #expect(
            MarkdownParser.blocks(from: "![Le sommet](x.png)")
                == [.image(path: "x.png", alt: "Le sommet")]
        )
    }

    @Test("une image au milieu d'une phrase reste du texte")
    func animageInsideASentenceStaysText() {
        // La même retenue que le reste du parseur : il ne reconnaît que ce que
        // quelqu'un tape sans penser à Markdown.
        #expect(
            MarkdownParser.blocks(from: "voir ![](x.jpg) ici")
                == [.paragraph("voir ![](x.jpg) ici")]
        )
    }

    @Test("le texte d'un bloc image est son texte de remplacement")
    func theimageBlockTextIsItsAlt() {
        #expect(MarkdownBlock.image(path: "x.jpg", alt: "Le sommet").text == "Le sommet")
    }
```

- [ ] **Étape 2 : les lancer et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MarkdownTests 2>&1 | grep -E "error:|Test run with"
```

Attendu : `error: type 'MarkdownBlock' has no member 'image'`.

- [ ] **Étape 3 : le bloc, puis le rendu**

Dans `MarkdownBlock.swift`, ajouter le cas, son `id` et son `text` :

```swift
    /// A picture on a line of its own. Only there: an image inside a sentence
    /// is a sentence, and this parser recognises nothing it was not asked to.
    case image(path: String, alt: String)
```

`id` : `"img-\(path)"`. `text` : le texte de remplacement, qui est ce qu'un
rendu sans image doit écrire.

Dans `MarkdownParser.blocks(from:)`, avant le cas paragraphe :

```swift
            if let image = image(in: line) {
                flushParagraph()
                blocks.append(image)
                continue
            }
```

```swift
    /// `![alt](chemin)` and nothing else on the line.
    private static func image(in line: String) -> MarkdownBlock? {
        guard line.hasPrefix("!["), line.hasSuffix(")"),
              let altEnd = line.firstIndex(of: "]"),
              line[line.index(after: altEnd)] == "("
        else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd])
        let path = String(
            line[line.index(altEnd, offsetBy: 2)..<line.index(before: line.endIndex)]
        )
        // A closing bracket inside the path means this was never one image.
        guard !path.isEmpty, !path.contains("]"), !path.contains("(") else {
            return nil
        }
        return .image(path: path, alt: alt)
    }
```

Dans `MarkdownText.swift`, une propriété de plus et un cas de plus :

```swift
    /// The folder a relative path resolves against — the vault, for a journal
    /// note. Nil where there is none: an activity's note has no attachments,
    /// and pretending otherwise would draw an empty frame under every line.
    var attachmentsBase: URL?
```

```swift
                case let .image(path, alt):
                    image(path: path, alt: alt)
```

```swift
    /// The picture, or its name.
    ///
    /// A missing file is not an error worth a broken frame: in a vault synced
    /// by iCloud, a picture that has not come down yet is not a picture that is
    /// gone, and nothing here can tell the two apart. Its name says which one
    /// is waiting.
    @ViewBuilder
    private func image(path: String, alt: String) -> some View {
        if let base = attachmentsBase,
           let nsImage = NSImage(contentsOf: base.appending(path: path)) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(.rect(cornerRadius: 6))
        } else {
            sized(Text(alt.isEmpty ? path : alt))
                .foregroundStyle(.secondary)
        }
    }
```

`MarkdownText` importe déjà SwiftUI ; `NSImage` demande `import AppKit`.

- [ ] **Étape 4 : les lancer et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : toute la suite verte. Le compilateur signalera tout `switch` sur
`MarkdownBlock` devenu non exhaustif — `MarkdownHTML` en est un, et la tâche 5
s'en occupe ; en attendant, lui faire rendre le texte de remplacement.

- [ ] **Étape 5 : commiter**

```bash
git add Cairn/Features/Shared Tests/MarkdownTests.swift
git commit -m "feat(journal): le parseur reconnaît une image, le rendu la dessine"
```

---

### Tâche 4 : les trois gestes

**Fichiers :**
- Modifier : `Cairn/Features/Journal/JournalDetailView.swift`
- Modifier : `Cairn/App/RootView.swift` (le dossier et l'écriture)

**Interfaces consommées :** tâches 1 à 3.

Pas de test automatique : une glissée-déposée et un panneau de fichiers ne se
rejouent pas sans interface. Ce qui se teste — le nom, la ligne, la copie — l'a
été aux tâches 1 et 2.

- [ ] **Étape 1 : le volet accepte les fichiers**

`JournalDetailView` reçoit deux choses de plus, passées par `RootView` :

```swift
    /// The vault, for resolving what a note's images point at.
    let attachmentsBase: URL?
    /// Hands over the files a gesture produced, in the order they arrived.
    /// The caller copies them and appends the links — this view only gathers.
    let onAddPhotos: ([URL]) -> Void
    /// The same for pasted bytes, which carry no file at all.
    let onPastePhoto: (Data, String) -> Void
```

Le rendu de la note passe `attachmentsBase` à `MarkdownText`, dans les deux
endroits où il apparaît (le corps de la note et l'aperçu).

Sur le volet entier :

```swift
        .dropDestination(for: URL.self) { urls, _ in
            onAddPhotos(urls)
            return true
        }
```

- [ ] **Étape 2 : le bouton et le collage**

Dans l'en-tête du volet, à côté de la date, un bouton discret :

```swift
                Button {
                    choosePhotos()
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Ajouter une photo à cette note")
```

```swift
    /// The one gesture that shows itself: a drop and a paste are both things
    /// one has to already know about.
    private func choosePhotos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .heic]
        panel.prompt = "Ajouter"
        guard panel.runModal() == .OK else { return }
        onAddPhotos(panel.urls)
    }
```

Le collage, sur le volet :

```swift
        .onPasteCommand(of: [.fileURL, .png, .jpeg, .heic]) { providers in
            // Files first: a paste that carries one is a paste of that file,
            // and keeping its extension beats re-encoding it as PNG.
            …
        }
```

Le détail de `onPasteCommand` est laissé à l'implémenteur : charger les
`NSItemProvider` en `URL` quand c'est possible, en `Data` sinon, et appeler
respectivement `onAddPhotos` et `onPastePhoto(data, "png")`.

- [ ] **Étape 3 : `RootView` écrit**

```swift
    /// Copies each picture into the vault and appends its link to the note.
    ///
    /// Through the store like any keystroke: the note stays a Markdown file
    /// someone else can edit, and Cairn only ever adds a line to it.
    private func addJournalPhotos(_ urls: [URL], to date: DateKey) {
        guard let folder = app.journal.folder else {
            fileMessage = "Aucun dossier de journal n'est choisi."
            return
        }
        var links: [String] = []
        var refused: [String] = []
        for url in urls {
            guard JournalAttachment.allowedExtensions
                .contains(url.pathExtension.lowercased())
            else {
                refused.append(url.lastPathComponent)
                continue
            }
            do {
                let name = try JournalFolder.copyAttachment(
                    from: url, for: date, in: folder
                )
                links.append(JournalAttachment.link(to: name))
            } catch {
                refused.append(url.lastPathComponent)
            }
        }
        if !links.isEmpty {
            let note = app.journal.text(for: date)
            app.journal.update(
                JournalAttachment.appending(links, to: note), for: date
            )
        }
        if !refused.isEmpty {
            fileMessage = "Ces fichiers n'ont pas pu être ajoutés : "
                + refused.joined(separator: ", ")
        }
    }
```

Le collage appelle `JournalFolder.writeAttachment` puis les mêmes deux
dernières lignes. `JournalStore.text(for:)` rend le texte courant — le tampon
quand la note est en cours d'édition, le fichier sinon — et
`JournalStore.update(_:for:)` l'écrit ; ce sont les deux appels à utiliser, pas
une lecture du disque.

- [ ] **Étape 4 : compiler, lancer toute la suite, commiter**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|✘|Test run with"
git add Cairn/Features/Journal/JournalDetailView.swift Cairn/App/RootView.swift
git commit -m "feat(journal): déposer, coller ou choisir une photo dans une note"
```

---

### Tâche 5 : les photos dans le carnet PDF

**Fichiers :**
- Modifier : `Cairn/Features/Shared/MarkdownHTML.swift`
- Modifier : `Cairn/Features/Export/JournalBookAssets.swift`
- Modifier : `Cairn/Features/Export/JournalBookHTML.swift`
- Modifier : `Tests/MarkdownHTMLTests.swift`

**Interfaces produites :**
```swift
enum MarkdownHTML {
    static func render(
        _ markdown: String, hidingTagHashes: Bool = true,
        images: [String: String] = [:]
    ) -> String
}
extension JournalBookAssets {
    /// Les images des notes du carnet, chemin écrit → `data:` URI.
    static func noteImages(
        for book: JournalBook, vault: URL?, progress: @escaping (Int, Int) -> Void
    ) -> [String: String]
}
```

- [ ] **Étape 1 : écrire les tests qui échouent**

À ajouter dans `Tests/MarkdownHTMLTests.swift` :

```swift
    @Test("une image connue entre dans le carnet avec sa source")
    func aknownImageCarriesItsSource() {
        let html = MarkdownHTML.render(
            "![Le sommet](pieces-jointes/2026-08-13-1.jpg)",
            images: ["pieces-jointes/2026-08-13-1.jpg": "data:image/jpeg;base64,AAA"]
        )
        #expect(html.contains("<img src=\"data:image/jpeg;base64,AAA\""))
        #expect(html.contains("alt=\"Le sommet\""))
    }

    @Test("une image inconnue rend son texte, jamais une balise vide")
    func anunknownImageRendersItsText() {
        let html = MarkdownHTML.render("![Le sommet](x.jpg)")
        #expect(!html.contains("<img"))
        #expect(html.contains("Le sommet"))
    }

    @Test("le texte de remplacement est échappé comme le reste")
    func thealtTextIsEscaped() {
        let html = MarkdownHTML.render(
            "![a & b](x.jpg)", images: ["x.jpg": "data:image/png;base64,AAA"]
        )
        #expect(html.contains("alt=\"a &amp; b\""))
    }
```

- [ ] **Étape 2 : les lancer et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MarkdownHTMLTests 2>&1 | grep -E "error:|✘|Test run with"
```

Attendu : l'appel avec `images:` ne compile pas.

- [ ] **Étape 3 : le rendu HTML, puis les images du carnet**

`MarkdownHTML.render` prend `images: [String: String] = [:]` et gagne son cas :

```swift
            case let .image(path, alt):
                closeList()
                if let source = images[path] {
                    html += "<figure class=\"note-photo\">"
                        + "<img src=\"\(source)\" alt=\"\(escape(alt))\"></figure>"
                } else {
                    // The book is one file: an image nobody encoded is an
                    // image that would come out as a broken frame.
                    html += "<p class=\"missing-photo\">\(escape(alt.isEmpty ? path : alt))</p>"
                }
```

`JournalBookAssets` gagne la collecte : pour chaque journée du carnet, les blocs
image de sa note ; pour chacun, le fichier lu depuis le coffre, ramené à
`photoWidth` et encodé par `jpegDataURI` — la même chaîne que les photos d'une
sortie. Les chemins qui ne se lisent pas sont simplement absents de la table.

Le total de la progression compte ces images comme les autres, et
`RootView.exportJournalPDF` passe `app.journal.folder` en `vault`.

`JournalBookHTML.document` prend `noteImages: [String: String] = [:]` et le
passe à chaque `MarkdownHTML.render` de note. La feuille de style gagne :

```css
figure.note-photo img { width: 100%; height: auto; border-radius: 4pt; }
figure.note-photo { break-inside: avoid; margin: .7em 0; }
.missing-photo { color: #6c6c70; font-style: italic; }
```

- [ ] **Étape 4 : les lancer et les voir passer, puis commiter**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|✘|Test run with"
git add Cairn/Features/Shared/MarkdownHTML.swift Cairn/Features/Export Tests/MarkdownHTMLTests.swift
git commit -m "feat(export): le carnet embarque les photos des notes"
```

- [ ] **Étape 5 : le vérifier à l'écran**

Ne pas faire soi-même : le propriétaire du dépôt s'en charge.

```bash
xcodebuild build -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build && open build/Build/Products/Debug/Cairn.app
```

À vérifier : une photo lâchée sur une note apparaît en bas du texte et s'affiche
en lecture ; le fichier est dans `pieces-jointes/` du coffre ; Obsidian montre
la même note avec la même image ; un export PDF de la période la contient.
