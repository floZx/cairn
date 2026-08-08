# Alimentation — Phase 5 : pipeline du catalogue Open Food Facts

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Le bouton « Mettre à jour le catalogue » : téléchargement de l'export CSV OFF (~1 Go gz) avec reprise validée, décompression et filtrage en flux, reconstruction du `off.db` FTS5 avec bascule atomique, progression et annulation dans Réglages → Nutrition.

**Architecture:** Quatre unités : `CatalogCSV` (parsing/filtrage pur d'une ligne TSV, colonnes résolues par nom d'en-tête), `FileDownloader` (contrat de reprise de `data/download.py` porté sur un transport injectable), `CatalogBuilder` (gunzip en flux via `/usr/bin/gunzip`, insertions par lots transactionnels, FTS, swap atomique), `CatalogUpdater` (`@Observable`, machine à états pour l'UI, annulation par Task). Le travail lourd tourne hors MainActor ; la progression y revient par sauts.

**Tech Stack:** Swift 6, URLSession (délégué de flux), Process (`/usr/bin/gunzip`), SQLite système via `SQLiteDatabase`, Swift Testing. Aucune dépendance externe.

**Spec :** `docs/specs/2026-08-08-alimentation-design.md` (§3 catalogue, §9 erreurs, §11 phase 5). Reliquat phase 2 intégré : message visible quand la recherche échoue n'est PAS ici (c'est un écran de recherche, phase 6) — cette phase couvre le pipeline seul.

## Global Constraints

- macOS 15.0 minimum, Swift 6.0 strict. Aucune dépendance externe (`gunzip` et SQLite sont système).
- Identifiants/commentaires **anglais**, chaînes visibles **français**, commentaires « pourquoi ».
- Après **tout ajout de fichier source** : `xcodegen generate` avant de builder.
- Tests : Swift Testing, noms en français. Commande type :
  ```bash
  xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/CatalogCSVTests 2>&1 | tail -5
  ```
- Commits : Conventional Commits en français, scope `catalogue`.
- **Contrat de reprise porté de `data/download.py` à l'identique** : fichier partiel `.part` + validateur `.part.etag` (ETag sinon Last-Modified), écrit **avant** le flux ; reprise = `Range: bytes=N-` + `If-Range: <validateur>` ; un `.part` sans validateur repart de zéro ; réponse 200 sur une reprise = fichier distant changé → on repart de zéro ; 416 avec `Content-Range: bytes */N` où N == taille du `.part` = téléchargement déjà complet → promotion ; 416 sinon = `.part` invalide → suppression et recommencement ; téléchargement incomplet (octets ≠ total annoncé) → erreur, `.part` **conservé** pour reprise ; succès → promotion du `.part` et nettoyage du validateur.
- **Filtres portés de `FILTER_SQL` à l'identique** : `countries_tags` contient `en:france` ; nom et code non vides ; kcal et protéines présents ; `completeness ≥ 0.5` ; bornes de vraisemblance kcal 0–900, protéines 0–100, glucides/lipides absents ou 0–100.
- Sécurité du fichier réel : le nouveau catalogue s'écrit dans `off.db.tmp` et ne remplace `off.db` qu'en **bascule atomique** finale — un échec en cours de route ne touche jamais le catalogue courant (spec §9).
- URL de l'export : `https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz`. Cache de téléchargement : `Application Support/Cairn/cache/food.csv.gz` (supprimé après un build réussi, conservé pour reprise sinon).

---

### Task 1: CatalogCSV — parsing et filtrage purs

**Files:**
- Create: `Cairn/Features/Nutrition/CatalogCSV.swift`
- Test: `Tests/CatalogCSVTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces (utilisé par Task 3) :

```swift
enum CatalogCSV {
    struct Columns: Equatable {
        var code: Int
        var name: Int
        var brands: Int
        var quantity: Int
        var servingSize: Int
        var countriesTags: Int
        var completeness: Int
        var kcal: Int
        var protein: Int
        var carbs: Int
        var fat: Int
    }
    struct Row: Equatable {
        var code: String
        var name: String
        var brands: String?
        var quantity: String?
        var kcal: Double
        var protein: Double
        var carbs: Double?
        var fat: Double?
        var servingSize: String?
        var completeness: Double
    }
    struct HeaderError: Error, CustomStringConvertible { let message: String }
    static let completenessThreshold = 0.5
    /// Throws naming the missing column — a changed export must fail loudly.
    static func columns(from headerLine: String) throws -> Columns
    /// nil = filtered out (not France, incomplete, implausible…).
    static func row(from line: String, columns: Columns) -> Row?
}
```

Les colonnes sont résolues **par nom d'en-tête** (l'ordre de l'export OFF n'est pas un contrat) : `code`, `product_name`, `brands`, `quantity`, `serving_size`, `countries_tags`, `completeness`, `energy-kcal_100g`, `proteins_100g`, `carbohydrates_100g`, `fat_100g`. Le TSV OFF ne quote pas (les tabulations sont retirées des champs à l'export) : `split(separator: "\t", omittingEmptySubsequences: false)` suffit.

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/CatalogCSVTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("CatalogCSV")
struct CatalogCSVTests {
    private static let header = [
        "code", "url", "product_name", "brands", "quantity", "serving_size",
        "countries_tags", "completeness", "energy-kcal_100g", "proteins_100g",
        "carbohydrates_100g", "fat_100g",
    ].joined(separator: "\t")

    /// A line in the fixture header's order, with sensible defaults.
    private func line(
        code: String = "123", name: String = "Flocons d'avoine",
        brands: String = "Marque A", countries: String = "en:france,en:belgium",
        completeness: String = "0.9", kcal: String = "370",
        protein: String = "13", carbs: String = "60", fat: String = "7"
    ) -> String {
        [
            code, "https://exemple", name, brands, "500 g", "40 g",
            countries, completeness, kcal, protein, carbs, fat,
        ].joined(separator: "\t")
    }

    private func columns() throws -> CatalogCSV.Columns {
        try CatalogCSV.columns(from: Self.header)
    }

    @Test("les colonnes se résolvent par nom, pas par position")
    func columnsResolveByName() throws {
        let columns = try columns()
        // "url" est intercalée : les index doivent la sauter.
        #expect(columns.code == 0)
        #expect(columns.name == 2)
        #expect(columns.kcal == 8)
        #expect(columns.fat == 11)
    }

    @Test("une colonne manquante échoue en la nommant")
    func missingColumnThrowsWithName() {
        #expect(throws: CatalogCSV.HeaderError.self) {
            _ = try CatalogCSV.columns(from: "code\tproduct_name\tbrands")
        }
        do {
            _ = try CatalogCSV.columns(from: "code\tproduct_name\tbrands")
        } catch let error as CatalogCSV.HeaderError {
            #expect(error.message.contains("countries_tags"))
        } catch {
            Issue.record("mauvais type d'erreur")
        }
    }

    @Test("une ligne française complète passe avec ses valeurs")
    func frenchCompleteRowParses() throws {
        let row = try #require(CatalogCSV.row(from: line(), columns: columns()))
        #expect(row.code == "123")
        #expect(row.name == "Flocons d'avoine")
        #expect(row.brands == "Marque A")
        #expect(row.kcal == 370)
        #expect(row.protein == 13)
        #expect(row.carbs == 60)
        #expect(row.fat == 7)
        #expect(row.servingSize == "40 g")
        #expect(row.completeness == 0.9)
    }

    @Test("hors France, filtré — même si 'france' apparaît ailleurs")
    func nonFranceFiltered() throws {
        let columns = try columns()
        #expect(CatalogCSV.row(
            from: line(countries: "en:belgium"), columns: columns
        ) == nil)
        // "en:french-guiana" contient "france" mais n'est pas le tag exact.
        #expect(CatalogCSV.row(
            from: line(countries: "en:french-guiana"), columns: columns
        ) == nil)
    }

    @Test("nom vide, code vide, kcal ou protéines absents : filtrés")
    func requiredFieldsFilter() throws {
        let columns = try columns()
        #expect(CatalogCSV.row(from: line(name: ""), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(code: ""), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(kcal: ""), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(protein: ""), columns: columns) == nil)
    }

    @Test("complétude insuffisante ou absente : filtrée")
    func completenessFilter() throws {
        let columns = try columns()
        #expect(CatalogCSV.row(
            from: line(completeness: "0.4"), columns: columns
        ) == nil)
        #expect(CatalogCSV.row(
            from: line(completeness: ""), columns: columns
        ) == nil)
        #expect(CatalogCSV.row(
            from: line(completeness: "0.5"), columns: columns
        ) != nil)
    }

    @Test("bornes de vraisemblance : kcal 0-900, macros 0-100")
    func plausibilityBounds() throws {
        let columns = try columns()
        // 1500 "kcal" est un kJ saisi dans le mauvais champ.
        #expect(CatalogCSV.row(from: line(kcal: "1500"), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(kcal: "-1"), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(protein: "120"), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(carbs: "101"), columns: columns) == nil)
        #expect(CatalogCSV.row(from: line(fat: "-2"), columns: columns) == nil)
        // Glucides/lipides absents restent acceptés, en nil.
        let sparse = try #require(CatalogCSV.row(
            from: line(carbs: "", fat: ""), columns: columns
        ))
        #expect(sparse.carbs == nil)
        #expect(sparse.fat == nil)
    }

    @Test("brands et serving_size vides deviennent nil")
    func emptyOptionalsBecomeNil() throws {
        let columns = try columns()
        let row = try #require(CatalogCSV.row(
            from: [
                "123", "u", "Riz", "", "", "", "en:france", "0.8",
                "350", "7", "", "",
            ].joined(separator: "\t"),
            columns: columns
        ))
        #expect(row.brands == nil)
        #expect(row.servingSize == nil)
        #expect(row.quantity == nil)
    }

    @Test("une ligne trop courte est filtrée sans crash")
    func shortLineFiltered() throws {
        #expect(CatalogCSV.row(from: "123\tabc", columns: try columns()) == nil)
    }
}
```

- [ ] **Step 2: Vérifier l'échec**

Run: `xcodegen generate && xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/CatalogCSVTests 2>&1 | tail -5`
Expected: échec de compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/CatalogCSV.swift
import Foundation

/// One line of the Open Food Facts CSV export, parsed and filtered — the
/// Swift port of the importer's `FILTER_SQL`. Pure string work, no I/O:
/// the builder streams lines through here.
enum CatalogCSV {
    struct Columns: Equatable {
        var code: Int
        var name: Int
        var brands: Int
        var quantity: Int
        var servingSize: Int
        var countriesTags: Int
        var completeness: Int
        var kcal: Int
        var protein: Int
        var carbs: Int
        var fat: Int
    }

    struct Row: Equatable {
        var code: String
        var name: String
        var brands: String?
        var quantity: String?
        var kcal: Double
        var protein: Double
        var carbs: Double?
        var fat: Double?
        var servingSize: String?
        var completeness: Double
    }

    struct HeaderError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static let completenessThreshold = 0.5

    /// Column indexes resolved by header name — the export's column order
    /// is not a contract, and a renamed column must fail loudly rather than
    /// silently reading the wrong data into the catalog.
    static func columns(from headerLine: String) throws -> Columns {
        let names = headerLine
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init)
        func index(of name: String) throws -> Int {
            guard let index = names.firstIndex(of: name) else {
                throw HeaderError(
                    message: "Colonne « \(name) » introuvable dans l'export CSV."
                )
            }
            return index
        }
        return Columns(
            code: try index(of: "code"),
            name: try index(of: "product_name"),
            brands: try index(of: "brands"),
            quantity: try index(of: "quantity"),
            servingSize: try index(of: "serving_size"),
            countriesTags: try index(of: "countries_tags"),
            completeness: try index(of: "completeness"),
            kcal: try index(of: "energy-kcal_100g"),
            protein: try index(of: "proteins_100g"),
            carbs: try index(of: "carbohydrates_100g"),
            fat: try index(of: "fat_100g")
        )
    }

    /// nil = filtered out. The filters mirror `FILTER_SQL`: France only,
    /// name and code present, kcal/protein present, completeness ≥ 0.5,
    /// plausibility bounds (a kJ typed into the kcal field reads as 1500+).
    static func row(from line: String, columns: Columns) -> Row? {
        let fields = line
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init)
        func field(_ index: Int) -> String? {
            guard fields.indices.contains(index) else { return nil }
            let value = fields[index]
            return value.isEmpty ? nil : value
        }
        guard let code = field(columns.code),
              let name = field(columns.name),
              let countries = field(columns.countriesTags),
              countries.split(separator: ",").contains("en:france"),
              let completeness = field(columns.completeness).flatMap(Double.init),
              completeness >= completenessThreshold,
              let kcal = field(columns.kcal).flatMap(Double.init),
              let protein = field(columns.protein).flatMap(Double.init),
              (0...900).contains(kcal),
              (0...100).contains(protein)
        else { return nil }
        let carbs = field(columns.carbs).flatMap(Double.init)
        let fat = field(columns.fat).flatMap(Double.init)
        if let carbs, !(0...100).contains(carbs) { return nil }
        if let fat, !(0...100).contains(fat) { return nil }
        return Row(
            code: code, name: name,
            brands: field(columns.brands),
            quantity: field(columns.quantity),
            kcal: kcal, protein: protein, carbs: carbs, fat: fat,
            servingSize: field(columns.servingSize),
            completeness: completeness
        )
    }
}
```

- [ ] **Step 4: Vérifier le succès** — mêmes commandes, 9 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/CatalogCSV.swift Tests/CatalogCSVTests.swift
git commit -m "feat(catalogue): parsing et filtrage purs de l'export CSV OFF"
```

---

### Task 2: FileDownloader — reprise validée

**Files:**
- Create: `Cairn/Features/Nutrition/FileDownloader.swift`
- Test: `Tests/FileDownloaderTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces (utilisé par Task 4) :

```swift
enum FileDownloader {
    struct Transport: Sendable {
        var fetch: @Sendable (URLRequest) async throws
            -> (response: HTTPURLResponse, body: AsyncThrowingStream<Data, Error>)
        static let live: Transport   // URLSession en flux (délégué)
    }
    struct DownloadError: Error, CustomStringConvertible { let message: String }
    /// Downloads `url` into `destination`, resuming a leftover `.part` when
    /// the server proves the remote file has not changed. Cancellation
    /// (Task) keeps the `.part` for a later resume.
    static func download(
        from url: URL, to destination: URL,
        transport: Transport = .live,
        onProgress: (@Sendable (_ bytes: Int64, _ total: Int64?) -> Void)? = nil
    ) async throws
}
```

Le contrat complet est celui des Global Constraints (port de `data/download.py`). Fichiers de travail : `<destination>.part` et `<destination>.part.etag`.

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/FileDownloaderTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("FileDownloader")
struct FileDownloaderTests {
    private func makeDestination() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "download-\(UUID().uuidString)")
            .appending(path: "file.gz")
    }

    private func body(_ chunks: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }

    private func response(
        _ status: Int, headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://exemple.test/file.gz")!,
            statusCode: status, httpVersion: nil, headerFields: headers
        )!
    }

    /// A transport whose answers are scripted per call, recording requests.
    private final class Script: @unchecked Sendable {
        var requests: [URLRequest] = []
        var responses: [(HTTPURLResponse, AsyncThrowingStream<Data, Error>)] = []
        var transport: FileDownloader.Transport {
            FileDownloader.Transport { [self] request in
                requests.append(request)
                return responses.removeFirst()
            }
        }
    }

    @Test("un téléchargement frais écrit le validateur puis promeut")
    func freshDownloadPromotes() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        let script = Script()
        script.responses = [(
            response(200, headers: ["ETag": "\"v1\"", "Content-Length": "10"]),
            body([Data("hello ".utf8), Data("moon".utf8)])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(try String(contentsOf: destination, encoding: .utf8) == "hello moon")
        // Ni .part ni validateur ne survivent à un succès.
        #expect(!FileManager.default.fileExists(
            atPath: destination.path + ".part"))
        #expect(!FileManager.default.fileExists(
            atPath: destination.path + ".part.etag"))
        // Pas d'en-tête Range sur un départ à zéro.
        #expect(script.requests[0].value(forHTTPHeaderField: "Range") == nil)
    }

    @Test("une reprise envoie Range et If-Range et appende")
    func resumeSendsRangeAndAppends() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("hello ".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        try Data("\"v1\"".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part.etag"))
        let script = Script()
        script.responses = [(
            response(206, headers: ["Content-Range": "bytes 6-9/10"]),
            body([Data("moon".utf8)])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(script.requests[0].value(forHTTPHeaderField: "Range") == "bytes=6-")
        #expect(script.requests[0].value(forHTTPHeaderField: "If-Range") == "\"v1\"")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "hello moon")
    }

    @Test("un .part sans validateur repart de zéro")
    func partWithoutValidatorRestarts() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stale".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        let script = Script()
        script.responses = [(
            response(200, headers: ["Content-Length": "5"]),
            body([Data("fresh".utf8)])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(script.requests[0].value(forHTTPHeaderField: "Range") == nil)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "fresh")
    }

    @Test("200 sur une reprise = fichier distant changé, on repart")
    func fullResponseOnResumeRestarts() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("old-".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        try Data("\"v1\"".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part.etag"))
        let script = Script()
        script.responses = [(
            response(200, headers: ["ETag": "\"v2\"", "Content-Length": "8"]),
            body([Data("nouveau!".utf8)])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        // Pas de collage v1+v2 : le contenu est UNIQUEMENT la réponse 200.
        #expect(try String(contentsOf: destination, encoding: .utf8) == "nouveau!")
    }

    @Test("416 avec la taille du .part = déjà complet, promotion")
    func http416MatchingSizePromotes() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("0123456789".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        try Data("\"v1\"".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part.etag"))
        let script = Script()
        script.responses = [(
            response(416, headers: ["Content-Range": "bytes */10"]),
            body([])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(try String(contentsOf: destination, encoding: .utf8) == "0123456789")
    }

    @Test("416 avec une autre taille = .part invalide, on recommence")
    func http416MismatchRestarts() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("partiel".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        try Data("\"v1\"".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part.etag"))
        let script = Script()
        script.responses = [
            (response(416, headers: ["Content-Range": "bytes */99"]), body([])),
            (
                response(200, headers: ["Content-Length": "4"]),
                body([Data("neuf".utf8)])
            ),
        ]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(script.requests.count == 2)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "neuf")
    }

    @Test("incomplet : erreur, le .part reste pour reprendre")
    func incompleteKeepsPartAndThrows() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        let script = Script()
        script.responses = [(
            response(200, headers: ["ETag": "\"v1\"", "Content-Length": "10"]),
            body([Data("moitié".utf8.prefix(4))])
        )]

        await #expect(throws: FileDownloader.DownloadError.self) {
            try await FileDownloader.download(
                from: URL(string: "https://exemple.test/file.gz")!,
                to: destination, transport: script.transport
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(
            atPath: destination.path + ".part"))
        #expect(FileManager.default.fileExists(
            atPath: destination.path + ".part.etag"))
    }
}
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/FileDownloader.swift
import Foundation

/// Resumable download with a validated `.part`, ported from suivinut's
/// `data/download.py`. Resuming is only safe when the remote file has not
/// changed in between: the validator (ETag or Last-Modified) is remembered
/// beside the partial file and sent back as `If-Range` — if the server sees
/// a change it answers 200 with the whole file, and we start over instead
/// of gluing bytes of two different versions together.
enum FileDownloader {
    struct Transport: Sendable {
        var fetch: @Sendable (URLRequest) async throws
            -> (response: HTTPURLResponse, body: AsyncThrowingStream<Data, Error>)

        static let live = Transport { request in
            try await StreamingFetch.run(request)
        }
    }

    struct DownloadError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static func download(
        from url: URL, to destination: URL,
        transport: Transport = .live,
        onProgress: (@Sendable (_ bytes: Int64, _ total: Int64?) -> Void)? = nil
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let partURL = URL(fileURLWithPath: destination.path + ".part")
        let metaURL = URL(fileURLWithPath: destination.path + ".part.etag")

        var resumeFrom: Int64 = 0
        if let size = try? fileManager
            .attributesOfItem(atPath: partURL.path)[.size] as? Int64 {
            resumeFrom = size
        }
        var validator = (try? String(contentsOf: metaURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if validator?.isEmpty == true { validator = nil }
        // A .part with no remembered validator cannot be verified: resuming
        // it could splice two versions. Start over.
        if resumeFrom > 0 && validator == nil { resumeFrom = 0 }

        var request = URLRequest(url: url)
        if resumeFrom > 0, let validator {
            request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range")
            request.setValue(validator, forHTTPHeaderField: "If-Range")
        }

        let (response, bodyStream): (HTTPURLResponse, AsyncThrowingStream<Data, Error>)
        do {
            (response, bodyStream) = try await transport.fetch(request)
        } catch {
            throw error
        }

        if response.statusCode == 416 {
            // Either the .part is already the whole file (crash after the
            // last byte, before promotion), or the remote size changed and
            // the .part is garbage.
            if remoteSize(from: response) == resumeFrom, resumeFrom > 0 {
                try promote(partURL, to: destination, cleaning: metaURL)
                return
            }
            try? fileManager.removeItem(at: partURL)
            try? fileManager.removeItem(at: metaURL)
            try await download(
                from: url, to: destination, transport: transport,
                onProgress: onProgress
            )
            return
        }
        guard (200...299).contains(response.statusCode) else {
            throw DownloadError(
                message: "Le serveur a répondu \(response.statusCode)."
            )
        }

        var appending = resumeFrom > 0
        // 200 while we asked for a range: the remote file changed (If-Range)
        // or the server ignores ranges — it sends everything, start fresh.
        if appending && response.statusCode == 200 {
            appending = false
            resumeFrom = 0
        }
        var downloaded = resumeFrom
        let total = expectedTotal(of: response, resumingFrom: resumeFrom)

        if !appending {
            // Remembered BEFORE the stream: an interruption must leave a
            // coherent (.part, validator) pair for the next resume.
            let newValidator = response.value(forHTTPHeaderField: "ETag")
                ?? response.value(forHTTPHeaderField: "Last-Modified")
            if let newValidator {
                try newValidator.write(
                    to: metaURL, atomically: true, encoding: .utf8
                )
            } else {
                try? fileManager.removeItem(at: metaURL)
            }
            fileManager.createFile(atPath: partURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: partURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        do {
            for try await chunk in bodyStream {
                try Task.checkCancellation()
                try handle.write(contentsOf: chunk)
                downloaded += Int64(chunk.count)
                onProgress?(downloaded, total)
            }
        } catch is CancellationError {
            // The .part stays: cancellation is a pause, not a failure.
            throw CancellationError()
        }

        if let total, downloaded != total {
            throw DownloadError(
                message: "Téléchargement incomplet : \(downloaded)/\(total) octets "
                    + "reçus. Relancez pour reprendre."
            )
        }
        try promote(partURL, to: destination, cleaning: metaURL)
    }

    private static func promote(
        _ part: URL, to destination: URL, cleaning meta: URL
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: part, to: destination)
        try? fileManager.removeItem(at: meta)
    }

    /// Total size according to the headers, nil when unknown. On a 206 the
    /// Content-Length is only the remaining bytes; Content-Range carries the
    /// full size.
    private static func expectedTotal(
        of response: HTTPURLResponse, resumingFrom resumeFrom: Int64
    ) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let tail = contentRange.split(separator: "/").last,
           let size = Int64(tail.trimmingCharacters(in: .whitespaces)) {
            return size
        }
        if let length = response.value(forHTTPHeaderField: "Content-Length"),
           let size = Int64(length.trimmingCharacters(in: .whitespaces)) {
            return resumeFrom + size
        }
        return nil
    }

    /// The remote size a 416 announces (`Content-Range: bytes */N`).
    private static func remoteSize(from response: HTTPURLResponse) -> Int64? {
        guard let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
              let tail = contentRange.split(separator: "/").last
        else { return nil }
        return Int64(tail.trimmingCharacters(in: .whitespaces))
    }
}

/// URLSession streaming without buffering the gigabyte in memory: a data
/// task whose delegate forwards each received chunk into an AsyncStream.
private final class StreamingFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var responseContinuation: CheckedContinuation<HTTPURLResponse, Error>?

    static func run(
        _ request: URLRequest
    ) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        let delegate = StreamingFetch()
        let session = URLSession(
            configuration: .ephemeral, delegate: delegate, delegateQueue: nil
        )
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            delegate.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                session.invalidateAndCancel()
            }
        }
        let task = session.dataTask(with: request)
        let response = try await withCheckedThrowingContinuation { continuation in
            delegate.responseContinuation = continuation
            task.resume()
        }
        return (response, stream)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            responseContinuation?.resume(returning: http)
            responseContinuation = nil
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
    ) {
        continuation?.yield(data)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            responseContinuation?.resume(throwing: error)
            responseContinuation = nil
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        session.finishTasksAndInvalidate()
    }
}
```

- [ ] **Step 4: Vérifier le succès** — `-only-testing:CairnTests/FileDownloaderTests`, 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/FileDownloader.swift Tests/FileDownloaderTests.swift
git commit -m "feat(catalogue): téléchargement avec reprise validée porté de suivinut"
```

---

### Task 3: CatalogBuilder — construction du off.db en flux

**Files:**
- Create: `Cairn/Features/Nutrition/CatalogBuilder.swift`
- Modify: `Cairn/Features/Nutrition/FoodCatalog.swift` (ajout `importedAt()`)
- Test: `Tests/CatalogBuilderTests.swift`, `Tests/FoodCatalogTests.swift` (ajout)

**Interfaces:**
- Consumes: `CatalogCSV` (Task 1), `SQLiteDatabase` (avec `execute`, `rows(_:bindings:)`).
- Produces (utilisé par Task 4) :

```swift
enum CatalogBuilder {
    static let catalogURL = URL(
        string: "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
    )!
    struct BuildError: Error, CustomStringConvertible { let message: String }
    /// Streams the gzipped TSV through gunzip, filters, writes `<offDBPath>.tmp`
    /// and atomically swaps it in. Returns the product count. Synchronous —
    /// run it off the main actor. Checks `Task.isCancelled` between batches.
    static func build(
        gzPath: String, offDBPath: String, importedAt: String,
        onProgress: (@Sendable (_ linesSeen: Int, _ kept: Int) -> Void)? = nil
    ) throws -> Int
}

extension FoodCatalog {
    /// The `imported_at` value the builder stamped, nil on a legacy catalog.
    func importedAt() throws -> String?
}
```

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/CatalogBuilderTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("CatalogBuilder")
@MainActor
struct CatalogBuilderTests {
    /// Writes a TSV, gzips it with the system gzip, returns the .gz path.
    private func makeFixture(lines: [String]) throws -> (gz: String, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let tsv = dir.appending(path: "food.csv")
        try lines.joined(separator: "\n").write(
            to: tsv, atomically: true, encoding: .utf8
        )
        let gzip = Process()
        gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        gzip.arguments = [tsv.path]
        try gzip.run()
        gzip.waitUntilExit()
        #expect(gzip.terminationStatus == 0)
        return (tsv.path + ".gz", dir)
    }

    private static let header = [
        "code", "product_name", "brands", "quantity", "serving_size",
        "countries_tags", "completeness", "energy-kcal_100g", "proteins_100g",
        "carbohydrates_100g", "fat_100g",
    ].joined(separator: "\t")

    private func product(
        code: String, name: String, countries: String = "en:france"
    ) -> String {
        [code, name, "Marque", "500 g", "40 g", countries, "0.9",
         "370", "13", "60", "7"].joined(separator: "\t")
    }

    @Test("le build filtre, indexe et bascule atomiquement")
    func buildsSearchableCatalog() throws {
        let (gz, dir) = try makeFixture(lines: [
            Self.header,
            product(code: "1", name: "Flocons d'avoine"),
            product(code: "2", name: "Bloemkool", countries: "en:belgium"),
            product(code: "3", name: "Crème fraîche"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let offDB = dir.appending(path: "off.db").path

        let count = try CatalogBuilder.build(
            gzPath: gz, offDBPath: offDB, importedAt: "2026-08-08"
        )

        #expect(count == 2)
        // Pas de .tmp résiduel après la bascule.
        #expect(!FileManager.default.fileExists(atPath: offDB + ".tmp"))
        let catalog = try FoodCatalog(path: offDB)
        #expect(try catalog.productCount() == 2)
        #expect(try catalog.search("floc").count == 1)
        #expect(try catalog.search("creme").count == 1)
        #expect(try catalog.search("bloemkool").isEmpty)
        #expect(try catalog.importedAt() == "2026-08-08")
    }

    @Test("un en-tête invalide échoue sans toucher au catalogue existant")
    func badHeaderLeavesExistingCatalogAlone() throws {
        let (gz, dir) = try makeFixture(lines: [
            "colonne\tinconnue", "1\t2",
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let offDB = dir.appending(path: "off.db").path
        try Data("ancien catalogue".utf8).write(
            to: URL(fileURLWithPath: offDB))

        #expect(throws: (any Error).self) {
            _ = try CatalogBuilder.build(
                gzPath: gz, offDBPath: offDB, importedAt: "2026-08-08"
            )
        }
        // Le fichier courant n'a pas bougé, le .tmp a été nettoyé.
        #expect(try String(
            contentsOf: URL(fileURLWithPath: offDB), encoding: .utf8
        ) == "ancien catalogue")
        #expect(!FileManager.default.fileExists(atPath: offDB + ".tmp"))
    }

    @Test("un gz corrompu échoue proprement")
    func corruptGzFails() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let gz = dir.appending(path: "food.csv.gz")
        try Data("pas du gzip".utf8).write(to: gz)

        #expect(throws: (any Error).self) {
            _ = try CatalogBuilder.build(
                gzPath: gz.path,
                offDBPath: dir.appending(path: "off.db").path,
                importedAt: "2026-08-08"
            )
        }
    }

    @Test("la progression remonte lignes vues et produits gardés")
    func progressReportsCounts() throws {
        let (gz, dir) = try makeFixture(lines: [
            Self.header,
            product(code: "1", name: "Un"),
            product(code: "2", name: "Deux", countries: "en:spain"),
            product(code: "3", name: "Trois"),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        final class Box: @unchecked Sendable { var last: (Int, Int) = (0, 0) }
        let box = Box()
        _ = try CatalogBuilder.build(
            gzPath: gz, offDBPath: dir.appending(path: "off.db").path,
            importedAt: "2026-08-08",
            onProgress: { lines, kept in box.last = (lines, kept) }
        )
        #expect(box.last.0 == 3)
        #expect(box.last.1 == 2)
    }
}
```

Dans `Tests/FoodCatalogTests.swift`, ajouter :

```swift
    @Test("importedAt est nil sur un catalogue sans méta")
    func importedAtNilWithoutMeta() throws {
        let (catalog, path) = try makeCatalog()
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(try catalog.importedAt() == nil)
    }
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter**

`FoodCatalog.swift` (ajout) :

```swift
    /// The `imported_at` the builder stamped. nil on a catalog copied from
    /// suivinut before the meta existed, or on fixtures — a missing
    /// `catalog_meta` table is a normal state, not an error, hence the
    /// swallow: the only failure a read-only SELECT can hit here is the
    /// table's absence.
    func importedAt() throws -> String? {
        do {
            let rows = try db.rows(
                "SELECT value FROM catalog_meta WHERE key = 'imported_at'"
            )
            return rows.first?["value"]?.stringValue
        } catch {
            return nil
        }
    }
```

`CatalogBuilder.swift` :

```swift
// Cairn/Features/Nutrition/CatalogBuilder.swift
import Foundation

/// Builds `off.db` from the gzipped Open Food Facts CSV export: gunzip
/// streams into a line parser, filtered rows land in `<offDBPath>.tmp` in
/// batched transactions, FTS is built once at the end, and the finished
/// file atomically replaces the current catalog — a failure anywhere leaves
/// the existing catalog untouched.
enum CatalogBuilder {
    static let catalogURL = URL(
        string: "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
    )!

    struct BuildError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    /// One transaction per batch: per-row commits made a million-row build
    /// crawl; a single giant transaction holds the page cache hostage.
    private static let batchSize = 5_000

    static func build(
        gzPath: String, offDBPath: String, importedAt: String,
        onProgress: (@Sendable (_ linesSeen: Int, _ kept: Int) -> Void)? = nil
    ) throws -> Int {
        let tmpPath = offDBPath + ".tmp"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: tmpPath) {
            try fileManager.removeItem(atPath: tmpPath)
        }

        let gunzip = Process()
        gunzip.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        gunzip.arguments = ["-c", gzPath]
        let stdout = Pipe()
        let stderr = Pipe()
        gunzip.standardOutput = stdout
        gunzip.standardError = stderr
        try gunzip.run()

        do {
            let count = try consume(
                stdout.fileHandleForReading, into: tmpPath,
                importedAt: importedAt, onProgress: onProgress
            )
            gunzip.waitUntilExit()
            guard gunzip.terminationStatus == 0 else {
                throw BuildError(
                    message: "gunzip a échoué (code \(gunzip.terminationStatus)) — "
                        + "le fichier téléchargé est probablement corrompu."
                )
            }
            // The atomic hand-over: everything before this line only ever
            // touched the .tmp file.
            if fileManager.fileExists(atPath: offDBPath) {
                _ = try fileManager.replaceItemAt(
                    URL(fileURLWithPath: offDBPath),
                    withItemAt: URL(fileURLWithPath: tmpPath)
                )
            } else {
                try fileManager.moveItem(atPath: tmpPath, toPath: offDBPath)
            }
            return count
        } catch {
            gunzip.terminate()
            gunzip.waitUntilExit()
            try? fileManager.removeItem(atPath: tmpPath)
            throw error
        }
    }

    private static func consume(
        _ output: FileHandle, into tmpPath: String, importedAt: String,
        onProgress: (@Sendable (Int, Int) -> Void)?
    ) throws -> Int {
        let db = try SQLiteDatabase(path: tmpPath)
        try db.execute("""
            CREATE TABLE products (
                code TEXT PRIMARY KEY, name TEXT NOT NULL, brands TEXT,
                quantity TEXT, kcal_100g REAL NOT NULL,
                protein_100g REAL NOT NULL, carbs_100g REAL, fat_100g REAL,
                serving_size TEXT, completeness REAL);
            CREATE VIRTUAL TABLE products_fts USING fts5(
                name, brands, code UNINDEXED,
                tokenize = 'unicode61 remove_diacritics 2');
            CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            """)

        var columns: CatalogCSV.Columns?
        var remainder = Data()
        var linesSeen = 0
        var kept = 0
        var batchOpen = false

        func insert(_ row: CatalogCSV.Row) throws {
            if !batchOpen {
                try db.execute("BEGIN")
                batchOpen = true
            }
            _ = try db.rows(
                """
                INSERT OR REPLACE INTO products
                    (code, name, brands, quantity, kcal_100g, protein_100g,
                     carbs_100g, fat_100g, serving_size, completeness)
                VALUES (?,?,?,?,?,?,?,?,?,?)
                """,
                bindings: [
                    .text(row.code), .text(row.name),
                    row.brands.map(SQLiteDatabase.Value.text) ?? .null,
                    row.quantity.map(SQLiteDatabase.Value.text) ?? .null,
                    .real(row.kcal), .real(row.protein),
                    row.carbs.map(SQLiteDatabase.Value.real) ?? .null,
                    row.fat.map(SQLiteDatabase.Value.real) ?? .null,
                    row.servingSize.map(SQLiteDatabase.Value.text) ?? .null,
                    .real(row.completeness),
                ]
            )
            kept += 1
            if kept % batchSize == 0 {
                try db.execute("COMMIT")
                batchOpen = false
                try Task.checkCancellation()
                onProgress?(linesSeen, kept)
            }
        }

        func process(lineData: Data) throws {
            guard !lineData.isEmpty else { return }
            let line = String(decoding: lineData, as: UTF8.self)
            if let columns {
                linesSeen += 1
                if let row = CatalogCSV.row(from: line, columns: columns) {
                    try insert(row)
                }
                if linesSeen % 50_000 == 0 {
                    try Task.checkCancellation()
                    onProgress?(linesSeen, kept)
                }
            } else {
                columns = try CatalogCSV.columns(from: line)
            }
        }

        while true {
            let chunk = output.availableData
            if chunk.isEmpty { break }
            remainder.append(chunk)
            while let newline = remainder.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = remainder.subdata(
                    in: remainder.startIndex..<newline)
                remainder.removeSubrange(remainder.startIndex...newline)
                try process(lineData: lineData)
            }
        }
        if !remainder.isEmpty {
            try process(lineData: remainder)
        }
        guard columns != nil else {
            throw BuildError(message: "Export vide — aucune ligne d'en-tête.")
        }

        if batchOpen { try db.execute("COMMIT") }
        try db.execute(
            "INSERT INTO products_fts(name, brands, code) "
            + "SELECT name, COALESCE(brands, ''), code FROM products"
        )
        _ = try db.rows(
            "INSERT INTO catalog_meta(key, value) VALUES ('imported_at', ?)",
            bindings: [.text(importedAt)]
        )
        _ = try db.rows(
            "INSERT INTO catalog_meta(key, value) VALUES ('threshold', ?)",
            bindings: [.text(String(CatalogCSV.completenessThreshold))]
        )
        onProgress?(linesSeen, kept)
        let count = try db.rows("SELECT COUNT(*) AS n FROM products")
            .first?["n"]?.intValue ?? 0
        return count
    }
}
```

Note d'implémentation : `insert` avec `INSERT OR REPLACE` reproduit `catalog.insert_products` (l'export peut contenir des doublons de code). Sur l'annulation : `Task.checkCancellation()` jette `CancellationError`, le `catch` du `build` termine gunzip et nettoie le `.tmp` — le catalogue courant reste intact.

- [ ] **Step 4: Vérifier le succès** — `CatalogBuilderTests` (4 tests) + `FoodCatalogTests` complets.

- [ ] **Step 5: Commit**

```bash
git add Cairn/Features/Nutrition/CatalogBuilder.swift Cairn/Features/Nutrition/FoodCatalog.swift Tests/CatalogBuilderTests.swift Tests/FoodCatalogTests.swift
git commit -m "feat(catalogue): construction du off.db en flux avec bascule atomique"
```

---

### Task 4: CatalogUpdater et l'UI des Réglages

**Files:**
- Create: `Cairn/Features/Nutrition/CatalogUpdater.swift`
- Modify: `Cairn/Features/Nutrition/NutritionSettingsView.swift` (section Catalogue)
- Test: `Tests/CatalogUpdaterTests.swift`

**Interfaces:**
- Consumes: `FileDownloader` (Task 2), `CatalogBuilder` (Task 3), `FoodCatalog.defaultURL/openDefault/productCount/importedAt`.
- Produces :

```swift
@MainActor @Observable
final class CatalogUpdater {
    enum Phase: Equatable {
        case idle
        case downloading(megabytes: Double, totalMegabytes: Double?)
        case building(kept: Int)
        case done(count: Int)
        case failed(message: String)
    }
    private(set) var phase: Phase
    var isRunning: Bool
    /// Injectable pipeline for tests; production uses the defaults.
    init(
        download: @escaping @Sendable (
            URL, URL, @Sendable @escaping (Int64, Int64?) -> Void
        ) async throws -> Void = { url, dest, progress in
            try await FileDownloader.download(
                from: url, to: dest, onProgress: progress)
        },
        build: @escaping @Sendable (
            String, String, String, @Sendable @escaping (Int, Int) -> Void
        ) throws -> Int = { gz, db, date, progress in
            try CatalogBuilder.build(
                gzPath: gz, offDBPath: db, importedAt: date,
                onProgress: progress)
        }
    )
    func start()
    func cancel()
    /// Awaited by tests; harmless in production.
    func waitUntilFinished() async
}
```

- [ ] **Step 1: Écrire les tests qui échouent**

```swift
// Tests/CatalogUpdaterTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("CatalogUpdater")
@MainActor
struct CatalogUpdaterTests {
    @Test("le pipeline complet passe par téléchargement, build et done")
    func fullPipelineReachesDone() async {
        let updater = CatalogUpdater(
            download: { _, _, progress in progress(1_000_000, 2_000_000) },
            build: { _, _, _, progress in
                progress(10, 4)
                return 4
            }
        )
        updater.start()
        await updater.waitUntilFinished()
        #expect(updater.phase == .done(count: 4))
        #expect(!updater.isRunning)
    }

    @Test("un échec de téléchargement finit en failed avec le message")
    func downloadFailureSurfaces() async {
        let updater = CatalogUpdater(
            download: { _, _, _ in
                throw FileDownloader.DownloadError(message: "coupure réseau")
            },
            build: { _, _, _, _ in 0 }
        )
        updater.start()
        await updater.waitUntilFinished()
        guard case let .failed(message) = updater.phase else {
            Issue.record("attendu failed, obtenu \(updater.phase)")
            return
        }
        #expect(message.contains("coupure réseau"))
    }

    @Test("l'annulation retombe sur idle, pas sur failed")
    func cancellationReturnsToIdle() async {
        let updater = CatalogUpdater(
            download: { _, _, _ in
                // Un téléchargement qui ne finit jamais de lui-même.
                try await Task.sleep(for: .seconds(60))
            },
            build: { _, _, _, _ in 0 }
        )
        updater.start()
        updater.cancel()
        await updater.waitUntilFinished()
        #expect(updater.phase == .idle)
        #expect(!updater.isRunning)
    }
}
```

- [ ] **Step 2: Vérifier l'échec** — compilation.

- [ ] **Step 3: Implémenter**

```swift
// Cairn/Features/Nutrition/CatalogUpdater.swift
import Foundation

/// The state machine behind "Mettre à jour le catalogue": download the CSV
/// export (resumable), build off.db off the main actor, report progress,
/// survive cancellation. One instance per settings screen; the pipeline
/// closures are injectable so the machine is testable without network.
@MainActor @Observable
final class CatalogUpdater {
    enum Phase: Equatable {
        case idle
        case downloading(megabytes: Double, totalMegabytes: Double?)
        case building(kept: Int)
        case done(count: Int)
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle

    var isRunning: Bool {
        switch phase {
        case .downloading, .building: return true
        case .idle, .done, .failed: return false
        }
    }

    /// Kept outside Application Support/Cairn's store files: a partial
    /// download surviving for resume is cache, not user data.
    static var cacheURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Cairn/cache/food.csv.gz")
    }

    private let download: @Sendable (
        URL, URL, @Sendable @escaping (Int64, Int64?) -> Void
    ) async throws -> Void
    private let buildCatalog: @Sendable (
        String, String, String, @Sendable @escaping (Int, Int) -> Void
    ) throws -> Int
    private var task: Task<Void, Never>?

    init(
        download: @escaping @Sendable (
            URL, URL, @Sendable @escaping (Int64, Int64?) -> Void
        ) async throws -> Void = { url, destination, progress in
            try await FileDownloader.download(
                from: url, to: destination, onProgress: progress
            )
        },
        build: @escaping @Sendable (
            String, String, String, @Sendable @escaping (Int, Int) -> Void
        ) throws -> Int = { gzPath, dbPath, date, progress in
            try CatalogBuilder.build(
                gzPath: gzPath, offDBPath: dbPath, importedAt: date,
                onProgress: progress
            )
        }
    ) {
        self.download = download
        self.buildCatalog = build
    }

    func start() {
        guard !isRunning else { return }
        phase = .downloading(megabytes: 0, totalMegabytes: nil)
        let download = download
        let buildCatalog = buildCatalog
        task = Task { [weak self] in
            do {
                let cache = Self.cacheURL
                try await download(CatalogBuilder.catalogURL, cache) {
                    bytes, total in
                    Task { @MainActor [weak self] in
                        guard self?.isRunning == true else { return }
                        self?.phase = .downloading(
                            megabytes: Double(bytes) / 1_048_576,
                            totalMegabytes: total.map { Double($0) / 1_048_576 }
                        )
                    }
                }
                await MainActor.run { [weak self] in
                    self?.phase = .building(kept: 0)
                }
                let importedAt = ISO8601DateFormatter()
                    .string(from: Date()).prefix(10)
                // A task group rather than Task.detached: detached tasks do
                // NOT inherit cancellation, and « Annuler » must reach the
                // builder's Task.checkCancellation().
                let count = try await withThrowingTaskGroup(of: Int.self) { group in
                    group.addTask(priority: .utility) {
                        try buildCatalog(
                            cache.path, FoodCatalog.defaultURL.path,
                            String(importedAt)
                        ) { _, kept in
                            Task { @MainActor [weak self] in
                                guard self?.isRunning == true else { return }
                                self?.phase = .building(kept: kept)
                            }
                        }
                    }
                    guard let result = try await group.next() else {
                        throw CancellationError()
                    }
                    return result
                }
                // The gz cache only matters for resuming; a finished build
                // has no use for a gigabyte on disk.
                try? FileManager.default.removeItem(at: cache)
                await MainActor.run { [weak self] in
                    self?.phase = .done(count: count)
                }
            } catch is CancellationError {
                // The .part stays on disk: cancelling is pausing.
                await MainActor.run { [weak self] in
                    self?.phase = .idle
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.phase = .failed(
                        message: "La mise à jour a échoué : \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    func waitUntilFinished() async {
        await task?.value
    }
}
```

(Le groupe structurel du listing ci-dessus est délibéré : les tâches d'un groupe héritent de l'annulation du Task englobant, ce qu'un `Task.detached` ne fait pas — `CatalogBuilder` voit l'annulation via `Task.checkCancellation()` entre les lots.)

- [ ] **Step 4: UI des Réglages**

Dans `NutritionSettingsView.swift` :

1. État : `@State private var updater = CatalogUpdater()` et `@State private var catalogRefresh = 0` (incrémenté à chaque `.done` pour recalculer le statut).

2. Remplacer la section Catalogue :

```swift
            Section("Catalogue") {
                Text(catalogStatus)
                    .foregroundStyle(.secondary)
                    .id(catalogRefresh)
                switch updater.phase {
                case .downloading(let megabytes, let total):
                    HStack {
                        ProgressView(
                            value: total.map { min(megabytes / $0, 1) } ?? 0
                        )
                        Text(downloadLabel(megabytes: megabytes, total: total))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Annuler") { updater.cancel() }
                    }
                case .building(let kept):
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Construction… \(kept) produits retenus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Annuler") { updater.cancel() }
                    }
                case .failed(let message):
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                    Button("Mettre à jour le catalogue") { updater.start() }
                case .done, .idle:
                    Button("Mettre à jour le catalogue") { updater.start() }
                }
            }
            .onChange(of: updater.phase) { _, newPhase in
                if case .done = newPhase { catalogRefresh += 1 }
            }
```

3. Aide de libellé :

```swift
    private func downloadLabel(megabytes: Double, total: Double?) -> String {
        let done = Format.typedNumber(megabytes)
        guard let total else { return "\(done) Mo téléchargés" }
        return "\(done) / \(Format.typedNumber(total)) Mo"
    }
```

4. `catalogStatus` s'enrichit de la date (nécessite `importedAt()` de la Task 3) :

```swift
    private var catalogStatus: String {
        guard let catalog = FoodCatalog.openDefault(),
              let count = try? catalog.productCount()
        else {
            return "Aucun catalogue — l'import suivinut en copie un, "
                + "ou téléchargez-le ci-dessous."
        }
        if let importedAt = try? catalog.importedAt(), let importedAt {
            return "\(count) produits Open Food Facts — importé le \(importedAt)."
        }
        return "\(count) produits Open Food Facts."
    }
```

(Attention au double optionnel de `try? catalog.importedAt()` : `if let importedAt = try? ..., let importedAt` le déplie en deux temps.)

- [ ] **Step 5: Vérifier le succès**

Run: `xcodegen generate`, build, `-only-testing:CairnTests/CatalogUpdaterTests` (3 tests), puis suite complète.
Expected: tout vert.

- [ ] **Step 6: Vérification visuelle**

En mode démo : Réglages → Nutrition → « Mettre à jour le catalogue ». Le téléchargement réel fait ~1 Go : vérifier que la progression s'affiche et qu'« Annuler » retombe en idle **sans** casser le catalogue courant (la recherche doit continuer de fonctionner). Laisser l'utilisateur décider s'il va au bout du téléchargement.

- [ ] **Step 7: Commit**

```bash
git add Cairn/Features/Nutrition/CatalogUpdater.swift Cairn/Features/Nutrition/NutritionSettingsView.swift Tests/CatalogUpdaterTests.swift
git commit -m "feat(catalogue): mise à jour du catalogue avec progression et annulation"
```

---

## Après cette phase

Phase 6 (plan séparé, dernier de la spec) : clavier (`gn`/`gp` dans `VimKeyBuffer` + aide), colonne détail d'Alimentation (mini-calendrier + panneau stats — `WeightStats.loggingStreak` est prêt), drag de réordonnancement (spec §5), message visible quand la recherche échoue (spec §9), volet détail activité résiduel, et les reliquats mineurs des ledgers de phases 2-5 (formatteur signé 2 décimales, confirmation d'écrasement de pesée, extraction du flux d'import dupliqué, etc.).
