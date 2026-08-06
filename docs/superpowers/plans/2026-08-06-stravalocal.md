# StravaLocal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une application macOS native qui garde une copie locale complète des données Strava de l'utilisateur et permet de les consulter, filtrer et explorer sur une carte, hors ligne.

**Architecture:** Quatre couches à dépendance unidirectionnelle — `Geo` (pur calcul, aucune dépendance), `Strava` (réseau + DTOs, ne connaît pas SwiftData), `Model` (SwiftData), `Sync` (l'`ImportMapper` est le seul pont DTO→modèle, le `SyncEngine` est un actor). Les `Features` SwiftUI consomment le modèle via `@Query`. Les performances reposent sur deux données dérivées portées par `Activity` : une bounding box en colonnes indexées, et une trace simplifiée en blob binaire — elles permettent d'afficher et de filtrer tout l'historique sans jamais charger les streams.

**Tech Stack:** Swift 6.3 (mode langage 6), SwiftUI, SwiftData, MapKit, Swift Charts, Network.framework (listener loopback OAuth), Security.framework (Keychain), Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-06-stravalocal-design.md`

## Global Constraints

- Cible de déploiement : **macOS 15.0**.
- `SWIFT_VERSION = 6.0` (mode langage Swift 6, strict concurrency). Tout type traversant une frontière de concurrence doit être `Sendable`.
- Signature : `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = 89SHJR3N3S`, `CODE_SIGN_IDENTITY = "Apple Development"`. Identité stable et obligatoire : elle conditionne la persistance des ACL Keychain entre deux builds.
- **App non sandboxée** : `com.apple.security.app-sandbox = false`. Le store SwiftData vit dans `~/Library/Application Support/StravaLocal/StravaLocal.store`.
- Aucun package externe. Uniquement les frameworks Apple.
- `StravaLocal.xcodeproj` n'est **jamais** committé — il est régénéré par `xcodegen generate`. Seul `project.yml` est versionné.
- **Après toute création ou suppression de fichier source, lancer `xcodegen generate` avant de compiler.** XcodeGen énumère les fichiers au moment de la génération : `project.yml` n'a pas à changer quand on ajoute un fichier dans `StravaLocal/` ou `Tests/`, mais le `.pbxproj` doit être régénéré pour que le nouveau fichier entre dans la cible. Oublier cette étape produit une erreur « cannot find X in scope » trompeuse.
- Aucun secret dans le dépôt. Client ID, Client Secret et jetons vivent exclusivement dans le Keychain.
- Framework de test : **Swift Testing** (`import Testing`, `@Test`, `#expect`), pas XCTest.
- Commande de test unique pour tout le plan :
  `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
- Langue : identifiants et commentaires en anglais, textes affichés à l'utilisateur en français.
- Aucun style visuel custom : composants SwiftUI/AppKit standard uniquement, pas de couleur, police ni métrique codée en dur.

## File Structure

| Fichier | Responsabilité |
|---|---|
| `project.yml` | Définition XcodeGen : cibles app + tests, réglages de build, signature |
| `StravaLocal/StravaLocal.entitlements` | Entitlements (sandbox désactivé) |
| `StravaLocal/App/StravaLocalApp.swift` | Point d'entrée, `ModelContainer`, scènes (fenêtre + Settings) |
| `StravaLocal/App/RootView.swift` | `NavigationSplitView`, état de sélection de la sidebar |
| `StravaLocal/App/AppEnvironment.swift` | Assemblage des dépendances (client, engine) injecté dans l'environnement |
| `StravaLocal/Geo/Coordinate.swift` | `Coordinate` — paire lat/lon `Sendable`, conversions CoreLocation |
| `StravaLocal/Geo/Polyline.swift` | Décodage/encodage du format Google Encoded Polyline de Strava |
| `StravaLocal/Geo/TrackBlob.swift` | Packing binaire des tableaux de coordonnées et de scalaires |
| `StravaLocal/Geo/Simplify.swift` | Simplification Douglas-Peucker |
| `StravaLocal/Geo/BoundingBox.swift` | Calcul de bbox, intersection, appartenance d'un point |
| `StravaLocal/Model/Activity.swift` | Modèle SwiftData `Activity` + index + `SportType` |
| `StravaLocal/Model/ActivityStreams.swift` | Modèle SwiftData des streams en blobs |
| `StravaLocal/Model/Athlete.swift` | Modèle SwiftData `Athlete` |
| `StravaLocal/Model/Lap.swift` | Modèle SwiftData `Lap` |
| `StravaLocal/Model/Gear.swift` | Modèle SwiftData `Gear` |
| `StravaLocal/Model/SyncState.swift` | Modèle SwiftData de l'état de synchro (curseur, file d'attente) |
| `StravaLocal/Model/ModelContainer+App.swift` | Construction du container, emplacement du store |
| `StravaLocal/Strava/StravaDTO.swift` | DTOs `Decodable` des réponses Strava |
| `StravaLocal/Strava/StravaError.swift` | Erreurs typées du client |
| `StravaLocal/Strava/TokenStore.swift` | Lecture/écriture Keychain des credentials et jetons |
| `StravaLocal/Strava/OAuthFlow.swift` | Listener loopback + ouverture navigateur + échange du code |
| `StravaLocal/Strava/RateLimiter.swift` | Suivi du quota via en-têtes, décision d'attente, backoff |
| `StravaLocal/Strava/StravaClient.swift` | Appels d'API, refresh de jeton, application du rate limiter |
| `StravaLocal/Sync/ImportMapper.swift` | DTO → modèles SwiftData, idempotent |
| `StravaLocal/Sync/SyncEngine.swift` | Actor : phase A (résumés), phase B (streams), reprise |
| `StravaLocal/Sync/SyncProgress.swift` | État de progression observable pour l'UI |
| `StravaLocal/Features/ActivityList/ActivityFilter.swift` | Valeurs de filtre + construction du `Predicate` |
| `StravaLocal/Features/ActivityList/ActivityListView.swift` | `Table` triable + `.searchable` |
| `StravaLocal/Features/ActivityList/FilterBar.swift` | Contrôles de filtre |
| `StravaLocal/Features/ActivityDetail/ActivityDetailView.swift` | Carte + stats + graphes + laps |
| `StravaLocal/Features/ActivityDetail/ActivityMapView.swift` | `NSViewRepresentable` d'une trace unique |
| `StravaLocal/Features/ActivityDetail/StreamCharts.swift` | Graphes Swift Charts avec sous-échantillonnage |
| `StravaLocal/Features/GlobalMap/GlobalMapView.swift` | `NSViewRepresentable`, `MKMultiPolyline` |
| `StravaLocal/Features/GlobalMap/SelectionOverlayView.swift` | `NSView` de dessin du rectangle de sélection |
| `StravaLocal/Features/Settings/SettingsScene.swift` | Onglets Compte et Synchronisation |
| `StravaLocal/Features/Shared/Formatters.swift` | Formatage distance, durée, allure, dates |
| `Tests/GeoTests.swift` | Polyline, TrackBlob, Simplify, BoundingBox |
| `Tests/ImportMapperTests.swift` | Mapping et idempotence sur fixtures |
| `Tests/RateLimiterTests.swift` | Parsing d'en-têtes, attente, backoff |
| `Tests/Fixtures/*.json` | Réponses Strava réelles anonymisées |

---

### Task 1: Squelette du projet

Deliverable : `xcodegen generate` produit un projet qui compile, lance une fenêtre vide, et exécute une suite de tests verte.

**Files:**
- Create: `project.yml`
- Create: `StravaLocal/StravaLocal.entitlements`
- Create: `StravaLocal/App/StravaLocalApp.swift`
- Create: `Tests/GeoTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Consumes: rien.
- Produces: cible app `StravaLocal`, cible de test `StravaLocalTests`, scheme `StravaLocal`. Toute tâche ultérieure ajoute simplement des fichiers sous `StravaLocal/` ou `Tests/` — les sources sont synchronisées par dossier, aucun fichier à déclarer.

- [ ] **Step 1: Écrire `.gitignore`**

Le fichier existe peut-être déjà avec des lignes supplémentaires (par exemple `.superpowers/`) : **conserver ce qui y est** et compléter avec les lignes manquantes.

```gitignore
*.xcodeproj
*.xcworkspace
.DS_Store
build/
DerivedData/
xcuserdata/
```

- [ ] **Step 2: Écrire `project.yml`**

```yaml
name: StravaLocal
options:
  bundleIdPrefix: com.florianmaisonnial
  deploymentTarget:
    macOS: "15.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Automatic
    DEVELOPMENT_TEAM: 89SHJR3N3S
    CODE_SIGN_IDENTITY: "Apple Development"
    ENABLE_USER_SCRIPT_SANDBOXING: YES
targets:
  StravaLocal:
    type: application
    platform: macOS
    sources:
      - path: StravaLocal
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.florianmaisonnial.StravaLocal
        PRODUCT_NAME: StravaLocal
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.healthcare-fitness
        INFOPLIST_KEY_NSHumanReadableCopyright: ""
        CODE_SIGN_ENTITLEMENTS: StravaLocal/StravaLocal.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        SWIFT_EMIT_LOC_STRINGS: YES
  StravaLocalTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
    dependencies:
      - target: StravaLocal
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.florianmaisonnial.StravaLocalTests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  StravaLocal:
    build:
      targets:
        StravaLocal: all
        StravaLocalTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      gatherCoverageData: false
      targets:
        - StravaLocalTests
```

- [ ] **Step 3: Écrire les entitlements (sandbox désactivé)**

`StravaLocal/StravaLocal.entitlements` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
</dict>
</plist>
```

- [ ] **Step 4: Écrire le point d'entrée minimal**

`StravaLocal/App/StravaLocalApp.swift` :

```swift
import SwiftUI

@main
struct StravaLocalApp: App {
    var body: some Scene {
        WindowGroup {
            Text("StravaLocal")
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
```

- [ ] **Step 5: Écrire un test bidon qui prouve que la cible de test tourne**

`Tests/GeoTests.swift` :

```swift
import Testing

@Suite("Geo")
struct GeoTests {
    @Test("la cible de test est câblée")
    func harnessRuns() {
        #expect(1 + 1 == 2)
    }
}
```

- [ ] **Step 6: Générer le projet**

Run: `cd /Users/florian/dev/stravapp && xcodegen generate`
Expected: `Created project at StravaLocal.xcodeproj`

- [ ] **Step 7: Lancer les tests**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`. Si la signature échoue, vérifier que `DEVELOPMENT_TEAM` vaut bien `89SHJR3N3S`.

- [ ] **Step 8: Vérifier que l'app se lance**

Run: `xcodebuild -project StravaLocal.xcodeproj -scheme StravaLocal -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet build && open build/Build/Products/Debug/StravaLocal.app`
Expected: une fenêtre affichant « StravaLocal ». La fermer.

- [ ] **Step 9: Commit**

```bash
git add .gitignore project.yml StravaLocal Tests
git commit -m "chore: squelette du projet macOS (XcodeGen, app vide, harness de test)"
```

---

### Task 2: Décodage de polyline

Deliverable : le format encodé que renvoie Strava devient un tableau de coordonnées.

**Files:**
- Create: `StravaLocal/Geo/Coordinate.swift`
- Create: `StravaLocal/Geo/Polyline.swift`
- Modify: `Tests/GeoTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces:
  - `struct Coordinate: Sendable, Hashable { var latitude: Double; var longitude: Double; init(latitude: Double, longitude: Double); var clLocation: CLLocationCoordinate2D; init(_ cl: CLLocationCoordinate2D) }`
  - `enum Polyline { static func decode(_ encoded: String) -> [Coordinate]; static func encode(_ coordinates: [Coordinate]) -> String }`

- [ ] **Step 1: Écrire les tests d'abord**

Remplacer le contenu de `Tests/GeoTests.swift` par :

```swift
import Testing
import CoreLocation
@testable import StravaLocal

@Suite("Polyline")
struct PolylineTests {
    @Test("décode le vecteur de référence Google")
    func decodesReferenceVector() {
        let result = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(result.count == 3)
        #expect(abs(result[0].latitude - 38.5) < 0.00001)
        #expect(abs(result[0].longitude - (-120.2)) < 0.00001)
        #expect(abs(result[1].latitude - 40.7) < 0.00001)
        #expect(abs(result[1].longitude - (-120.95)) < 0.00001)
        #expect(abs(result[2].latitude - 43.252) < 0.00001)
        #expect(abs(result[2].longitude - (-126.453)) < 0.00001)
    }

    @Test("une chaîne vide donne un tableau vide")
    func decodesEmpty() {
        #expect(Polyline.decode("").isEmpty)
    }

    @Test("un encodage suivi d'un décodage préserve les coordonnées à 1e-5")
    func roundTrips() {
        let original = [
            Coordinate(latitude: 45.7640, longitude: 4.8357),
            Coordinate(latitude: 45.7650, longitude: 4.8400),
            Coordinate(latitude: 45.7700, longitude: 4.8500),
        ]
        let decoded = Polyline.decode(Polyline.encode(original))
        #expect(decoded.count == original.count)
        for (a, b) in zip(original, decoded) {
            #expect(abs(a.latitude - b.latitude) < 0.00001)
            #expect(abs(a.longitude - b.longitude) < 0.00001)
        }
    }

    @Test("une chaîne tronquée ne plante pas")
    func toleratesTruncatedInput() {
        _ = Polyline.decode("_p~iF~ps|U_ulLnnq")
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'Polyline' in scope ».

- [ ] **Step 3: Écrire `Coordinate`**

```swift
import CoreLocation

/// A latitude/longitude pair. Deliberately independent of CoreLocation so the
/// Geo layer stays testable and Sendable.
struct Coordinate: Sendable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ cl: CLLocationCoordinate2D) {
        self.init(latitude: cl.latitude, longitude: cl.longitude)
    }

    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
```

- [ ] **Step 4: Écrire `Polyline`**

```swift
/// Google Encoded Polyline Algorithm Format, precision 5 — the format Strava
/// uses for `map.summary_polyline`.
enum Polyline {
    static func decode(_ encoded: String) -> [Coordinate] {
        var coordinates: [Coordinate] = []
        var index = encoded.startIndex
        var lat = 0
        var lon = 0

        while index < encoded.endIndex {
            guard let dLat = nextValue(in: encoded, from: &index) else { break }
            guard let dLon = nextValue(in: encoded, from: &index) else { break }
            lat += dLat
            lon += dLon
            coordinates.append(
                Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5)
            )
        }
        return coordinates
    }

    static func encode(_ coordinates: [Coordinate]) -> String {
        var output = ""
        var previousLat = 0
        var previousLon = 0

        for coordinate in coordinates {
            let lat = Int((coordinate.latitude * 1e5).rounded())
            let lon = Int((coordinate.longitude * 1e5).rounded())
            append(lat - previousLat, to: &output)
            append(lon - previousLon, to: &output)
            previousLat = lat
            previousLon = lon
        }
        return output
    }

    /// Reads one varint-style chunk sequence. Returns nil on truncated input.
    private static func nextValue(
        in encoded: String, from index: inout String.Index
    ) -> Int? {
        var result = 0
        var shift = 0
        var byte = 0

        repeat {
            guard index < encoded.endIndex else { return nil }
            guard let ascii = encoded[index].asciiValue else { return nil }
            byte = Int(ascii) - 63
            index = encoded.index(after: index)
            result |= (byte & 0x1F) << shift
            shift += 5
        } while byte >= 0x20

        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }

    private static func append(_ value: Int, to output: inout String) {
        var zigzag = value < 0 ? ~(value << 1) : (value << 1)
        while zigzag >= 0x20 {
            output.append(Character(UnicodeScalar(UInt8((0x20 | (zigzag & 0x1F)) + 63))))
            zigzag >>= 5
        }
        output.append(Character(UnicodeScalar(UInt8(zigzag + 63))))
    }
}
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add StravaLocal/Geo Tests/GeoTests.swift
git commit -m "feat(geo): décodage et encodage de polylines Strava"
```

---

### Task 3: Packing binaire des streams

Deliverable : un tableau de coordonnées ou de scalaires se convertit en `Data` compact et revient à l'identique.

**Files:**
- Create: `StravaLocal/Geo/TrackBlob.swift`
- Create: `Tests/TrackBlobTests.swift`

**Interfaces:**
- Consumes: `Coordinate` (Task 2).
- Produces:
  - `enum TrackBlob { static func encode(coordinates: [Coordinate]) -> Data; static func decodeCoordinates(_ data: Data) -> [Coordinate]; static func encode(scalars: [Float]) -> Data; static func decodeScalars(_ data: Data) -> [Float]; static func encode(times: [Int32]) -> Data; static func decodeTimes(_ data: Data) -> [Int32] }`

Format : little-endian, sans en-tête. Coordonnées = paires de `Float64` (lat, lon). Scalaires = `Float32`. Temps = `Int32`. L'absence d'en-tête est délibérée : le type est connu du champ qui porte le blob, et le décodage se réduit à une réinterprétation mémoire.

- [ ] **Step 1: Écrire les tests d'abord**

`Tests/TrackBlobTests.swift` :

```swift
import Testing
import Foundation
@testable import StravaLocal

@Suite("TrackBlob")
struct TrackBlobTests {
    @Test("les coordonnées font un aller-retour exact")
    func coordinatesRoundTrip() {
        let coordinates = [
            Coordinate(latitude: 45.764043, longitude: 4.835659),
            Coordinate(latitude: -33.868820, longitude: 151.209290),
            Coordinate(latitude: 0, longitude: 0),
        ]
        let decoded = TrackBlob.decodeCoordinates(TrackBlob.encode(coordinates: coordinates))
        #expect(decoded == coordinates)
    }

    @Test("un blob de coordonnées fait 16 octets par point")
    func coordinateBlobIsCompact() {
        let coordinates = Array(
            repeating: Coordinate(latitude: 1, longitude: 2), count: 100
        )
        #expect(TrackBlob.encode(coordinates: coordinates).count == 1600)
    }

    @Test("les scalaires font un aller-retour exact")
    func scalarsRoundTrip() {
        let values: [Float] = [0, 1.5, -20.25, 1234.5]
        #expect(TrackBlob.decodeScalars(TrackBlob.encode(scalars: values)) == values)
    }

    @Test("les temps font un aller-retour exact")
    func timesRoundTrip() {
        let values: [Int32] = [0, 1, 60, 3600, 86_399]
        #expect(TrackBlob.decodeTimes(TrackBlob.encode(times: values)) == values)
    }

    @Test("un blob vide donne un tableau vide")
    func emptyBlob() {
        #expect(TrackBlob.decodeCoordinates(Data()).isEmpty)
        #expect(TrackBlob.decodeScalars(Data()).isEmpty)
    }

    @Test("un blob de taille non multiple ignore la queue incomplète")
    func truncatedBlobIsTolerated() {
        var data = TrackBlob.encode(coordinates: [Coordinate(latitude: 1, longitude: 2)])
        data.append(contentsOf: [0x01, 0x02, 0x03])
        #expect(TrackBlob.decodeCoordinates(data).count == 1)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'TrackBlob' in scope ».

- [ ] **Step 3: Écrire `TrackBlob`**

```swift
import Foundation

/// Packs stream arrays into headerless little-endian binary blobs.
///
/// Streams are never queried, only read whole, so a compact packed
/// representation beats both JSON and a per-point table. The element type is
/// implied by the property holding the blob, which is why no header is needed.
enum TrackBlob {
    static func encode(coordinates: [Coordinate]) -> Data {
        var flat = [Double]()
        flat.reserveCapacity(coordinates.count * 2)
        for coordinate in coordinates {
            flat.append(coordinate.latitude)
            flat.append(coordinate.longitude)
        }
        return pack(flat)
    }

    static func decodeCoordinates(_ data: Data) -> [Coordinate] {
        let flat: [Double] = unpack(data)
        var coordinates = [Coordinate]()
        coordinates.reserveCapacity(flat.count / 2)
        var index = 0
        while index + 1 < flat.count {
            coordinates.append(
                Coordinate(latitude: flat[index], longitude: flat[index + 1])
            )
            index += 2
        }
        return coordinates
    }

    static func encode(scalars: [Float]) -> Data { pack(scalars) }
    static func decodeScalars(_ data: Data) -> [Float] { unpack(data) }
    static func encode(times: [Int32]) -> Data { pack(times) }
    static func decodeTimes(_ data: Data) -> [Int32] { unpack(data) }

    private static func pack<T>(_ values: [T]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Trailing bytes that don't form a whole element are dropped rather than
    /// trapping, so a corrupted store degrades instead of crashing.
    ///
    /// Reads are unaligned on purpose: `Data.withUnsafeBytes` makes no
    /// alignment promise, and a `Data` that is a slice of a larger buffer can
    /// start at any byte offset — which is exactly what reading a blob column
    /// back out of the store can hand us.
    private static func unpack<T>(_ data: Data) -> [T] {
        let stride = MemoryLayout<T>.stride
        let count = data.count / stride
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { raw in
            (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * stride, as: T.self) }
        }
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Geo/TrackBlob.swift Tests/TrackBlobTests.swift
git commit -m "feat(geo): packing binaire des streams"
```

---

### Task 4: Simplification et bounding box

Deliverable : une trace brute donne une trace allégée et une bounding box exploitables comme données dérivées d'`Activity`.

**Files:**
- Create: `StravaLocal/Geo/Simplify.swift`
- Create: `StravaLocal/Geo/BoundingBox.swift`
- Create: `Tests/SimplifyTests.swift`
- Create: `Tests/BoundingBoxTests.swift`

**Interfaces:**
- Consumes: `Coordinate` (Task 2).
- Produces:
  - `enum Simplify { static let defaultToleranceMeters: Double (= 15); static func douglasPeucker(_ coordinates: [Coordinate], toleranceMeters: Double = defaultToleranceMeters) -> [Coordinate]; static func downsample<T>(_ values: [T], to maxCount: Int) -> [T] }`
  - `struct BoundingBox: Sendable, Equatable { var minLat: Double; var maxLat: Double; var minLon: Double; var maxLon: Double; init?(coordinates: [Coordinate]); init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double); static let world: BoundingBox; func intersects(_ other: BoundingBox) -> Bool; func contains(_ coordinate: Coordinate) -> Bool; func containsAnyPoint(of coordinates: [Coordinate]) -> Bool }`

`downsample` sert au sous-échantillonnage des graphes (Task 15) : il vit ici parce que c'est la même famille de réduction de série.

- [ ] **Step 1: Écrire les tests de simplification**

`Tests/SimplifyTests.swift` :

```swift
import Testing
@testable import StravaLocal

@Suite("Simplify")
struct SimplifyTests {
    @Test("les extrémités sont toujours préservées")
    func keepsEndpoints() {
        let line = (0..<50).map {
            Coordinate(latitude: 45.0 + Double($0) * 0.001, longitude: 4.0)
        }
        let simplified = Simplify.douglasPeucker(line, toleranceMeters: 15)
        #expect(simplified.first == line.first)
        #expect(simplified.last == line.last)
    }

    @Test("une ligne droite se réduit à deux points")
    func collapsesStraightLine() {
        let line = (0..<100).map {
            Coordinate(latitude: 45.0 + Double($0) * 0.0005, longitude: 4.0)
        }
        #expect(Simplify.douglasPeucker(line, toleranceMeters: 15).count == 2)
    }

    @Test("un détour supérieur à la tolérance est conservé")
    func keepsSignificantDetour() {
        let line = [
            Coordinate(latitude: 45.0, longitude: 4.0),
            Coordinate(latitude: 45.0, longitude: 4.01),
            Coordinate(latitude: 45.0, longitude: 4.02),
        ]
        var withDetour = line
        // ~1 km d'écart, très au-delà de 15 m
        withDetour[1] = Coordinate(latitude: 45.009, longitude: 4.01)
        #expect(Simplify.douglasPeucker(withDetour, toleranceMeters: 15).count == 3)
    }

    @Test("moins de trois points est retourné tel quel")
    func passesThroughShortInput() {
        let two = [
            Coordinate(latitude: 1, longitude: 2), Coordinate(latitude: 3, longitude: 4),
        ]
        #expect(Simplify.douglasPeucker(two) == two)
        #expect(Simplify.douglasPeucker([]).isEmpty)
    }

    @Test("le sous-échantillonnage garde les bornes et respecte le plafond")
    func downsampleKeepsBounds() {
        let values = Array(0..<1000)
        let reduced = Simplify.downsample(values, to: 100)
        #expect(reduced.count <= 100)
        #expect(reduced.first == 0)
        #expect(reduced.last == 999)
    }

    @Test("le sous-échantillonnage ne touche pas une série déjà courte")
    func downsampleShortInput() {
        let values = [1, 2, 3]
        #expect(Simplify.downsample(values, to: 100) == values)
    }
}
```

- [ ] **Step 2: Écrire les tests de bounding box**

`Tests/BoundingBoxTests.swift` :

```swift
import Testing
@testable import StravaLocal

@Suite("BoundingBox")
struct BoundingBoxTests {
    private let lyon = [
        Coordinate(latitude: 45.75, longitude: 4.83),
        Coordinate(latitude: 45.80, longitude: 4.90),
        Coordinate(latitude: 45.70, longitude: 4.85),
    ]

    @Test("englobe tous les points")
    func computesExtent() {
        let box = BoundingBox(coordinates: lyon)
        #expect(box?.minLat == 45.70)
        #expect(box?.maxLat == 45.80)
        #expect(box?.minLon == 4.83)
        #expect(box?.maxLon == 4.90)
    }

    @Test("un tableau vide ne donne pas de boîte")
    func rejectsEmptyInput() {
        #expect(BoundingBox(coordinates: []) == nil)
    }

    @Test("deux boîtes qui se chevauchent s'intersectent")
    func detectsOverlap() {
        let a = BoundingBox(minLat: 45, maxLat: 46, minLon: 4, maxLon: 5)
        let b = BoundingBox(minLat: 45.5, maxLat: 47, minLon: 4.5, maxLon: 6)
        #expect(a.intersects(b))
        #expect(b.intersects(a))
    }

    @Test("deux boîtes disjointes ne s'intersectent pas")
    func detectsDisjoint() {
        let a = BoundingBox(minLat: 45, maxLat: 46, minLon: 4, maxLon: 5)
        let b = BoundingBox(minLat: 48, maxLat: 49, minLon: 2, maxLon: 3)
        #expect(!a.intersects(b))
    }

    @Test("deux boîtes qui se touchent par un bord s'intersectent")
    func touchingEdgesCount() {
        let a = BoundingBox(minLat: 45, maxLat: 46, minLon: 4, maxLon: 5)
        let b = BoundingBox(minLat: 46, maxLat: 47, minLon: 4, maxLon: 5)
        #expect(a.intersects(b))
    }

    @Test("l'appartenance d'un point est testée bord inclus")
    func containsPoint() {
        let box = BoundingBox(minLat: 45, maxLat: 46, minLon: 4, maxLon: 5)
        #expect(box.contains(Coordinate(latitude: 45.5, longitude: 4.5)))
        #expect(box.contains(Coordinate(latitude: 45, longitude: 4)))
        #expect(!box.contains(Coordinate(latitude: 44.9, longitude: 4.5)))
    }

    @Test("containsAnyPoint distingue une trace qui traverse d'une trace hors zone")
    func containsAnyPointOfTrack() {
        let box = BoundingBox(minLat: 45.79, maxLat: 45.81, minLon: 4.89, maxLon: 4.91)
        #expect(box.containsAnyPoint(of: lyon))
        let elsewhere = [Coordinate(latitude: 48.85, longitude: 2.35)]
        #expect(!box.containsAnyPoint(of: elsewhere))
    }

    @Test("la boîte monde contient n'importe quoi")
    func worldContainsEverything() {
        #expect(BoundingBox.world.contains(Coordinate(latitude: -33.87, longitude: 151.2)))
    }
}
```

- [ ] **Step 3: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'Simplify' in scope ».

- [ ] **Step 4: Écrire `BoundingBox`**

```swift
import Foundation

/// An axis-aligned lat/lon extent. Stored on `Activity` as four indexed columns
/// so the database can pre-filter a geographic query without touching tracks.
struct BoundingBox: Sendable, Equatable {
    var minLat: Double
    var maxLat: Double
    var minLon: Double
    var maxLon: Double

    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    init?(coordinates: [Coordinate]) {
        guard let first = coordinates.first else { return nil }
        var box = BoundingBox(
            minLat: first.latitude, maxLat: first.latitude,
            minLon: first.longitude, maxLon: first.longitude
        )
        for coordinate in coordinates.dropFirst() {
            box.minLat = min(box.minLat, coordinate.latitude)
            box.maxLat = max(box.maxLat, coordinate.latitude)
            box.minLon = min(box.minLon, coordinate.longitude)
            box.maxLon = max(box.maxLon, coordinate.longitude)
        }
        self = box
    }

    static let world = BoundingBox(
        minLat: -90, maxLat: 90, minLon: -180, maxLon: 180
    )

    func intersects(_ other: BoundingBox) -> Bool {
        minLat <= other.maxLat && maxLat >= other.minLat
            && minLon <= other.maxLon && maxLon >= other.minLon
    }

    func contains(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= minLat && coordinate.latitude <= maxLat
            && coordinate.longitude >= minLon && coordinate.longitude <= maxLon
    }

    func containsAnyPoint(of coordinates: [Coordinate]) -> Bool {
        coordinates.contains(where: contains)
    }
}
```

- [ ] **Step 5: Écrire `Simplify`**

```swift
import Foundation

/// Ramer–Douglas–Peucker line simplification, plus series downsampling.
enum Simplify {
    /// 15 m keeps city streets distinguishable while cutting a typical ride
    /// track by an order of magnitude.
    static let defaultToleranceMeters: Double = 15

    static func douglasPeucker(
        _ coordinates: [Coordinate],
        toleranceMeters: Double = defaultToleranceMeters
    ) -> [Coordinate] {
        // A negative tolerance makes `recurse` re-enter itself with identical
        // arguments on a run of duplicate points, so reject it at the door.
        precondition(toleranceMeters >= 0, "tolerance must not be negative")
        guard coordinates.count > 2 else { return coordinates }
        var keep = [Bool](repeating: false, count: coordinates.count)
        keep[0] = true
        keep[coordinates.count - 1] = true
        recurse(coordinates, 0, coordinates.count - 1, toleranceMeters, &keep)
        return zip(coordinates, keep).compactMap { $1 ? $0 : nil }
    }

    private static func recurse(
        _ points: [Coordinate], _ first: Int, _ last: Int,
        _ tolerance: Double, _ keep: inout [Bool]
    ) {
        guard last > first + 1 else { return }
        var worstIndex = first
        var worstDistance = 0.0

        for index in (first + 1)..<last {
            let distance = perpendicularDistance(
                points[index], from: points[first], to: points[last]
            )
            if distance > worstDistance {
                worstDistance = distance
                worstIndex = index
            }
        }

        guard worstDistance > tolerance else { return }
        keep[worstIndex] = true
        recurse(points, first, worstIndex, tolerance, &keep)
        recurse(points, worstIndex, last, tolerance, &keep)
    }

    /// Distance in metres from `point` to segment `start`–`end`, using an
    /// equirectangular projection. Accurate enough at track scale and far
    /// cheaper than a geodesic computation run millions of times.
    private static func perpendicularDistance(
        _ point: Coordinate, from start: Coordinate, to end: Coordinate
    ) -> Double {
        let metresPerDegree = 111_320.0
        let scale = cos(point.latitude * .pi / 180)

        let px = (point.longitude - start.longitude) * metresPerDegree * scale
        let py = (point.latitude - start.latitude) * metresPerDegree
        let ex = (end.longitude - start.longitude) * metresPerDegree * scale
        let ey = (end.latitude - start.latitude) * metresPerDegree

        let lengthSquared = ex * ex + ey * ey
        guard lengthSquared > 0 else { return (px * px + py * py).squareRoot() }

        let t = max(0, min(1, (px * ex + py * ey) / lengthSquared))
        let dx = px - t * ex
        let dy = py - t * ey
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Evenly thins a series to at most `maxCount` elements, always keeping the
    /// first and last. Used to keep charts responsive on long activities.
    static func downsample<T>(_ values: [T], to maxCount: Int) -> [T] {
        guard maxCount >= 2, values.count > maxCount else { return values }
        let spacing = Double(values.count - 1) / Double(maxCount - 1)
        var result = [T]()
        result.reserveCapacity(maxCount)
        for step in 0..<maxCount {
            result.append(values[Int((Double(step) * spacing).rounded())])
        }
        return result
    }
}
```

- [ ] **Step 6: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add StravaLocal/Geo Tests/SimplifyTests.swift Tests/BoundingBoxTests.swift
git commit -m "feat(geo): simplification Douglas-Peucker et bounding box"
```

---

### Task 5: Modèles SwiftData

Deliverable : le `ModelContainer` s'ouvre sur un store dans `Application Support` et un test crée puis relit une activité.

**Files:**
- Create: `StravaLocal/Model/SportType.swift`
- Create: `StravaLocal/Model/Activity.swift`
- Create: `StravaLocal/Model/ActivityStreams.swift`
- Create: `StravaLocal/Model/Athlete.swift`
- Create: `StravaLocal/Model/Lap.swift`
- Create: `StravaLocal/Model/Gear.swift`
- Create: `StravaLocal/Model/SyncState.swift`
- Create: `StravaLocal/Model/ModelContainer+App.swift`
- Create: `Tests/ModelTests.swift`

**Interfaces:**
- Consumes: `Coordinate`, `BoundingBox`, `TrackBlob` (Tasks 2-4).
- Produces:
  - `enum SportType: String, Codable, CaseIterable, Sendable, Identifiable` avec cas `ride, mountainBikeRide, gravelRide, eBikeRide, run, trailRun, walk, hike, swim, nordicSki, alpineSki, rowing, workout, other`, `var displayName: String`, `var symbolName: String`, `init(stravaValue: String)`.
  - `@Model final class Activity` — voir propriétés ci-dessous ; `var boundingBox: BoundingBox?`, `var simplifiedCoordinates: [Coordinate]`, `func apply(boundingBox:)`, `func apply(simplifiedCoordinates:)`.
  - `@Model final class ActivityStreams` avec `latlng, altitude, time, heartrate, cadence, watts, velocitySmooth, temp, grade, moving: Data?` et `pointCount: Int`.
  - `@Model final class Athlete`, `@Model final class Lap`, `@Model final class Gear`.
  - `@Model final class SyncState` avec `lastSummaryEpoch: Int`, `pendingStreamIDs: [Int64]`, `lastRunAt: Date?`, `lastErrorMessage: String?`, `isInitialImportDone: Bool`.
  - `enum AppModelContainer { static let schema: Schema; static func make() throws -> ModelContainer; static func inMemory() throws -> ModelContainer }`

- [ ] **Step 1: Écrire le test d'abord**

`Tests/ModelTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("Model")
struct ModelTests {
    @Test("une activité survit à un aller-retour en base")
    func persistsActivity() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let activity = Activity(stravaID: 42, name: "Sortie du matin", sportType: .ride)
        activity.distance = 42_195
        activity.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let track = [
            Coordinate(latitude: 45.75, longitude: 4.83),
            Coordinate(latitude: 45.80, longitude: 4.90),
        ]
        activity.apply(simplifiedCoordinates: track)
        activity.apply(boundingBox: BoundingBox(coordinates: track)!)
        context.insert(activity)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Activity>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Sortie du matin")
        #expect(fetched[0].sportType == .ride)
        #expect(fetched[0].simplifiedCoordinates == track)
        #expect(fetched[0].boundingBox == BoundingBox(coordinates: track))
        #expect(fetched[0].minLat == 45.75)
        #expect(fetched[0].maxLon == 4.90)
    }

    @Test("les streams sont liés et relisibles")
    func persistsStreams() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let activity = Activity(stravaID: 7, name: "Test", sportType: .run)
        let streams = ActivityStreams()
        streams.pointCount = 3
        streams.altitude = TrackBlob.encode(scalars: [100, 110, 120])
        streams.activity = activity
        activity.streams = streams
        context.insert(activity)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Activity>())
        let altitude = fetched[0].streams.flatMap { $0.altitude }
        #expect(altitude.map(TrackBlob.decodeScalars) == [100, 110, 120])
    }

    @Test("le type de sport Strava inconnu retombe sur other")
    func mapsUnknownSport() {
        #expect(SportType(stravaValue: "Ride") == .ride)
        #expect(SportType(stravaValue: "TrailRun") == .trailRun)
        #expect(SportType(stravaValue: "Kitesurf") == .other)
    }

    @Test("l'état de synchro persiste sa file d'attente")
    func persistsSyncState() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let state = SyncState()
        state.pendingStreamIDs = [1, 2, 3]
        state.lastSummaryEpoch = 1_700_000_000
        context.insert(state)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SyncState>())
        #expect(fetched[0].pendingStreamIDs == [1, 2, 3])
        #expect(fetched[0].lastSummaryEpoch == 1_700_000_000)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'AppModelContainer' in scope ».

- [ ] **Step 3: Écrire `SportType`**

```swift
import Foundation

/// The sports we surface in the sidebar. Strava has more values than this;
/// anything unrecognised lands in `.other` rather than polluting the UI.
enum SportType: String, Codable, CaseIterable, Sendable, Identifiable {
    case ride, mountainBikeRide, gravelRide, eBikeRide
    case run, trailRun, walk, hike
    case swim, nordicSki, alpineSki, rowing, workout, other

    var id: String { rawValue }

    init(stravaValue: String) {
        switch stravaValue {
        case "Ride": self = .ride
        case "MountainBikeRide": self = .mountainBikeRide
        case "GravelRide": self = .gravelRide
        case "EBikeRide", "EMountainBikeRide": self = .eBikeRide
        case "Run": self = .run
        case "TrailRun": self = .trailRun
        case "Walk": self = .walk
        case "Hike": self = .hike
        case "Swim": self = .swim
        case "NordicSki", "BackcountrySki": self = .nordicSki
        case "AlpineSki", "Snowboard": self = .alpineSki
        case "Rowing", "Kayaking", "Canoeing": self = .rowing
        case "Workout", "WeightTraining", "Crossfit", "Yoga": self = .workout
        default: self = .other
        }
    }

    var displayName: String {
        switch self {
        case .ride: "Vélo"
        case .mountainBikeRide: "VTT"
        case .gravelRide: "Gravel"
        case .eBikeRide: "Vélo électrique"
        case .run: "Course"
        case .trailRun: "Trail"
        case .walk: "Marche"
        case .hike: "Randonnée"
        case .swim: "Natation"
        case .nordicSki: "Ski de fond"
        case .alpineSki: "Ski alpin"
        case .rowing: "Aviron"
        case .workout: "Renforcement"
        case .other: "Autre"
        }
    }

    /// SF Symbols only — no bundled art, so the app follows system appearance.
    var symbolName: String {
        switch self {
        case .ride, .eBikeRide: "bicycle"
        case .mountainBikeRide, .gravelRide: "bicycle.circle"
        case .run, .trailRun: "figure.run"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .swim: "figure.pool.swim"
        case .nordicSki: "figure.skiing.crosscountry"
        case .alpineSki: "figure.skiing.downhill"
        case .rowing: "figure.rowing"
        case .workout: "figure.strengthtraining.traditional"
        case .other: "sparkles"
        }
    }
}
```

- [ ] **Step 4: Écrire `Activity`**

```swift
import Foundation
import SwiftData

@Model
final class Activity {
    #Index<Activity>([\.startDate], [\.stravaID], [\.minLat], [\.maxLat], [\.minLon], [\.maxLon])
    #Unique<Activity>([\.stravaID])

    var stravaID: Int64 = 0
    var name: String = ""
    var sportTypeRaw: String = SportType.other.rawValue
    var startDate: Date = Date.distantPast
    var startLocalDate: Date = Date.distantPast
    var timezoneIdentifier: String?

    var distance: Double = 0
    var movingTime: Int = 0
    var elapsedTime: Int = 0
    var totalElevationGain: Double = 0
    var averageSpeed: Double = 0
    var maxSpeed: Double = 0
    var averageHeartrate: Double?
    var maxHeartrate: Double?
    var averageWatts: Double?
    var weightedAverageWatts: Double?
    var kilojoules: Double?
    var averageCadence: Double?
    var calories: Double?

    var isCommute: Bool = false
    var isTrainer: Bool = false
    var isManual: Bool = false
    var isPrivate: Bool = false

    var kudosCount: Int = 0
    var achievementCount: Int = 0
    var prCount: Int = 0
    var athleteCount: Int = 1

    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?

    /// Bounding box of the track, flattened into indexed columns so a
    /// geographic query can be pre-filtered by the database itself.
    /// `world` when the activity has no track (manual entries, indoor trainer).
    var minLat: Double = -90
    var maxLat: Double = 90
    var minLon: Double = -180
    var maxLon: Double = 180
    var hasTrack: Bool = false

    /// Douglas-Peucker-simplified track, packed by `TrackBlob`. Duplicated from
    /// the streams on purpose: it lets the global map and geographic search read
    /// every activity without ever loading a full stream.
    var simplifiedTrack: Data?

    var summaryPolyline: String?
    var activityDescription: String?
    var deviceName: String?
    /// Non-nil once the detail endpoint has been fetched for this activity.
    var detailFetchedAt: Date?

    /// Kept alongside the relationship: the summary endpoint gives us a gear id
    /// long before the gear itself is fetched, and without storing it there'd be
    /// nothing left to link against afterwards.
    var gearID: String?
    var gear: Gear?
    @Relationship(deleteRule: .cascade, inverse: \Lap.activity)
    var laps: [Lap] = []
    @Relationship(deleteRule: .cascade, inverse: \ActivityStreams.activity)
    var streams: ActivityStreams?

    init(stravaID: Int64, name: String, sportType: SportType) {
        self.stravaID = stravaID
        self.name = name
        self.sportTypeRaw = sportType.rawValue
    }

    var sportType: SportType {
        get { SportType(rawValue: sportTypeRaw) ?? .other }
        set { sportTypeRaw = newValue.rawValue }
    }

    var boundingBox: BoundingBox? {
        guard hasTrack else { return nil }
        return BoundingBox(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    func apply(boundingBox box: BoundingBox) {
        minLat = box.minLat
        maxLat = box.maxLat
        minLon = box.minLon
        maxLon = box.maxLon
        hasTrack = true
    }

    var simplifiedCoordinates: [Coordinate] {
        simplifiedTrack.map(TrackBlob.decodeCoordinates) ?? []
    }

    func apply(simplifiedCoordinates coordinates: [Coordinate]) {
        simplifiedTrack = coordinates.isEmpty ? nil : TrackBlob.encode(coordinates: coordinates)
    }
}
```

- [ ] **Step 5: Écrire `ActivityStreams`, `Athlete`, `Lap`, `Gear`, `SyncState`**

`ActivityStreams.swift` :

```swift
import Foundation
import SwiftData

/// One blob per stream, kept out of the row so listing activities never pays
/// for them. Decode with `TrackBlob`: `latlng` as coordinates, `time` as
/// Int32 seconds, everything else as Float scalars.
@Model
final class ActivityStreams {
    var pointCount: Int = 0

    @Attribute(.externalStorage) var latlng: Data?
    @Attribute(.externalStorage) var altitude: Data?
    @Attribute(.externalStorage) var time: Data?
    @Attribute(.externalStorage) var heartrate: Data?
    @Attribute(.externalStorage) var cadence: Data?
    @Attribute(.externalStorage) var watts: Data?
    @Attribute(.externalStorage) var velocitySmooth: Data?
    @Attribute(.externalStorage) var temp: Data?
    @Attribute(.externalStorage) var grade: Data?
    @Attribute(.externalStorage) var moving: Data?

    var activity: Activity?

    init() {}

    var coordinates: [Coordinate] {
        latlng.map(TrackBlob.decodeCoordinates) ?? []
    }
}
```

`Athlete.swift` :

```swift
import Foundation
import SwiftData

@Model
final class Athlete {
    var stravaID: Int64 = 0
    var firstName: String = ""
    var lastName: String = ""
    var city: String?
    var country: String?
    var profileImageURL: String?
    var weight: Double?
    var updatedAt: Date = Date.distantPast

    init(stravaID: Int64) { self.stravaID = stravaID }

    var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
}
```

`Lap.swift` :

```swift
import Foundation
import SwiftData

@Model
final class Lap {
    var stravaID: Int64 = 0
    var lapIndex: Int = 0
    var name: String = ""
    var distance: Double = 0
    var movingTime: Int = 0
    var elapsedTime: Int = 0
    var totalElevationGain: Double = 0
    var averageSpeed: Double = 0
    var maxSpeed: Double = 0
    var averageHeartrate: Double?
    var averageCadence: Double?
    /// Index range into the activity's streams, so a lap can be highlighted.
    var startIndex: Int = 0
    var endIndex: Int = 0

    var activity: Activity?

    init(stravaID: Int64, lapIndex: Int) {
        self.stravaID = stravaID
        self.lapIndex = lapIndex
    }
}
```

`Gear.swift` :

```swift
import Foundation
import SwiftData

@Model
final class Gear {
    #Unique<Gear>([\.stravaID])

    var stravaID: String = ""
    var name: String = ""
    var brandName: String?
    var modelName: String?
    var isBike: Bool = true
    var totalDistance: Double = 0

    init(stravaID: String, name: String) {
        self.stravaID = stravaID
        self.name = name
    }
}
```

`SyncState.swift` :

```swift
import Foundation
import SwiftData

/// Single-row record holding everything needed to resume a sync. Progress lives
/// in the database, not in memory, so quitting the app or exhausting the API
/// quota interrupts a sync without losing it.
@Model
final class SyncState {
    /// `after` cursor for the summary endpoint: epoch seconds of the most
    /// recent activity already imported.
    var lastSummaryEpoch: Int = 0
    /// Strava IDs of activities whose streams are still missing.
    var pendingStreamIDs: [Int64] = []
    var lastRunAt: Date?
    var lastErrorMessage: String?
    var isInitialImportDone: Bool = false

    init() {}
}
```

- [ ] **Step 6: Écrire `ModelContainer+App`**

```swift
import Foundation
import SwiftData

enum AppModelContainer {
    static let schema = Schema([
        Activity.self, ActivityStreams.self, Athlete.self,
        Lap.self, Gear.self, SyncState.self,
    ])

    static func make() throws -> ModelContainer {
        let directory = URL.applicationSupportDirectory.appending(path: "StravaLocal")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(
            schema: schema, url: directory.appending(path: "StravaLocal.store")
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
```

- [ ] **Step 7: Câbler le container dans l'app**

Remplacer `StravaLocal/App/StravaLocalApp.swift` par :

```swift
import SwiftUI
import SwiftData

@main
struct StravaLocalApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try AppModelContainer.make()
        } catch {
            fatalError("Impossible d'ouvrir la base locale : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Text("StravaLocal")
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 8: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 9: Commit**

```bash
git add StravaLocal/Model StravaLocal/App Tests/ModelTests.swift
git commit -m "feat(model): schéma SwiftData (activités, streams, laps, gear, état de synchro)"
```

---

### Task 6: DTOs Strava et fixtures

Deliverable : les réponses JSON réelles de Strava se décodent en DTOs typés.

**Files:**
- Create: `StravaLocal/Strava/StravaDTO.swift`
- Create: `Tests/Fixtures/summary_activity.json`
- Create: `Tests/Fixtures/manual_activity.json`
- Create: `Tests/Fixtures/streams.json`
- Create: `Tests/Fixtures/athlete.json`
- Create: `Tests/StravaDTOTests.swift`
- Create: `Tests/FixtureLoader.swift`

**Interfaces:**
- Consumes: rien.
- Produces:
  - `struct SummaryActivityDTO: Decodable, Sendable` — champs : `id: Int64`, `name: String`, `sport_type: String`, `start_date: Date`, `start_date_local: Date`, `timezone: String?`, `distance: Double`, `moving_time: Int`, `elapsed_time: Int`, `total_elevation_gain: Double`, `average_speed: Double`, `max_speed: Double`, `average_heartrate: Double?`, `max_heartrate: Double?`, `average_watts: Double?`, `weighted_average_watts: Double?`, `kilojoules: Double?`, `average_cadence: Double?`, `commute: Bool?`, `trainer: Bool?`, `manual: Bool?`, `private: Bool?`, `kudos_count: Int?`, `achievement_count: Int?`, `pr_count: Int?`, `athlete_count: Int?`, `start_latlng: [Double]?`, `end_latlng: [Double]?`, `gear_id: String?`, `map: MapDTO?`
  - `struct MapDTO: Decodable, Sendable { let summary_polyline: String? }`
  - `struct DetailActivityDTO: Decodable, Sendable { let id: Int64; let description: String?; let calories: Double?; let device_name: String?; let laps: [LapDTO]? }`
  - `struct LapDTO: Decodable, Sendable`
  - `struct StreamSetDTO: Decodable, Sendable { let latlng: StreamDTO<[Double]>?; let altitude: StreamDTO<Double>?; let time: StreamDTO<Int>?; let heartrate: StreamDTO<Double>?; let cadence: StreamDTO<Double>?; let watts: StreamDTO<Double>?; let velocity_smooth: StreamDTO<Double>?; let temp: StreamDTO<Double>?; let grade_smooth: StreamDTO<Double>?; let moving: StreamDTO<Bool>? }`
  - `struct StreamDTO<Element: Decodable & Sendable>: Decodable, Sendable { let data: [Element] }`
  - `struct AthleteDTO: Decodable, Sendable`
  - `struct TokenResponseDTO: Decodable, Sendable { let access_token: String; let refresh_token: String; let expires_at: Int; let athlete: AthleteDTO? }`
  - `enum StravaJSON { static let decoder: JSONDecoder }` — décodeur configuré avec `.iso8601`, sans conversion de clés (les DTOs utilisent les noms Strava tels quels).
  - `enum Fixture { static func data(_ name: String) throws -> Data; static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T }` (cible de test)

Les DTOs conservent volontairement le nommage `snake_case` de Strava : aucune stratégie de conversion à maintenir, et la correspondance avec la documentation Strava reste évidente. La traduction vers le nommage Swift se fait dans `ImportMapper` (Task 10), au seul endroit qui la mérite.

- [ ] **Step 1: Écrire la fixture d'activité résumée**

`Tests/Fixtures/summary_activity.json` :

```json
{
  "id": 10123456789,
  "name": "Sortie matinale",
  "sport_type": "Ride",
  "start_date": "2025-06-14T05:32:11Z",
  "start_date_local": "2025-06-14T07:32:11Z",
  "timezone": "(GMT+01:00) Europe/Paris",
  "distance": 45231.4,
  "moving_time": 5412,
  "elapsed_time": 5890,
  "total_elevation_gain": 612.0,
  "average_speed": 8.357,
  "max_speed": 16.2,
  "average_heartrate": 138.4,
  "max_heartrate": 171.0,
  "average_watts": 156.3,
  "weighted_average_watts": 178,
  "kilojoules": 846.1,
  "average_cadence": 82.5,
  "commute": false,
  "trainer": false,
  "manual": false,
  "private": false,
  "kudos_count": 12,
  "achievement_count": 3,
  "pr_count": 1,
  "athlete_count": 2,
  "start_latlng": [45.764043, 4.835659],
  "end_latlng": [45.771, 4.842],
  "gear_id": "b1234567",
  "map": {
    "id": "a10123456789",
    "summary_polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
    "resource_state": 2
  }
}
```

- [ ] **Step 2: Écrire les autres fixtures**

`Tests/Fixtures/manual_activity.json` — une entrée manuelle sans trace ni capteur, pour vérifier que tous les champs optionnels absents sont tolérés :

```json
{
  "id": 10999999999,
  "name": "Séance salle",
  "sport_type": "WeightTraining",
  "start_date": "2025-06-15T18:00:00Z",
  "start_date_local": "2025-06-15T20:00:00Z",
  "distance": 0.0,
  "moving_time": 3600,
  "elapsed_time": 3600,
  "total_elevation_gain": 0.0,
  "average_speed": 0.0,
  "max_speed": 0.0,
  "manual": true,
  "start_latlng": [],
  "end_latlng": [],
  "map": { "id": "a10999999999", "summary_polyline": null }
}
```

`Tests/Fixtures/streams.json` :

```json
{
  "latlng": {
    "data": [[45.764043, 4.835659], [45.765, 4.8365], [45.766, 4.837]],
    "series_type": "distance",
    "original_size": 3,
    "resolution": "high"
  },
  "altitude": { "data": [172.4, 175.1, 180.9], "original_size": 3 },
  "time": { "data": [0, 5, 11], "original_size": 3 },
  "heartrate": { "data": [96.0, 104.0, 118.0], "original_size": 3 },
  "velocity_smooth": { "data": [0.0, 4.2, 5.1], "original_size": 3 },
  "moving": { "data": [false, true, true], "original_size": 3 }
}
```

`Tests/Fixtures/athlete.json` :

```json
{
  "id": 1234567,
  "firstname": "Florian",
  "lastname": "Maisonnial",
  "city": "Lyon",
  "country": "France",
  "profile": "https://example.invalid/large.jpg",
  "weight": 72.5
}
```

- [ ] **Step 3: Écrire le chargeur de fixtures et les tests**

`Tests/FixtureLoader.swift` :

```swift
import Foundation
import Testing
@testable import StravaLocal

/// Reads JSON fixtures from the test bundle root. `project.yml` excludes
/// `Fixtures/**` from the plain source list and declares it as a resources
/// build phase group, so each file lands flat in the bundle.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle(for: BundleToken.self)
            .url(forResource: name, withExtension: "json")
        else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try StravaJSON.decoder.decode(type, from: data(name))
    }

    enum FixtureError: Error { case notFound(String) }
    private final class BundleToken {}
}
```

`Tests/StravaDTOTests.swift` :

```swift
import Testing
import Foundation
@testable import StravaLocal

@Suite("StravaDTO")
struct StravaDTOTests {
    @Test("décode une activité résumée complète")
    func decodesSummary() throws {
        let dto = try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        #expect(dto.id == 10_123_456_789)
        #expect(dto.name == "Sortie matinale")
        #expect(dto.sport_type == "Ride")
        #expect(dto.distance == 45_231.4)
        #expect(dto.moving_time == 5412)
        #expect(dto.average_heartrate == 138.4)
        #expect(dto.gear_id == "b1234567")
        #expect(dto.map?.summary_polyline == "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(dto.start_latlng == [45.764043, 4.835659])
        #expect(dto.start_date == ISO8601DateFormatter().date(from: "2025-06-14T05:32:11Z"))
        #expect(dto.start_date_local == ISO8601DateFormatter().date(from: "2025-06-14T07:32:11Z"))
    }

    @Test("décode une activité manuelle sans capteur ni trace")
    func decodesManual() throws {
        let dto = try Fixture.decode(SummaryActivityDTO.self, "manual_activity")
        #expect(dto.manual == true)
        #expect(dto.average_heartrate == nil)
        #expect(dto.average_watts == nil)
        #expect(dto.kudos_count == nil)
        #expect(dto.map?.summary_polyline == nil)
        #expect(dto.start_latlng == [])
    }

    @Test("décode un jeu de streams")
    func decodesStreams() throws {
        let dto = try Fixture.decode(StreamSetDTO.self, "streams")
        #expect(dto.latlng?.data.count == 3)
        #expect(dto.latlng?.data.first == [45.764043, 4.835659])
        #expect(dto.altitude?.data == [172.4, 175.1, 180.9])
        #expect(dto.time?.data == [0, 5, 11])
        #expect(dto.heartrate?.data == [96, 104, 118])
        #expect(dto.moving?.data == [false, true, true])
        #expect(dto.watts == nil)
    }

    @Test("décode un athlète")
    func decodesAthlete() throws {
        let dto = try Fixture.decode(AthleteDTO.self, "athlete")
        #expect(dto.id == 1_234_567)
        #expect(dto.firstname == "Florian")
        #expect(dto.city == "Lyon")
        #expect(dto.weight == 72.5)
    }
}
```

- [ ] **Step 4: Déclarer les fixtures comme ressources de la cible de test**

Dans `project.yml`, remplacer le bloc `sources` de la cible `StravaLocalTests` par :

```yaml
    sources:
      - path: Tests
        excludes:
          - "Fixtures/**"
      - path: Tests/Fixtures
        type: group
        buildPhase: resources
```

`type: group` et non `type: folder` : un dossier référencé conserve sa hiérarchie et place les fixtures sous `Resources/Fixtures/`, où le `url(forResource:withExtension:)` plat de `FixtureLoader` ne les trouve pas. En groupe, chaque fichier entre individuellement dans la phase de ressources et atterrit à la racine du bundle.

Puis `xcodegen generate`.

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'SummaryActivityDTO' in scope ».

- [ ] **Step 6: Écrire les DTOs**

```swift
import Foundation

/// Wire-format mirrors of the Strava REST responses.
///
/// Property names keep Strava's snake_case on purpose: no key-conversion
/// strategy to maintain, and every field maps visibly onto the published API
/// docs. Renaming to Swift conventions happens once, in `ImportMapper`.
struct MapDTO: Decodable, Sendable {
    let summary_polyline: String?
}

struct SummaryActivityDTO: Decodable, Sendable {
    let id: Int64
    let name: String
    let sport_type: String
    let start_date: Date
    let start_date_local: Date
    let timezone: String?
    let distance: Double
    let moving_time: Int
    let elapsed_time: Int
    let total_elevation_gain: Double
    let average_speed: Double
    let max_speed: Double
    let average_heartrate: Double?
    let max_heartrate: Double?
    let average_watts: Double?
    let weighted_average_watts: Double?
    let kilojoules: Double?
    let average_cadence: Double?
    let commute: Bool?
    let trainer: Bool?
    let manual: Bool?
    let `private`: Bool?
    let kudos_count: Int?
    let achievement_count: Int?
    let pr_count: Int?
    let athlete_count: Int?
    let start_latlng: [Double]?
    let end_latlng: [Double]?
    let gear_id: String?
    let map: MapDTO?
}

struct LapDTO: Decodable, Sendable {
    let id: Int64
    let name: String?
    let lap_index: Int
    let distance: Double
    let moving_time: Int
    let elapsed_time: Int
    let total_elevation_gain: Double?
    let average_speed: Double?
    let max_speed: Double?
    let average_heartrate: Double?
    let average_cadence: Double?
    let start_index: Int?
    let end_index: Int?
}

struct DetailActivityDTO: Decodable, Sendable {
    let id: Int64
    let description: String?
    let calories: Double?
    let device_name: String?
    let laps: [LapDTO]?
}

struct StreamDTO<Element: Decodable & Sendable>: Decodable, Sendable {
    let data: [Element]
}

/// Result of `key_by_type=true`: one keyed object per requested stream.
struct StreamSetDTO: Decodable, Sendable {
    let latlng: StreamDTO<[Double]>?
    let altitude: StreamDTO<Double>?
    let time: StreamDTO<Int>?
    let heartrate: StreamDTO<Double>?
    let cadence: StreamDTO<Double>?
    let watts: StreamDTO<Double>?
    let velocity_smooth: StreamDTO<Double>?
    let temp: StreamDTO<Double>?
    let grade_smooth: StreamDTO<Double>?
    let moving: StreamDTO<Bool>?
}

struct AthleteDTO: Decodable, Sendable {
    let id: Int64
    let firstname: String?
    let lastname: String?
    let city: String?
    let country: String?
    let profile: String?
    let weight: Double?
}

struct TokenResponseDTO: Decodable, Sendable {
    let access_token: String
    let refresh_token: String
    let expires_at: Int
    let athlete: AthleteDTO?
}

struct GearDTO: Decodable, Sendable {
    let id: String
    let name: String
    let brand_name: String?
    let model_name: String?
    let distance: Double?
}

enum StravaJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
```

- [ ] **Step 7: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add StravaLocal/Strava project.yml Tests
git commit -m "feat(strava): DTOs des réponses API et fixtures de test"
```

---

### Task 7: Stockage Keychain des credentials et jetons

Deliverable : credentials et jetons s'écrivent, se relisent et s'effacent dans le Keychain, sans jamais toucher le disque en clair.

**Files:**
- Create: `StravaLocal/Strava/TokenStore.swift`
- Create: `Tests/TokenStoreTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces:
  - `struct StravaCredentials: Sendable, Equatable { let clientID: String; let clientSecret: String }`
  - `struct StravaTokens: Sendable, Equatable, Codable { let accessToken: String; let refreshToken: String; let expiresAt: Date; var isExpired: Bool { get } }` — `isExpired` est vrai dès qu'il reste moins de 5 minutes.
  - `protocol SecretStore: Sendable { func credentials() -> StravaCredentials?; func save(_ credentials: StravaCredentials) throws; func tokens() -> StravaTokens?; func save(_ tokens: StravaTokens) throws; func clearTokens() throws; func clearAll() throws }`
  - `final class KeychainStore: SecretStore, Sendable { init(service: String = "com.florianmaisonnial.StravaLocal") }`
  - `final class InMemorySecretStore: SecretStore, @unchecked Sendable { init() }` — utilisé par les tests et par les tests de `StravaClient` (Task 9).
  - `enum SecretStoreError: Error { case keychain(OSStatus) }`

`InMemorySecretStore` vit dans le code de production, pas dans les tests : c'est ce qui permet à `StravaClient` d'être testé sans Keychain, et il est trivial.

- [ ] **Step 1: Écrire les tests d'abord**

`Tests/TokenStoreTests.swift` :

```swift
import Testing
import Foundation
@testable import StravaLocal

@Suite("TokenStore")
struct TokenStoreTests {
    @Test("un jeton valable plus de 5 minutes n'est pas expiré")
    func freshTokenIsValid() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600)
        )
        #expect(!tokens.isExpired)
    }

    @Test("un jeton qui expire dans moins de 5 minutes est traité comme expiré")
    func nearlyExpiredTokenCountsAsExpired() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(60)
        )
        #expect(tokens.isExpired)
    }

    @Test("un jeton dépassé est expiré")
    func pastTokenIsExpired() {
        let tokens = StravaTokens(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(-1)
        )
        #expect(tokens.isExpired)
    }

    @Test("le store en mémoire respecte le contrat")
    func inMemoryStoreRoundTrips() throws {
        let store = InMemorySecretStore()
        #expect(store.credentials() == nil)
        #expect(store.tokens() == nil)

        let credentials = StravaCredentials(clientID: "123", clientSecret: "secret")
        try store.save(credentials)
        #expect(store.credentials() == credentials)

        let tokens = StravaTokens(
            accessToken: "at", refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try store.save(tokens)
        #expect(store.tokens() == tokens)

        try store.clearTokens()
        #expect(store.tokens() == nil)
        #expect(store.credentials() == credentials)

        try store.clearAll()
        #expect(store.credentials() == nil)
    }

    @Test("le Keychain respecte le même contrat")
    func keychainStoreRoundTrips() throws {
        // Dedicated service name so the app's real credentials are never touched.
        let store = KeychainStore(service: "com.florianmaisonnial.StravaLocal.tests")
        try store.clearAll()

        let credentials = StravaCredentials(clientID: "42", clientSecret: "shh")
        try store.save(credentials)
        #expect(store.credentials() == credentials)

        // Rewrite must update in place, not fail on a duplicate item.
        let updated = StravaCredentials(clientID: "43", clientSecret: "shh2")
        try store.save(updated)
        #expect(store.credentials() == updated)

        let tokens = StravaTokens(
            accessToken: "at", refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try store.save(tokens)
        #expect(store.tokens()?.accessToken == "at")
        #expect(store.tokens()?.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))

        // Clearing tokens must not take the credentials with them.
        try store.clearTokens()
        #expect(store.tokens() == nil)
        #expect(store.credentials() == updated)

        try store.clearAll()
        #expect(store.credentials() == nil)
        #expect(store.tokens() == nil)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'StravaTokens' in scope ».

- [ ] **Step 3: Écrire `TokenStore`**

```swift
import Foundation
import Security

struct StravaCredentials: Sendable, Equatable, Codable {
    let clientID: String
    let clientSecret: String
}

struct StravaTokens: Sendable, Equatable, Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    /// Treated as expired five minutes early so a long request can't start on a
    /// token that dies mid-flight.
    var isExpired: Bool {
        expiresAt.timeIntervalSinceNow < 300
    }
}

protocol SecretStore: Sendable {
    func credentials() -> StravaCredentials?
    func save(_ credentials: StravaCredentials) throws
    func tokens() -> StravaTokens?
    func save(_ tokens: StravaTokens) throws
    func clearTokens() throws
    func clearAll() throws
}

enum SecretStoreError: Error {
    case keychain(OSStatus)
}

/// Generic-password Keychain items, one per record, keyed by account name.
/// Values are JSON so adding a field later doesn't need a migration.
final class KeychainStore: SecretStore, Sendable {
    private let service: String
    private static let credentialsAccount = "credentials"
    private static let tokensAccount = "tokens"

    init(service: String = "com.florianmaisonnial.StravaLocal") {
        self.service = service
    }

    func credentials() -> StravaCredentials? {
        read(StravaCredentials.self, account: Self.credentialsAccount)
    }

    func save(_ credentials: StravaCredentials) throws {
        try write(credentials, account: Self.credentialsAccount)
    }

    func tokens() -> StravaTokens? {
        read(StravaTokens.self, account: Self.tokensAccount)
    }

    func save(_ tokens: StravaTokens) throws {
        try write(tokens, account: Self.tokensAccount)
    }

    func clearTokens() throws {
        try delete(account: Self.tokensAccount)
    }

    func clearAll() throws {
        try delete(account: Self.tokensAccount)
        try delete(account: Self.credentialsAccount)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read<T: Decodable>(_ type: T.Type, account: String) -> T? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = baseQuery(account: account)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.keychain(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.keychain(addStatus)
        }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }
}

/// Non-persistent implementation, used to test everything that depends on
/// secrets without touching the user's Keychain.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCredentials: StravaCredentials?
    private var storedTokens: StravaTokens?

    init(credentials: StravaCredentials? = nil, tokens: StravaTokens? = nil) {
        storedCredentials = credentials
        storedTokens = tokens
    }

    func credentials() -> StravaCredentials? {
        lock.withLock { storedCredentials }
    }

    func save(_ credentials: StravaCredentials) throws {
        lock.withLock { storedCredentials = credentials }
    }

    func tokens() -> StravaTokens? {
        lock.withLock { storedTokens }
    }

    func save(_ tokens: StravaTokens) throws {
        lock.withLock { storedTokens = tokens }
    }

    func clearTokens() throws {
        lock.withLock { storedTokens = nil }
    }

    func clearAll() throws {
        lock.withLock {
            storedTokens = nil
            storedCredentials = nil
        }
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`. Si macOS demande l'autorisation d'accès au Keychain, cliquer « Toujours autoriser » — l'identité de signature étant stable, la demande ne réapparaît pas.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Strava/TokenStore.swift Tests/TokenStoreTests.swift
git commit -m "feat(strava): stockage Keychain des credentials et jetons"
```

---

### Task 8: Rate limiter

Deliverable : le quota Strava est suivi à partir des en-têtes de réponse, et le limiteur sait dire combien de temps attendre avant la prochaine requête.

**Files:**
- Create: `StravaLocal/Strava/RateLimiter.swift`
- Create: `Tests/RateLimiterTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces:
  - `struct RateLimitSnapshot: Sendable, Equatable { let shortTermUsage: Int; let shortTermLimit: Int; let dailyUsage: Int; let dailyLimit: Int; init?(headers: [String: String]) }`
  - `actor RateLimiter { init(clock: @escaping @Sendable () -> Date = { Date() }, reserve: Int = 5); func observeSuccess(headers: [String: String]); func observeTooManyRequests(); var snapshot: RateLimitSnapshot? { get }; func delayBeforeNextRequest() -> TimeInterval; func reset() }`

`delayBeforeNextRequest` renvoie 0 quand il reste de la marge, la durée jusqu'à la prochaine fenêtre de 15 minutes quand le quota court terme est saturé, la durée jusqu'à minuit UTC quand le quota journalier est saturé, et un backoff exponentiel après un ou plusieurs `429`. L'horloge est injectée : les tests n'attendent jamais réellement.

- [ ] **Step 1: Écrire les tests d'abord**

`Tests/RateLimiterTests.swift` :

```swift
import Testing
import Foundation
@testable import StravaLocal

@Suite("RateLimiter")
struct RateLimiterTests {
    private func headers(short: String, daily: String) -> [String: String] {
        ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "\(short),\(daily)"]
    }

    @Test("parse les en-têtes de quota")
    func parsesHeaders() {
        let snapshot = RateLimitSnapshot(
            headers: ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "42,1337"]
        )
        #expect(snapshot?.shortTermUsage == 42)
        #expect(snapshot?.shortTermLimit == 200)
        #expect(snapshot?.dailyUsage == 1337)
        #expect(snapshot?.dailyLimit == 2000)
    }

    @Test("des en-têtes absents ou malformés ne donnent pas de snapshot")
    func rejectsBadHeaders() {
        #expect(RateLimitSnapshot(headers: [:]) == nil)
        #expect(RateLimitSnapshot(headers: ["X-RateLimit-Limit": "200"]) == nil)
        #expect(
            RateLimitSnapshot(
                headers: ["X-RateLimit-Limit": "a,b", "X-RateLimit-Usage": "1,2"]
            ) == nil
        )
    }

    @Test("les en-têtes sont reconnus quelle que soit la casse")
    func headerLookupIsCaseInsensitive() {
        let snapshot = RateLimitSnapshot(
            headers: ["x-ratelimit-limit": "200,2000", "x-ratelimit-usage": "1,2"]
        )
        #expect(snapshot?.shortTermUsage == 1)
    }

    @Test("aucune attente quand il reste de la marge")
    func noDelayWithHeadroom() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) })
        await limiter.observeSuccess(headers: headers(short: "10", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() == 0)
    }

    @Test("attend la prochaine fenêtre de 15 minutes quand le quota court terme est saturé")
    func waitsForNextShortWindow() async {
        // 1970-01-01T00:03:00Z → la fenêtre courante finit à 00:15:00Z, soit 720 s.
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 180) })
        await limiter.observeSuccess(headers: headers(short: "199", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() == 720)
    }

    @Test("la réserve empêche de consommer les toutes dernières requêtes")
    func reserveTriggersWait() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) }, reserve: 5)
        await limiter.observeSuccess(headers: headers(short: "196", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() > 0)
        await limiter.observeSuccess(headers: headers(short: "194", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() == 0)
    }

    @Test("attend minuit UTC quand le quota journalier est saturé")
    func waitsForNextDay() async {
        // 1970-01-01T00:03:00Z → minuit suivant à 86400 s, soit 86220 s d'attente.
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 180) })
        await limiter.observeSuccess(headers: headers(short: "10", daily: "1999"))
        #expect(await limiter.delayBeforeNextRequest() == 86_220)
    }

    @Test("un 429 déclenche un backoff qui double")
    func backsOffOnTooManyRequests() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) })
        await limiter.observeTooManyRequests()
        let first = await limiter.delayBeforeNextRequest()
        await limiter.observeTooManyRequests()
        let second = await limiter.delayBeforeNextRequest()
        #expect(first > 0)
        #expect(second >= first * 2)
    }

    @Test("une réponse réussie remet le backoff à zéro")
    func successResetsBackoff() async {
        let limiter = RateLimiter(clock: { Date(timeIntervalSince1970: 0) })
        await limiter.observeTooManyRequests()
        #expect(await limiter.delayBeforeNextRequest() > 0)
        await limiter.observeSuccess(headers: headers(short: "10", daily: "100"))
        #expect(await limiter.delayBeforeNextRequest() == 0)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'RateLimiter' in scope ».

- [ ] **Step 3: Écrire `RateLimiter`**

```swift
import Foundation

/// Strava reports quota on every response: `X-RateLimit-Limit: 200,2000` and
/// `X-RateLimit-Usage: <15min>,<daily>`.
struct RateLimitSnapshot: Sendable, Equatable {
    let shortTermUsage: Int
    let shortTermLimit: Int
    let dailyUsage: Int
    let dailyLimit: Int

    init(
        shortTermUsage: Int, shortTermLimit: Int, dailyUsage: Int, dailyLimit: Int
    ) {
        self.shortTermUsage = shortTermUsage
        self.shortTermLimit = shortTermLimit
        self.dailyUsage = dailyUsage
        self.dailyLimit = dailyLimit
    }

    init?(headers: [String: String]) {
        func value(_ name: String) -> [Int]? {
            let match = headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }
            guard let raw = match?.value else { return nil }
            let parts = raw.split(separator: ",").map {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            guard parts.count == 2, let first = parts[0], let second = parts[1] else {
                return nil
            }
            return [first, second]
        }
        guard let limits = value("X-RateLimit-Limit"),
              let usage = value("X-RateLimit-Usage")
        else { return nil }
        self.init(
            shortTermUsage: usage[0], shortTermLimit: limits[0],
            dailyUsage: usage[1], dailyLimit: limits[1]
        )
    }
}

/// Decides how long to wait before the next Strava request.
///
/// Pausing until the next window is the whole point: sync phase B walks
/// thousands of activities, and getting throttled mid-walk is both slower and
/// harder to reason about than waiting deliberately.
actor RateLimiter {
    private let clock: @Sendable () -> Date
    /// Requests deliberately left unused in each window, so an interactive
    /// action never gets blocked by a background sync burning the last call.
    private let reserve: Int
    private var latest: RateLimitSnapshot?
    private var consecutiveThrottles = 0

    private static let shortWindow: TimeInterval = 15 * 60
    private static let dailyWindow: TimeInterval = 24 * 60 * 60

    init(clock: @escaping @Sendable () -> Date = { Date() }, reserve: Int = 5) {
        self.clock = clock
        self.reserve = reserve
    }

    var snapshot: RateLimitSnapshot? { latest }

    /// Records a successful response's quota headers.
    ///
    /// Call this **only** for a non-throttled (2xx) response. Success is proof
    /// the throttling is over, so it clears any accumulated backoff — which is
    /// why it must never be called for a 429, even though Strava sends quota
    /// headers on those too. Use `observeTooManyRequests()` there instead.
    func observeSuccess(headers: [String: String]) {
        consecutiveThrottles = 0
        if let parsed = RateLimitSnapshot(headers: headers) {
            latest = parsed
        }
    }

    func observeTooManyRequests() {
        consecutiveThrottles += 1
    }

    func reset() {
        latest = nil
        consecutiveThrottles = 0
    }

    func delayBeforeNextRequest() -> TimeInterval {
        if consecutiveThrottles > 0 {
            // 30 s, 60 s, 120 s… capped at the 15-minute window.
            let backoff = 30 * pow(2, Double(consecutiveThrottles - 1))
            return min(backoff, Self.shortWindow)
        }
        guard let latest else { return 0 }

        let now = clock()
        if latest.dailyUsage >= latest.dailyLimit - reserve {
            return secondsUntilNextBoundary(of: Self.dailyWindow, from: now)
        }
        if latest.shortTermUsage >= latest.shortTermLimit - reserve {
            return secondsUntilNextBoundary(of: Self.shortWindow, from: now)
        }
        return 0
    }

    /// Strava's windows are aligned on UTC clock boundaries, not on first use.
    private func secondsUntilNextBoundary(
        of window: TimeInterval, from now: Date
    ) -> TimeInterval {
        let elapsed = now.timeIntervalSince1970.truncatingRemainder(dividingBy: window)
        return window - elapsed
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Strava/RateLimiter.swift Tests/RateLimiterTests.swift
git commit -m "feat(strava): rate limiter piloté par les en-têtes de quota"
```

---

### Task 9: Client Strava et flux OAuth

Deliverable : l'app obtient des jetons via le navigateur, les rafraîchit automatiquement, et sait appeler les quatre endpoints dont elle a besoin.

**Files:**
- Create: `StravaLocal/Strava/StravaError.swift`
- Create: `StravaLocal/Strava/OAuthFlow.swift`
- Create: `StravaLocal/Strava/StravaClient.swift`
- Create: `Tests/StravaClientTests.swift`

**Interfaces:**
- Consumes: `SecretStore`, `StravaCredentials`, `StravaTokens` (Task 7), `RateLimiter` (Task 8), tous les DTOs (Task 6).
- Produces:
  - `enum StravaError: LocalizedError, Sendable { case missingCredentials, notAuthenticated, invalidResponse, http(Int, String), tokenRefreshRejected, oauthCancelled, oauthStateMismatch, oauthDenied(String) }`
  - `protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`
  - `struct URLSessionTransport: HTTPTransport { init(session: URLSession = .shared) }`
  - `actor OAuthFlow { init(store: SecretStore, transport: HTTPTransport); func authorize() async throws -> AthleteDTO? }`
  - `actor StravaClient { init(store: SecretStore, transport: HTTPTransport = URLSessionTransport(), rateLimiter: RateLimiter = RateLimiter()); var isAuthenticated: Bool { get }; func rateLimitSnapshot() async -> RateLimitSnapshot?; func activities(after epoch: Int, page: Int, perPage: Int) async throws -> [SummaryActivityDTO]; func activityDetail(id: Int64) async throws -> DetailActivityDTO; func streams(id: Int64) async throws -> StreamSetDTO; func athlete() async throws -> AthleteDTO; func gear(id: String) async throws -> GearDTO; func signOut() throws }`

`HTTPTransport` est le point d'injection : les tests fournissent un transport en dur, sans réseau ni serveur factice.

Deux exigences non négociables, découvertes en revue :

- **Le rafraîchissement de jeton doit être mutualisé.** `StravaClient` est un acteur
  réentrant et `validAccessToken()` suspend sur le réseau : deux requêtes concurrentes
  rafraîchiraient toutes les deux, la seconde avec un refresh token que Strava a déjà
  consommé et fait tourner. Son rejet effacerait le jeton tout juste enregistré par la
  première, déconnectant silencieusement l'utilisateur. Comme `isExpired` déclenche
  5 minutes avant l'échéance, deux requêtes dans la même fenêtre de 5 minutes suffisent.
  Le rafraîchissement en cours est donc mémorisé dans un `Task` que tous les appelants
  attendent, et un rejet n'efface les jetons que s'ils sont encore ceux qu'il a essayés.
- **`OAuthFlow` doit être infaillible sans test.** Le listener ne doit résoudre l'attente
  que sur une requête portant réellement des paramètres OAuth — tout navigateur ouvre des
  connexions spéculatives et demande `/favicon.ico`, et laisser l'une d'elles consommer
  l'attente unique perd le vrai redirect. Il doit aussi tamponner un callback arrivé avant
  qu'un attendeur soit prêt, découvrir son port via `stateUpdateHandler` plutôt qu'en
  bloquant un thread du pool coopératif, vérifier le retour de `NSWorkspace.open`, et
  porter un délai maximal ainsi qu'une prise en charge de l'annulation.

Le code de référence intégrant ces deux exigences est conservé dans
`.superpowers/sdd/2026-08-06-stravalocal/task-9-fix-spec.md`.

- [ ] **Step 1: Écrire les tests d'abord**

`Tests/StravaClientTests.swift` :

```swift
import Testing
import Foundation
@testable import StravaLocal

/// Records requests and replays canned responses in order.
private final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Response { let status: Int; let body: Data; let headers: [String: String] }

    private let lock = NSLock()
    private var queue: [Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Response]) { queue = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            requests.append(request)
            let response = queue.isEmpty ? Response(status: 500, body: Data(), headers: [:])
                                         : queue.removeFirst()
            let http = HTTPURLResponse(
                url: request.url!, statusCode: response.status,
                httpVersion: nil, headerFields: response.headers
            )!
            return (response.body, http)
        }
    }
}

private func json(_ string: String) -> Data { Data(string.utf8) }

private let quotaHeaders = [
    "X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "1,1",
]

@Suite("StravaClient")
struct StravaClientTests {
    private func validStore() -> InMemorySecretStore {
        InMemorySecretStore(
            credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
            tokens: StravaTokens(
                accessToken: "good", refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3600)
            )
        )
    }

    @Test("sans credentials, l'appel échoue avant tout réseau")
    func requiresCredentials() async {
        let transport = StubTransport([])
        let client = StravaClient(store: InMemorySecretStore(), transport: transport)
        await #expect(throws: StravaError.self) {
            _ = try await client.athlete()
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("la liste d'activités passe after, page et per_page et porte le jeton")
    func buildsActivityRequest() async throws {
        let transport = StubTransport([
            .init(status: 200, body: json("[]"), headers: quotaHeaders)
        ])
        let client = StravaClient(store: validStore(), transport: transport)
        let result = try await client.activities(after: 1_700_000_000, page: 2, perPage: 200)

        #expect(result.isEmpty)
        let url = transport.requests[0].url!.absoluteString
        #expect(url.contains("/api/v3/athlete/activities"))
        #expect(url.contains("after=1700000000"))
        #expect(url.contains("page=2"))
        #expect(url.contains("per_page=200"))
        #expect(
            transport.requests[0].value(forHTTPHeaderField: "Authorization")
                == "Bearer good"
        )
    }

    @Test("les streams demandent toutes les clés en une requête")
    func requestsAllStreamKeys() async throws {
        let transport = StubTransport([
            .init(
                status: 200,
                body: json(#"{"altitude":{"data":[1.0,2.0]}}"#),
                headers: quotaHeaders
            )
        ])
        let client = StravaClient(store: validStore(), transport: transport)
        let streams = try await client.streams(id: 99)

        #expect(streams.altitude?.data == [1, 2])
        let url = transport.requests[0].url!.absoluteString
        #expect(url.contains("/api/v3/activities/99/streams"))
        #expect(url.contains("key_by_type=true"))
        #expect(url.contains("latlng"))
        #expect(url.contains("heartrate"))
        #expect(url.contains("watts"))
    }

    @Test("un jeton expiré est rafraîchi avant l'appel, puis persisté")
    func refreshesExpiredToken() async throws {
        let store = InMemorySecretStore(
            credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
            tokens: StravaTokens(
                accessToken: "stale", refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(-60)
            )
        )
        let transport = StubTransport([
            .init(
                status: 200,
                body: json(
                    #"{"access_token":"fresh","refresh_token":"r2","expires_at":4000000000}"#
                ),
                headers: [:]
            ),
            .init(status: 200, body: json("[]"), headers: quotaHeaders),
        ])
        let client = StravaClient(store: store, transport: transport)
        _ = try await client.activities(after: 0, page: 1, perPage: 200)

        #expect(transport.requests.count == 2)
        #expect(transport.requests[0].url!.absoluteString.contains("/oauth/token"))
        #expect(
            transport.requests[1].value(forHTTPHeaderField: "Authorization")
                == "Bearer fresh"
        )
        #expect(store.tokens()?.accessToken == "fresh")
        #expect(store.tokens()?.refreshToken == "r2")
    }

    @Test("un refresh refusé purge les jetons sans toucher aux credentials")
    func clearsTokensOnRejectedRefresh() async {
        let store = InMemorySecretStore(
            credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
            tokens: StravaTokens(
                accessToken: "stale", refreshToken: "revoked",
                expiresAt: Date().addingTimeInterval(-60)
            )
        )
        let transport = StubTransport([
            .init(status: 401, body: json(#"{"message":"Unauthorized"}"#), headers: [:])
        ])
        let client = StravaClient(store: store, transport: transport)

        await #expect(throws: StravaError.self) {
            _ = try await client.athlete()
        }
        #expect(store.tokens() == nil)
        #expect(store.credentials() != nil)
    }

    @Test("une erreur HTTP est remontée avec son code")
    func surfacesHTTPErrors() async {
        let transport = StubTransport([
            .init(status: 404, body: json(#"{"message":"Record Not Found"}"#), headers: [:])
        ])
        let client = StravaClient(store: validStore(), transport: transport)
        await #expect(throws: StravaError.self) {
            _ = try await client.activityDetail(id: 1)
        }
    }

    @Test("le quota lu dans les en-têtes est exposé")
    func exposesQuota() async throws {
        let transport = StubTransport([
            .init(
                status: 200, body: json("[]"),
                headers: ["X-RateLimit-Limit": "200,2000", "X-RateLimit-Usage": "17,342"]
            )
        ])
        let client = StravaClient(store: validStore(), transport: transport)
        _ = try await client.activities(after: 0, page: 1, perPage: 200)
        let snapshot = await client.rateLimitSnapshot()
        #expect(snapshot?.shortTermUsage == 17)
        #expect(snapshot?.dailyUsage == 342)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'StravaClient' in scope ».

- [ ] **Step 3: Écrire `StravaError` et `HTTPTransport`**

`StravaLocal/Strava/StravaError.swift` :

```swift
import Foundation

enum StravaError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case notAuthenticated
    case invalidResponse
    case http(Int, String)
    case tokenRefreshRejected
    case oauthCancelled
    case oauthStateMismatch
    case oauthDenied(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Renseignez le Client ID et le Client Secret de votre application Strava dans les réglages."
        case .notAuthenticated:
            "Vous n'êtes pas connecté à Strava."
        case .invalidResponse:
            "Réponse inattendue de Strava."
        case let .http(status, message):
            "Strava a répondu \(status) : \(message)"
        case .tokenRefreshRejected:
            "L'autorisation Strava a expiré ou été révoquée. Reconnectez-vous."
        case .oauthCancelled:
            "Connexion annulée."
        case .oauthStateMismatch:
            "La réponse d'autorisation ne correspond pas à la demande. Réessayez."
        case let .oauthDenied(reason):
            "Strava a refusé l'autorisation : \(reason)"
        }
    }
}

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        return (data, http)
    }
}
```

- [ ] **Step 4: Écrire `StravaClient`**

```swift
import Foundation

/// All Strava REST access. Owns token refresh and quota accounting so callers
/// never think about either.
actor StravaClient {
    private let store: SecretStore
    private let transport: HTTPTransport
    private let rateLimiter: RateLimiter

    private static let apiBase = URL(string: "https://www.strava.com/api/v3")!
    static let tokenEndpoint = URL(string: "https://www.strava.com/oauth/token")!
    private static let streamKeys = [
        "latlng", "altitude", "time", "heartrate", "cadence",
        "watts", "velocity_smooth", "temp", "grade_smooth", "moving",
    ]

    init(
        store: SecretStore,
        transport: HTTPTransport = URLSessionTransport(),
        rateLimiter: RateLimiter = RateLimiter()
    ) {
        self.store = store
        self.transport = transport
        self.rateLimiter = rateLimiter
    }

    var isAuthenticated: Bool { store.tokens() != nil }

    func rateLimitSnapshot() async -> RateLimitSnapshot? {
        await rateLimiter.snapshot
    }

    func signOut() throws { try store.clearTokens() }

    // MARK: - Endpoints

    func activities(
        after epoch: Int, page: Int, perPage: Int
    ) async throws -> [SummaryActivityDTO] {
        try await get(
            [SummaryActivityDTO].self, path: "athlete/activities",
            query: [
                "after": String(epoch), "page": String(page),
                "per_page": String(perPage),
            ]
        )
    }

    func activityDetail(id: Int64) async throws -> DetailActivityDTO {
        try await get(
            DetailActivityDTO.self, path: "activities/\(id)",
            query: ["include_all_efforts": "false"]
        )
    }

    func streams(id: Int64) async throws -> StreamSetDTO {
        try await get(
            StreamSetDTO.self, path: "activities/\(id)/streams",
            query: [
                "keys": Self.streamKeys.joined(separator: ","),
                "key_by_type": "true",
            ]
        )
    }

    func athlete() async throws -> AthleteDTO {
        try await get(AthleteDTO.self, path: "athlete", query: [:])
    }

    func gear(id: String) async throws -> GearDTO {
        try await get(GearDTO.self, path: "gear/\(id)", query: [:])
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(
        _ type: T.Type, path: String, query: [String: String]
    ) async throws -> T {
        let token = try await validAccessToken()

        let delay = await rateLimiter.delayBeforeNextRequest()
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }

        var components = URLComponents(
            url: Self.apiBase.appending(path: path), resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await transport.send(request)
        let headers = response.allHeaderFields.reduce(into: [String: String]()) {
            if let key = $1.key as? String, let value = $1.value as? String {
                $0[key] = value
            }
        }

        switch response.statusCode {
        case 200..<300:
            await rateLimiter.observeSuccess(headers: headers)
            return try StravaJSON.decoder.decode(type, from: data)
        case 429:
            await rateLimiter.observeTooManyRequests()
            throw StravaError.http(429, "Quota d'API dépassé")
        default:
            throw StravaError.http(response.statusCode, Self.message(from: data))
        }
    }

    /// Refreshes proactively rather than reacting to a 401: Strava hands us an
    /// expiry, so a round trip can be skipped instead of wasted.
    private func validAccessToken() async throws -> String {
        guard let credentials = store.credentials() else {
            throw StravaError.missingCredentials
        }
        guard let tokens = store.tokens() else { throw StravaError.notAuthenticated }
        guard tokens.isExpired else { return tokens.accessToken }

        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = Self.formBody([
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
        ])

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode),
              let payload = try? StravaJSON.decoder.decode(TokenResponseDTO.self, from: data)
        else {
            // A rejected refresh means the grant is gone for good; drop the
            // tokens so the UI can ask for a fresh sign-in, but keep the
            // credentials, which are still valid.
            try? store.clearTokens()
            throw StravaError.tokenRefreshRejected
        }

        let refreshed = StravaTokens(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date(timeIntervalSince1970: Double(payload.expires_at))
        )
        try store.save(refreshed)
        return refreshed.accessToken
    }

    static func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func message(from data: Data) -> String {
        struct ErrorPayload: Decodable { let message: String? }
        return (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.message
            ?? String(data: data, encoding: .utf8)
            ?? "erreur inconnue"
    }
}
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Écrire `OAuthFlow`**

Le flux n'est pas couvert par des tests unitaires : il dépend d'un navigateur et d'une socket. Il se vérifie à la main en Task 13.

```swift
import Foundation
import Network
import AppKit

/// RFC 8252 loopback authorisation flow.
///
/// `ASWebAuthenticationSession` is deliberately not used: it can only complete
/// on a custom scheme or an https universal link, never on `http://localhost`,
/// which is the only callback shape Strava's "Authorization Callback Domain"
/// field accepts for a desktop app. Going through the default browser also
/// means the user's existing Strava session is already there.
actor OAuthFlow {
    private let store: SecretStore
    private let transport: HTTPTransport
    private static let scope = "read,activity:read_all,profile:read_all"

    init(store: SecretStore, transport: HTTPTransport = URLSessionTransport()) {
        self.store = store
        self.transport = transport
    }

    func authorize() async throws -> AthleteDTO? {
        guard let credentials = store.credentials() else {
            throw StravaError.missingCredentials
        }

        let listener = try LoopbackListener()
        let port = try listener.start()
        let state = UUID().uuidString

        var components = URLComponents(string: "https://www.strava.com/oauth/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: credentials.clientID),
            .init(name: "redirect_uri", value: "http://localhost:\(port)/callback"),
            .init(name: "response_type", value: "code"),
            .init(name: "approval_prompt", value: "auto"),
            .init(name: "scope", value: Self.scope),
            .init(name: "state", value: state),
        ]
        // The Bool result is discarded explicitly: an unused MainActor.run
        // result is a warning, and test output has to stay pristine.
        await MainActor.run { _ = NSWorkspace.shared.open(components.url!) }

        let callback = try await listener.waitForCallback()
        listener.stop()

        guard callback.state == state else { throw StravaError.oauthStateMismatch }
        if let error = callback.error { throw StravaError.oauthDenied(error) }
        guard let code = callback.code else { throw StravaError.oauthCancelled }

        return try await exchange(code: code, credentials: credentials)
    }

    private func exchange(
        code: String, credentials: StravaCredentials
    ) async throws -> AthleteDTO? {
        var request = URLRequest(url: StravaClient.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = StravaClient.formBody([
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "code": code,
            "grant_type": "authorization_code",
        ])

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw StravaError.http(response.statusCode, "échange du code impossible")
        }
        let payload = try StravaJSON.decoder.decode(TokenResponseDTO.self, from: data)
        try store.save(
            StravaTokens(
                accessToken: payload.access_token,
                refreshToken: payload.refresh_token,
                expiresAt: Date(timeIntervalSince1970: Double(payload.expires_at))
            )
        )
        return payload.athlete
    }
}

/// Minimal one-shot HTTP listener on the loopback interface. It parses exactly
/// one request line, answers a static page, and is done.
private final class LoopbackListener: @unchecked Sendable {
    struct Callback: Sendable {
        let code: String?
        let state: String?
        let error: String?
    }

    private let listener: NWListener
    private var continuation: CheckedContinuation<Callback, Error>?
    private let lock = NSLock()

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: .global(qos: .userInitiated))

        // NWListener assigns the port asynchronously; poll briefly for it.
        for _ in 0..<200 {
            if let port = listener.port?.rawValue, port != 0 { return port }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw StravaError.oauthCancelled
    }

    func stop() {
        listener.cancel()
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
            [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let callback = Self.parse(requestLine: request)

            let body = callback.code != nil
                ? "<h2>Connexion réussie</h2><p>Vous pouvez fermer cet onglet et revenir à StravaLocal.</p>"
                : "<h2>Connexion refusée</h2><p>Revenez à StravaLocal pour réessayer.</p>"
            let response = """
                HTTP/1.1 200 OK\r
                Content-Type: text/html; charset=utf-8\r
                Content-Length: \(body.utf8.count)\r
                Connection: close\r
                \r
                \(body)
                """
            connection.send(
                content: Data(response.utf8),
                completion: .contentProcessed { _ in connection.cancel() }
            )

            let pending = self.lock.withLock {
                let value = self.continuation
                self.continuation = nil
                return value
            }
            pending?.resume(returning: callback)
        }
    }

    private static func parse(requestLine: String) -> Callback {
        guard let line = requestLine.split(separator: "\r\n").first,
              let path = line.split(separator: " ").dropFirst().first,
              let components = URLComponents(string: "http://localhost\(path)")
        else {
            return Callback(code: nil, state: nil, error: "requête illisible")
        }
        func item(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }
        return Callback(code: item("code"), state: item("state"), error: item("error"))
    }
}
```

- [ ] **Step 7: Vérifier que tout compile et que les tests passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
git add StravaLocal/Strava Tests/StravaClientTests.swift
git commit -m "feat(strava): client API et flux OAuth loopback"
```

---

### Task 10: ImportMapper

Deliverable : un DTO devient une `Activity` complète avec bbox et trace simplifiée, et un réimport met à jour au lieu de dupliquer.

**Files:**
- Create: `StravaLocal/Sync/ImportMapper.swift`
- Create: `Tests/ImportMapperTests.swift`

**Interfaces:**
- Consumes: DTOs (Task 6), modèles (Task 5), `Polyline`, `Simplify`, `BoundingBox`, `TrackBlob` (Tasks 2-4).
- Produces:
  - `struct ImportMapper { init(context: ModelContext); @discardableResult func upsert(summary: SummaryActivityDTO) throws -> Activity; func apply(detail: DetailActivityDTO, to activity: Activity) throws; func apply(streams: StreamSetDTO, to activity: Activity); @discardableResult func upsert(athlete: AthleteDTO) throws -> Athlete; @discardableResult func upsert(gear: GearDTO) throws -> Gear; func activity(stravaID: Int64) throws -> Activity? }`

Seul point de contact entre le monde DTO et le monde SwiftData. Toutes les méthodes sont idempotentes.

- [ ] **Step 1: Écrire les tests d'abord**

`Tests/ImportMapperTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("ImportMapper")
struct ImportMapperTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    @Test("mappe une activité résumée complète")
    func mapsSummary() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(SummaryActivityDTO.self, "summary_activity")

        let activity = try mapper.upsert(summary: dto)
        try context.save()

        #expect(activity.stravaID == 10_123_456_789)
        #expect(activity.name == "Sortie matinale")
        #expect(activity.sportType == .ride)
        #expect(activity.distance == 45_231.4)
        #expect(activity.movingTime == 5412)
        #expect(activity.totalElevationGain == 612)
        #expect(activity.averageHeartrate == 138.4)
        #expect(activity.weightedAverageWatts == 178)
        #expect(activity.kudosCount == 12)
        #expect(activity.isCommute == false)
        #expect(activity.startLatitude == 45.764043)
        #expect(activity.endLongitude == 4.842)
        #expect(activity.summaryPolyline == "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    }

    @Test("la trace simplifiée et la bbox sont dérivées de la polyline de résumé")
    func derivesTrackAndBox() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(SummaryActivityDTO.self, "summary_activity")

        let activity = try mapper.upsert(summary: dto)

        #expect(activity.hasTrack)
        #expect(activity.simplifiedCoordinates.count >= 2)
        let box = activity.boundingBox
        #expect(box != nil)
        #expect(box!.minLat < box!.maxLat)
        // La polyline de référence va de 38.5 à 43.252 de latitude.
        #expect(abs(box!.minLat - 38.5) < 0.001)
        #expect(abs(box!.maxLat - 43.252) < 0.001)
    }

    @Test("une activité manuelle sans trace reste importable")
    func mapsManualActivity() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(SummaryActivityDTO.self, "manual_activity")

        let activity = try mapper.upsert(summary: dto)

        #expect(activity.isManual)
        #expect(activity.sportType == .workout)
        #expect(!activity.hasTrack)
        #expect(activity.simplifiedTrack == nil)
        #expect(activity.startLatitude == nil)
        #expect(activity.averageHeartrate == nil)
        #expect(activity.kudosCount == 0)
    }

    @Test("réimporter la même activité met à jour sans dupliquer")
    func upsertIsIdempotent() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(SummaryActivityDTO.self, "summary_activity")

        _ = try mapper.upsert(summary: dto)
        try context.save()
        let again = try mapper.upsert(summary: dto)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Activity>())
        #expect(all.count == 1)
        #expect(again.persistentModelID == all[0].persistentModelID)
    }

    @Test("les streams sont packés et rattachés")
    func mapsStreams() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let streams = try Fixture.decode(StreamSetDTO.self, "streams")

        mapper.apply(streams: streams, to: activity)
        try context.save()

        #expect(activity.streams?.pointCount == 3)
        #expect(
            activity.streams?.altitude.map(TrackBlob.decodeScalars) == [172.4, 175.1, 180.9]
        )
        #expect(activity.streams?.time.map(TrackBlob.decodeTimes) == [0, 5, 11])
        #expect(activity.streams?.heartrate.map(TrackBlob.decodeScalars) == [96, 104, 118])
        #expect(activity.streams?.watts == nil)
        // moving est un stream de booléens → packé en 0/1
        #expect(activity.streams?.moving.map(TrackBlob.decodeScalars) == [0, 1, 1])
    }

    @Test("le stream latlng remplace la trace simplifiée issue de la polyline")
    func streamsRefineTrack() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        mapper.apply(
            streams: try Fixture.decode(StreamSetDTO.self, "streams"), to: activity
        )

        // Les streams de la fixture sont à Lyon, la polyline de résumé en Californie.
        let box = activity.boundingBox!
        #expect(abs(box.minLat - 45.764043) < 0.001)
        #expect(abs(box.maxLon - 4.837) < 0.001)
        #expect(activity.streams?.coordinates.count == 3)
    }

    @Test("réappliquer des streams ne crée pas un second enregistrement")
    func streamsUpsert() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let streams = try Fixture.decode(StreamSetDTO.self, "streams")

        mapper.apply(streams: streams, to: activity)
        try context.save()
        mapper.apply(streams: streams, to: activity)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ActivityStreams>()).count == 1)
    }

    @Test("le détail ajoute description, calories et laps")
    func mapsDetail() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let detail = DetailActivityDTO(
            id: 10_123_456_789,
            description: "Belle sortie",
            calories: 812,
            device_name: "Garmin Edge 840",
            laps: [
                LapDTO(
                    id: 1, name: "Lap 1", lap_index: 1, distance: 20_000,
                    moving_time: 2600, elapsed_time: 2700, total_elevation_gain: 300,
                    average_speed: 7.7, max_speed: 15, average_heartrate: 135,
                    average_cadence: 80, start_index: 0, end_index: 1500
                )
            ]
        )

        try mapper.apply(detail: detail, to: activity)
        try context.save()

        #expect(activity.activityDescription == "Belle sortie")
        #expect(activity.calories == 812)
        #expect(activity.deviceName == "Garmin Edge 840")
        #expect(activity.detailFetchedAt != nil)
        #expect(activity.laps.count == 1)
        #expect(activity.laps[0].distance == 20_000)
        #expect(activity.laps[0].endIndex == 1500)
    }

    @Test("réappliquer le détail remplace les laps au lieu de les accumuler")
    func detailReplacesLaps() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let activity = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        let lap = LapDTO(
            id: 1, name: "Lap 1", lap_index: 1, distance: 1000, moving_time: 100,
            elapsed_time: 100, total_elevation_gain: 0, average_speed: 10,
            max_speed: 12, average_heartrate: nil, average_cadence: nil,
            start_index: 0, end_index: 10
        )
        let detail = DetailActivityDTO(
            id: 10_123_456_789, description: nil, calories: nil,
            device_name: nil, laps: [lap]
        )

        try mapper.apply(detail: detail, to: activity)
        try context.save()
        try mapper.apply(detail: detail, to: activity)
        try context.save()

        #expect(activity.laps.count == 1)
        #expect(try context.fetch(FetchDescriptor<Lap>()).count == 1)
    }

    @Test("l'athlète est unique et mis à jour")
    func upsertsAthlete() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        let dto = try Fixture.decode(AthleteDTO.self, "athlete")

        _ = try mapper.upsert(athlete: dto)
        try context.save()
        let second = try mapper.upsert(athlete: dto)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Athlete>()).count == 1)
        #expect(second.fullName == "Florian Maisonnial")
        #expect(second.city == "Lyon")
    }

    @Test("retrouve une activité par son identifiant Strava")
    func findsByStravaID() throws {
        let context = try makeContext()
        let mapper = ImportMapper(context: context)
        _ = try mapper.upsert(
            summary: try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        )
        try context.save()

        #expect(try mapper.activity(stravaID: 10_123_456_789) != nil)
        #expect(try mapper.activity(stravaID: 1) == nil)
    }
}
```

Note : `DetailActivityDTO` et `LapDTO` sont construits directement dans les tests, ce qui exige des initialiseurs mémberwise accessibles. Les `struct` `Decodable` sans initialiseur explicite en ont un, mais il est `internal` — c'est suffisant ici puisque les tests utilisent `@testable import`.

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'ImportMapper' in scope ».

- [ ] **Step 3: Écrire `ImportMapper`**

```swift
import Foundation
import SwiftData

/// The single bridge between Strava DTOs and SwiftData models.
///
/// Every method is an upsert keyed on the Strava identifier, which is what makes
/// an interrupted sync safe to simply run again.
struct ImportMapper {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func activity(stravaID: Int64) throws -> Activity? {
        var descriptor = FetchDescriptor<Activity>(
            predicate: #Predicate { $0.stravaID == stravaID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func upsert(summary dto: SummaryActivityDTO) throws -> Activity {
        let activity = try activity(stravaID: dto.id)
            ?? {
                let new = Activity(
                    stravaID: dto.id, name: dto.name,
                    sportType: SportType(stravaValue: dto.sport_type)
                )
                context.insert(new)
                return new
            }()

        activity.name = dto.name
        activity.sportType = SportType(stravaValue: dto.sport_type)
        activity.startDate = dto.start_date
        activity.startLocalDate = dto.start_date_local
        activity.timezoneIdentifier = dto.timezone

        activity.distance = dto.distance
        activity.movingTime = dto.moving_time
        activity.elapsedTime = dto.elapsed_time
        activity.totalElevationGain = dto.total_elevation_gain
        activity.averageSpeed = dto.average_speed
        activity.maxSpeed = dto.max_speed
        activity.averageHeartrate = dto.average_heartrate
        activity.maxHeartrate = dto.max_heartrate
        activity.averageWatts = dto.average_watts
        activity.weightedAverageWatts = dto.weighted_average_watts
        activity.kilojoules = dto.kilojoules
        activity.averageCadence = dto.average_cadence

        activity.isCommute = dto.commute ?? false
        activity.isTrainer = dto.trainer ?? false
        activity.isManual = dto.manual ?? false
        activity.isPrivate = dto.private ?? false

        activity.kudosCount = dto.kudos_count ?? 0
        activity.achievementCount = dto.achievement_count ?? 0
        activity.prCount = dto.pr_count ?? 0
        activity.athleteCount = dto.athlete_count ?? 1

        let start = Self.coordinate(dto.start_latlng)
        let end = Self.coordinate(dto.end_latlng)
        activity.startLatitude = start?.latitude
        activity.startLongitude = start?.longitude
        activity.endLatitude = end?.latitude
        activity.endLongitude = end?.longitude

        activity.summaryPolyline = dto.map?.summary_polyline

        if let gearID = dto.gear_id, !gearID.isEmpty {
            activity.gearID = gearID
            activity.gear = try existingGear(stravaID: gearID)
        }

        // Only derive the track from the summary polyline while the real streams
        // are still missing — they produce a strictly better track.
        if activity.streams?.latlng == nil {
            applyTrack(from: dto.map?.summary_polyline, to: activity)
        }
        return activity
    }

    func apply(detail dto: DetailActivityDTO, to activity: Activity) throws {
        activity.activityDescription = dto.description
        activity.calories = dto.calories
        activity.deviceName = dto.device_name
        activity.detailFetchedAt = Date()

        // Laps are replaced wholesale: they're cheap, and diffing them would be
        // more code than it saves.
        for lap in activity.laps { context.delete(lap) }
        activity.laps = []

        for lapDTO in dto.laps ?? [] {
            let lap = Lap(stravaID: lapDTO.id, lapIndex: lapDTO.lap_index)
            lap.name = lapDTO.name ?? "Tour \(lapDTO.lap_index)"
            lap.distance = lapDTO.distance
            lap.movingTime = lapDTO.moving_time
            lap.elapsedTime = lapDTO.elapsed_time
            lap.totalElevationGain = lapDTO.total_elevation_gain ?? 0
            lap.averageSpeed = lapDTO.average_speed ?? 0
            lap.maxSpeed = lapDTO.max_speed ?? 0
            lap.averageHeartrate = lapDTO.average_heartrate
            lap.averageCadence = lapDTO.average_cadence
            lap.startIndex = lapDTO.start_index ?? 0
            lap.endIndex = lapDTO.end_index ?? 0
            lap.activity = activity
            context.insert(lap)
            activity.laps.append(lap)
        }
    }

    func apply(streams dto: StreamSetDTO, to activity: Activity) {
        let streams = activity.streams ?? {
            let new = ActivityStreams()
            new.activity = activity
            context.insert(new)
            activity.streams = new
            return new
        }()

        let coordinates = (dto.latlng?.data ?? []).compactMap { pair -> Coordinate? in
            guard pair.count == 2 else { return nil }
            return Coordinate(latitude: pair[0], longitude: pair[1])
        }

        streams.latlng = coordinates.isEmpty
            ? nil : TrackBlob.encode(coordinates: coordinates)
        streams.altitude = Self.pack(dto.altitude?.data)
        streams.heartrate = Self.pack(dto.heartrate?.data)
        streams.cadence = Self.pack(dto.cadence?.data)
        streams.watts = Self.pack(dto.watts?.data)
        streams.velocitySmooth = Self.pack(dto.velocity_smooth?.data)
        streams.temp = Self.pack(dto.temp?.data)
        streams.grade = Self.pack(dto.grade_smooth?.data)
        streams.moving = Self.pack(dto.moving?.data.map { $0 ? 1.0 : 0.0 })
        streams.time = dto.time?.data.map { Int32($0) }
            .nonEmpty.map(TrackBlob.encode(times:))
        streams.pointCount = max(
            coordinates.count,
            dto.time?.data.count ?? dto.altitude?.data.count ?? 0
        )

        if !coordinates.isEmpty {
            applyTrack(coordinates: coordinates, to: activity)
        }
    }

    @discardableResult
    func upsert(athlete dto: AthleteDTO) throws -> Athlete {
        let stravaID = dto.id
        var descriptor = FetchDescriptor<Athlete>(
            predicate: #Predicate { $0.stravaID == stravaID }
        )
        descriptor.fetchLimit = 1
        let athlete = try context.fetch(descriptor).first
            ?? {
                let new = Athlete(stravaID: stravaID)
                context.insert(new)
                return new
            }()

        athlete.firstName = dto.firstname ?? ""
        athlete.lastName = dto.lastname ?? ""
        athlete.city = dto.city
        athlete.country = dto.country
        athlete.profileImageURL = dto.profile
        athlete.weight = dto.weight
        athlete.updatedAt = Date()
        return athlete
    }

    @discardableResult
    func upsert(gear dto: GearDTO) throws -> Gear {
        let gear = try existingGear(stravaID: dto.id) ?? {
            let new = Gear(stravaID: dto.id, name: dto.name)
            context.insert(new)
            return new
        }()
        gear.name = dto.name
        gear.brandName = dto.brand_name
        gear.modelName = dto.model_name
        gear.isBike = dto.id.hasPrefix("b")
        gear.totalDistance = dto.distance ?? 0
        return gear
    }

    // MARK: - Helpers

    private func existingGear(stravaID: String) throws -> Gear? {
        var descriptor = FetchDescriptor<Gear>(
            predicate: #Predicate { $0.stravaID == stravaID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func applyTrack(from polyline: String?, to activity: Activity) {
        guard let polyline, !polyline.isEmpty else { return }
        applyTrack(coordinates: Polyline.decode(polyline), to: activity)
    }

    private func applyTrack(coordinates: [Coordinate], to activity: Activity) {
        guard let box = BoundingBox(coordinates: coordinates) else { return }
        activity.apply(simplifiedCoordinates: Simplify.douglasPeucker(coordinates))
        activity.apply(boundingBox: box)
    }

    private static func coordinate(_ pair: [Double]?) -> Coordinate? {
        guard let pair, pair.count == 2 else { return nil }
        return Coordinate(latitude: pair[0], longitude: pair[1])
    }

    private static func pack(_ values: [Double]?) -> Data? {
        guard let values, !values.isEmpty else { return nil }
        return TrackBlob.encode(scalars: values.map(Float.init))
    }
}

private extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Sync/ImportMapper.swift Tests/ImportMapperTests.swift
git commit -m "feat(sync): mapping idempotent des DTOs Strava vers SwiftData"
```

---

### Task 11: Moteur de synchro — phase A (résumés)

Deliverable : une synchro remplit la base avec toutes les métadonnées, bbox et traces simplifiées, publie sa progression, et reprend en incrémental au deuxième passage.

**Files:**
- Create: `StravaLocal/Sync/SyncProgress.swift`
- Create: `StravaLocal/Sync/SyncEngine.swift`
- Create: `Tests/SyncEngineTests.swift`

**Interfaces:**
- Consumes: `StravaClient` (Task 9), `ImportMapper` (Task 10), `SyncState` (Task 5).
- Produces:
  - `enum SyncPhase: Sendable, Equatable { case idle, summaries(page: Int), streams(done: Int, total: Int), waitingForQuota(until: Date), failed(String) }`
  - `@MainActor @Observable final class SyncProgress { var phase: SyncPhase; var lastRunAt: Date?; var quota: RateLimitSnapshot?; var isRunning: Bool { get }; var statusText: String { get } }`
  - `protocol ActivitySource: Sendable { func activities(after: Int, page: Int, perPage: Int) async throws -> [SummaryActivityDTO]; func streams(id: Int64) async throws -> StreamSetDTO; func activityDetail(id: Int64) async throws -> DetailActivityDTO; func athlete() async throws -> AthleteDTO; func rateLimitSnapshot() async -> RateLimitSnapshot? }` + `extension StravaClient: ActivitySource {}`
  - `actor SyncEngine { init(source: ActivitySource, container: ModelContainer, progress: SyncProgress); func syncSummaries() async throws -> Int; func state() throws -> SyncState }`

`ActivitySource` existe pour que `SyncEngine` soit testable avec une source en dur, sans HTTP du tout.

- [ ] **Step 1: Écrire les tests d'abord**

`Tests/SyncEngineTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import StravaLocal

/// Serves pages of canned summaries and records what was asked for.
private actor FakeSource: ActivitySource {
    private let pages: [[SummaryActivityDTO]]
    private(set) var requestedAfter: [Int] = []
    private(set) var streamRequests: [Int64] = []
    private(set) var gearRequests: [String] = []
    var streamsToReturn = StreamSetDTO(
        latlng: StreamDTO(data: [[45.0, 4.0], [45.001, 4.001]]),
        altitude: StreamDTO(data: [100, 110]), time: StreamDTO(data: [0, 10]),
        heartrate: nil, cadence: nil, watts: nil, velocity_smooth: nil,
        temp: nil, grade_smooth: nil, moving: nil
    )

    init(pages: [[SummaryActivityDTO]]) { self.pages = pages }

    func activities(
        after: Int, page: Int, perPage: Int
    ) async throws -> [SummaryActivityDTO] {
        requestedAfter.append(after)
        guard page - 1 < pages.count else { return [] }
        return pages[page - 1]
    }

    func streams(id: Int64) async throws -> StreamSetDTO {
        streamRequests.append(id)
        return streamsToReturn
    }

    func activityDetail(id: Int64) async throws -> DetailActivityDTO {
        DetailActivityDTO(
            id: id, description: nil, calories: nil, device_name: nil, laps: nil
        )
    }

    func athlete() async throws -> AthleteDTO {
        AthleteDTO(
            id: 1, firstname: "Test", lastname: "User", city: nil,
            country: nil, profile: nil, weight: nil
        )
    }

    func gear(id: String) async throws -> GearDTO {
        gearRequests.append(id)
        return GearDTO(
            id: id, name: "Vélo de test", brand_name: "Marque",
            model_name: "Modèle", distance: 12_345
        )
    }

    func rateLimitSnapshot() async -> RateLimitSnapshot? { nil }
}

private func makeSummary(
    id: Int64, epoch: Int, sport: String = "Ride", gearID: String? = nil
) -> SummaryActivityDTO {
    SummaryActivityDTO(
        id: id, name: "Activité \(id)", sport_type: sport,
        start_date: Date(timeIntervalSince1970: Double(epoch)),
        start_date_local: Date(timeIntervalSince1970: Double(epoch)),
        timezone: nil, distance: 10_000, moving_time: 3600, elapsed_time: 3700,
        total_elevation_gain: 100, average_speed: 2.7, max_speed: 5,
        average_heartrate: nil, max_heartrate: nil, average_watts: nil,
        weighted_average_watts: nil, kilojoules: nil, average_cadence: nil,
        commute: nil, trainer: nil, manual: nil, `private`: nil,
        kudos_count: nil, achievement_count: nil, pr_count: nil,
        athlete_count: nil, start_latlng: nil, end_latlng: nil, gear_id: gearID,
        map: MapDTO(summary_polyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    )
}

@Suite("SyncEngine — phase A")
@MainActor
struct SyncSummariesTests {
    @Test("importe toutes les pages jusqu'à une page vide")
    func importsAllPages() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000)],
            [makeSummary(id: 3, epoch: 3000)],
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        let imported = try await engine.syncSummaries()
        #expect(imported == 3)

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<Activity>()).count == 3)
    }

    @Test("la trace simplifiée et la bbox sont renseignées dès la phase A")
    func fillsTrackInPhaseA() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let context = ModelContext(container)
        let activity = try context.fetch(FetchDescriptor<Activity>())[0]
        #expect(activity.hasTrack)
        #expect(!activity.simplifiedCoordinates.isEmpty)
    }

    @Test("les activités importées entrent dans la file d'attente des streams")
    func queuesStreams() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000)]
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let state = try engine.state()
        #expect(Set(state.pendingStreamIDs) == [1, 2])
    }

    @Test("le curseur retient la date la plus récente")
    func advancesCursor() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 5000)]
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        #expect(try engine.state().lastSummaryEpoch == 5000)
        #expect(try engine.state().isInitialImportDone)
    }

    @Test("la deuxième synchro repart du curseur")
    func secondRunIsIncremental() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 5000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        _ = try await engine.syncSummaries()
        _ = try await engine.syncSummaries()

        let asked = await source.requestedAfter
        #expect(asked.first == 0)
        #expect(asked.contains(5000))
    }

    @Test("réimporter les mêmes activités ne duplique rien")
    func rerunIsIdempotent() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        _ = try await engine.syncSummaries()
        _ = try await engine.syncSummaries()

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<Activity>()).count == 1)
    }

    @Test("la progression retombe à idle en fin de synchro")
    func reportsProgress() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let progress = SyncProgress()
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: progress
        )

        _ = try await engine.syncSummaries()

        #expect(progress.phase == .idle)
        #expect(progress.lastRunAt != nil)
        #expect(!progress.isRunning)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'SyncEngine' in scope ».

- [ ] **Step 3: Écrire `SyncProgress`**

```swift
import Foundation
import Observation

enum SyncPhase: Sendable, Equatable {
    case idle
    case summaries(page: Int)
    case streams(done: Int, total: Int)
    case waitingForQuota(until: Date)
    case failed(String)
}

/// UI-facing sync state. Lives on the main actor so views can observe it
/// directly; the engine pushes updates into it.
@MainActor
@Observable
final class SyncProgress {
    var phase: SyncPhase = .idle
    var lastRunAt: Date?
    var quota: RateLimitSnapshot?

    var isRunning: Bool {
        switch phase {
        case .idle, .failed: false
        case .summaries, .streams, .waitingForQuota: true
        }
    }

    var statusText: String {
        switch phase {
        case .idle:
            lastRunAt.map {
                "Dernière synchro \($0.formatted(date: .abbreviated, time: .shortened))"
            } ?? "Jamais synchronisé"
        case let .summaries(page):
            "Import des activités… (page \(page))"
        case let .streams(done, total):
            "Import des traces… \(done)/\(total)"
        case let .waitingForQuota(until):
            "Quota Strava atteint, reprise à \(until.formatted(date: .omitted, time: .shortened))"
        case let .failed(message):
            "Échec : \(message)"
        }
    }

    var fractionCompleted: Double? {
        guard case let .streams(done, total) = phase, total > 0 else { return nil }
        return Double(done) / Double(total)
    }
}
```

- [ ] **Step 4: Écrire `SyncEngine` (phase A seulement)**

```swift
import Foundation
import SwiftData

/// Abstracts the network away from the engine so a sync can be tested end to
/// end without HTTP.
protocol ActivitySource: Sendable {
    func activities(after: Int, page: Int, perPage: Int) async throws -> [SummaryActivityDTO]
    func streams(id: Int64) async throws -> StreamSetDTO
    func activityDetail(id: Int64) async throws -> DetailActivityDTO
    func athlete() async throws -> AthleteDTO
    func gear(id: String) async throws -> GearDTO
    func rateLimitSnapshot() async -> RateLimitSnapshot?
}

/// `StravaClient` already has every one of these signatures, so the conformance
/// needs no bridging methods — adding one here would just recurse.
extension StravaClient: ActivitySource {}

actor SyncEngine {
    private let source: ActivitySource
    private let container: ModelContainer
    private let progress: SyncProgress
    private let context: ModelContext
    private let mapper: ImportMapper

    private static let pageSize = 200

    init(source: ActivitySource, container: ModelContainer, progress: SyncProgress) {
        self.source = source
        self.container = container
        self.progress = progress
        let context = ModelContext(container)
        self.context = context
        self.mapper = ImportMapper(context: context)
    }

    /// Single-row sync state, created on first access.
    func state() throws -> SyncState {
        if let existing = try context.fetch(FetchDescriptor<SyncState>()).first {
            return existing
        }
        let created = SyncState()
        context.insert(created)
        try context.save()
        return created
    }

    /// Phase A: walk the summary endpoint. A handful of requests covers an
    /// entire history, so the list and the global map become usable long before
    /// streams are done.
    @discardableResult
    func syncSummaries() async throws -> Int {
        let state = try state()
        let after = state.lastSummaryEpoch
        var page = 1
        var imported = 0
        var newestEpoch = after

        do {
            while true {
                await setPhase(.summaries(page: page))
                let batch = try await source.activities(
                    after: after, page: page, perPage: Self.pageSize
                )
                if batch.isEmpty { break }

                for dto in batch {
                    let activity = try mapper.upsert(summary: dto)
                    if activity.streams?.latlng == nil,
                       !state.pendingStreamIDs.contains(dto.id) {
                        state.pendingStreamIDs.append(dto.id)
                    }
                    newestEpoch = max(newestEpoch, Int(dto.start_date.timeIntervalSince1970))
                    imported += 1
                }
                try context.save()
                page += 1
            }

            state.lastSummaryEpoch = newestEpoch
            state.isInitialImportDone = true
            state.lastRunAt = Date()
            state.lastErrorMessage = nil
            try context.save()

            let snapshot = await source.rateLimitSnapshot()
            await finish(quota: snapshot, at: state.lastRunAt)
            return imported
        } catch {
            state.lastErrorMessage = error.localizedDescription
            try? context.save()
            await setPhase(.failed(error.localizedDescription))
            throw error
        }
    }

    private func setPhase(_ phase: SyncPhase) async {
        await MainActor.run { progress.phase = phase }
    }

    private func finish(quota: RateLimitSnapshot?, at date: Date?) async {
        await MainActor.run {
            progress.phase = .idle
            progress.quota = quota
            progress.lastRunAt = date
        }
    }
}
```

- [ ] **Step 5: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add StravaLocal/Sync Tests/SyncEngineTests.swift
git commit -m "feat(sync): phase A — import des résumés d'activités"
```

---

### Task 12: Moteur de synchro — phase B (streams)

Deliverable : la file d'attente des streams se vide activité par activité, s'interrompt proprement sur quota ou annulation, et reprend intacte.

**Files:**
- Modify: `StravaLocal/Sync/SyncEngine.swift`
- Modify: `Tests/SyncEngineTests.swift`

**Interfaces:**
- Consumes: tout ce que produit la Task 11.
- Produces, ajouté à `SyncEngine` :
  - `func syncStreams(limit: Int? = nil) async throws -> Int`
  - `func syncAll() async throws`
  - `func syncGear() async throws`
  - `func fetchDetailIfNeeded(stravaID: Int64) async throws`
  - `func syncAthlete() async throws`
  - `ActivitySource` gagne `func gear(id: String) async throws -> GearDTO`, et `Activity` gagne `var gearID: String?` (Task 5) : sans lui, un identifiant de matériel connu avant le matériel lui-même serait perdu.

- [ ] **Step 1: Écrire les tests d'abord**

Ajouter à `Tests/SyncEngineTests.swift` :

```swift
@Suite("SyncEngine — phase B")
@MainActor
struct SyncStreamsTests {
    @Test("vide la file d'attente et rattache les streams")
    func drainsQueue() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000)]
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let fetched = try await engine.syncStreams()

        #expect(fetched == 2)
        #expect(Set(await source.streamRequests) == [1, 2])
        #expect(try engine.state().pendingStreamIDs.isEmpty)

        let context = ModelContext(container)
        let activities = try context.fetch(FetchDescriptor<Activity>())
        #expect(activities.allSatisfy { $0.streams?.latlng != nil })
        #expect(activities.allSatisfy { $0.streams?.pointCount == 2 })
    }

    @Test("respecte la limite passée et laisse le reste en attente")
    func honoursLimit() async throws {
        let source = FakeSource(pages: [
            [
                makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000),
                makeSummary(id: 3, epoch: 3000),
            ]
        ])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let fetched = try await engine.syncStreams(limit: 2)

        #expect(fetched == 2)
        #expect(try engine.state().pendingStreamIDs.count == 1)
    }

    @Test("reprendre après un arrêt ne redemande pas ce qui est déjà là")
    func resumesWithoutRefetching() async throws {
        let source = FakeSource(pages: [
            [
                makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000),
                makeSummary(id: 3, epoch: 3000),
            ]
        ])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        _ = try await engine.syncStreams(limit: 1)
        _ = try await engine.syncStreams()

        let requests = await source.streamRequests
        #expect(requests.count == 3)
        #expect(Set(requests).count == 3)
    }

    @Test("une file vide ne déclenche aucune requête")
    func emptyQueueDoesNothing() async throws {
        let source = FakeSource(pages: [[]])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        #expect(try await engine.syncStreams() == 0)
        #expect(await source.streamRequests.isEmpty)
    }

    @Test("le détail n'est récupéré qu'une seule fois")
    func fetchesDetailOnce() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        try await engine.fetchDetailIfNeeded(stravaID: 1)
        let context = ModelContext(container)
        let first = try context.fetch(FetchDescriptor<Activity>())[0].detailFetchedAt
        #expect(first != nil)

        try await engine.fetchDetailIfNeeded(stravaID: 1)
        let second = try ModelContext(container)
            .fetch(FetchDescriptor<Activity>())[0].detailFetchedAt
        #expect(second == first)
    }

    @Test("le matériel référencé est récupéré une fois et rattaché")
    func linksGear() async throws {
        let source = FakeSource(pages: [
            [
                makeSummary(id: 1, epoch: 1000, gearID: "b123"),
                makeSummary(id: 2, epoch: 2000, gearID: "b123"),
                makeSummary(id: 3, epoch: 3000),
            ]
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        try await engine.syncGear()

        // Un seul appel réseau pour deux activités partageant le même vélo.
        #expect(await source.gearRequests == ["b123"])

        let context = ModelContext(container)
        let activities = try context.fetch(FetchDescriptor<Activity>())
            .sorted { $0.stravaID < $1.stravaID }
        #expect(activities[0].gear?.name == "Vélo de test")
        #expect(activities[1].gear?.name == "Vélo de test")
        #expect(activities[2].gear == nil)
        #expect(try context.fetch(FetchDescriptor<Gear>()).count == 1)
    }

    @Test("relancer syncGear ne redemande pas ce qui est déjà rattaché")
    func gearSyncIsIdempotent() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000, gearID: "b123")]
        ])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        try await engine.syncGear()
        try await engine.syncGear()

        #expect(await source.gearRequests == ["b123"])
    }

    @Test("syncAll enchaîne les deux phases")
    func syncAllRunsBothPhases() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        let progress = SyncProgress()
        let engine = SyncEngine(
            source: source, container: container, progress: progress
        )

        try await engine.syncAll()

        let context = ModelContext(container)
        let activity = try context.fetch(FetchDescriptor<Activity>())[0]
        #expect(activity.streams?.latlng != nil)
        #expect(progress.phase == .idle)
        #expect(try engine.state().pendingStreamIDs.isEmpty)
    }

    @Test("l'annulation laisse la file exploitable")
    func cancellationLeavesQueueIntact() async throws {
        let source = FakeSource(pages: [
            [
                makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000),
                makeSummary(id: 3, epoch: 3000),
            ]
        ])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let task = Task { try await engine.syncStreams() }
        task.cancel()
        _ = try? await task.value

        // Où que l'annulation tombe, rien n'est perdu : chaque activité est soit
        // déjà récupérée, soit encore dans la file.
        let remaining = try engine.state().pendingStreamIDs.count
        let done = await source.streamRequests.count
        #expect(remaining + done == 3)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « value of type 'SyncEngine' has no member 'syncStreams' ».

- [ ] **Step 3: Ajouter la phase B à `SyncEngine`**

Insérer ces méthodes dans `actor SyncEngine`, après `syncSummaries()` :

```swift
    /// Phase B: one request per activity, popped off a persisted queue.
    ///
    /// The queue entry is only removed once the streams are saved, so an
    /// interruption at any point leaves the work still recorded as pending.
    @discardableResult
    func syncStreams(limit: Int? = nil) async throws -> Int {
        let state = try state()
        let total = state.pendingStreamIDs.count
        guard total > 0 else {
            await finish(quota: await source.rateLimitSnapshot(), at: state.lastRunAt)
            return 0
        }

        var fetched = 0
        let budget = limit ?? total

        while fetched < budget {
            if Task.isCancelled { break }
            let current = try state()
            guard let stravaID = current.pendingStreamIDs.first else { break }
            await setPhase(.streams(done: fetched, total: min(budget, total)))

            do {
                let streams = try await source.streams(id: stravaID)
                if let activity = try mapper.activity(stravaID: stravaID) {
                    mapper.apply(streams: streams, to: activity)
                }
                try dequeue(stravaID)
                fetched += 1
            } catch let StravaError.http(status, message) where status == 404 {
                // The activity is gone from Strava: dropping it from the queue
                // is the only way to make progress.
                try dequeue(stravaID)
                current.lastErrorMessage =
                    "Activité \(stravaID) introuvable : \(message)"
                try context.save()
            } catch let StravaError.http(status, _) where status == 429 {
                let resumeAt = Date().addingTimeInterval(15 * 60)
                await setPhase(.waitingForQuota(until: resumeAt))
                current.lastErrorMessage = "Quota Strava atteint"
                try context.save()
                return fetched
            }
        }

        let finalState = try state()
        finalState.lastRunAt = Date()
        try context.save()
        await finish(quota: await source.rateLimitSnapshot(), at: finalState.lastRunAt)
        return fetched
    }

    private func dequeue(_ stravaID: Int64) throws {
        let state = try state()
        state.pendingStreamIDs.removeAll { $0 == stravaID }
        try context.save()
    }

    func syncAll() async throws {
        try await syncAthlete()
        try await syncSummaries()
        try await syncGear()
        try await syncStreams()
    }

    /// Fetches the gear referenced by imported activities and links it up. Only
    /// a handful of requests — a rider owns a few bikes, not a few thousand.
    func syncGear() async throws {
        let activities = try context.fetch(
            FetchDescriptor<Activity>(predicate: #Predicate { $0.gearID != nil })
        )
        let unlinked = activities.filter { $0.gear == nil }
        guard !unlinked.isEmpty else { return }

        for gearID in Set(unlinked.compactMap(\.gearID)) {
            let dto: GearDTO
            do {
                dto = try await source.gear(id: gearID)
            } catch {
                // Deleted or inaccessible gear must not stall the whole sync.
                continue
            }
            let gear = try mapper.upsert(gear: dto)
            for activity in unlinked where activity.gearID == gearID {
                activity.gear = gear
            }
        }
        try context.save()
    }

    func syncAthlete() async throws {
        let dto = try await source.athlete()
        try mapper.upsert(athlete: dto)
        try context.save()
    }

    /// Fetches the detail endpoint lazily, on first open of an activity. Halves
    /// the cost of the initial sync compared to fetching it up front.
    func fetchDetailIfNeeded(stravaID: Int64) async throws {
        guard let activity = try mapper.activity(stravaID: stravaID),
              activity.detailFetchedAt == nil
        else { return }
        let detail = try await source.activityDetail(id: stravaID)
        try mapper.apply(detail: detail, to: activity)
        try context.save()
    }
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal/Sync/SyncEngine.swift Tests/SyncEngineTests.swift
git commit -m "feat(sync): phase B — import des streams avec file reprenable"
```

---

### Task 13: Réglages, connexion et première synchro réelle

Deliverable : **premier jalon utilisable**. L'app se lance, on colle ses credentials, on se connecte à Strava dans le navigateur, on lance une synchro et on voit le nombre d'activités importées.

**Files:**
- Create: `StravaLocal/Features/Shared/Formatters.swift`
- Create: `StravaLocal/App/AppEnvironment.swift`
- Create: `StravaLocal/Features/Settings/SettingsScene.swift`
- Modify: `StravaLocal/App/StravaLocalApp.swift`
- Create: `StravaLocal/App/RootView.swift`
- Create: `Tests/FormattersTests.swift`

**Interfaces:**
- Consumes: `KeychainStore`, `OAuthFlow`, `StravaClient`, `SyncEngine`, `SyncProgress`.
- Produces:
  - `enum Format { static func distance(_ metres: Double) -> String; static func duration(_ seconds: Int) -> String; static func elevation(_ metres: Double) -> String; static func speed(_ metresPerSecond: Double, sport: SportType) -> String; static func heartrate(_ bpm: Double?) -> String; static func power(_ watts: Double?) -> String; static func cadence(_ rpm: Double?) -> String }`
  - `@MainActor @Observable final class AppEnvironment { let store: SecretStore; let client: StravaClient; let oauth: OAuthFlow; let engine: SyncEngine; let progress: SyncProgress; var isAuthenticated: Bool; var hasCredentials: Bool; var athleteName: String?; var errorMessage: String?; init(container: ModelContainer); func saveCredentials(clientID: String, clientSecret: String); func connect() async; func disconnect(); func syncNow(); func syncSummariesOnly(); func cancelSync(); func loadDetail(stravaID: Int64); func refreshAuthenticationState() }`
  - `struct SettingsScene: View`

`AppEnvironment` est le seul objet qui assemble les dépendances ; il est injecté par `.environment()` et les vues n'instancient jamais rien elles-mêmes.

- [ ] **Step 1: Écrire les tests de formatage**

`Tests/FormattersTests.swift` :

```swift
import Testing
import Foundation
@testable import StravaLocal

@Suite("Format")
struct FormattersTests {
    @Test("les distances sous 1 km sont en mètres, au-dessus en kilomètres")
    func formatsDistance() {
        #expect(Format.distance(0) == "0 m")
        #expect(Format.distance(850) == "850 m")
        #expect(Format.distance(45_231.4).contains("45,2"))
        #expect(Format.distance(45_231.4).hasSuffix("km"))
    }

    @Test("les durées passent en h/min/s selon leur longueur")
    func formatsDuration() {
        #expect(Format.duration(0) == "0 s")
        #expect(Format.duration(45) == "45 s")
        #expect(Format.duration(90) == "1 min 30 s")
        #expect(Format.duration(3600) == "1 h 00")
        #expect(Format.duration(5412) == "1 h 30")
    }

    @Test("le dénivelé est arrondi au mètre")
    func formatsElevation() {
        #expect(Format.elevation(612.4) == "612 m")
    }

    @Test("la vitesse devient une allure pour les sports de course")
    func formatsSpeedBySport() {
        // 2,78 m/s ≈ 10 km/h → 6:00/km
        #expect(Format.speed(2.7778, sport: .run).contains("/km"))
        #expect(Format.speed(2.7778, sport: .ride).contains("km/h"))
    }

    @Test("une vitesse nulle ne produit pas d'allure absurde")
    func handlesZeroSpeed() {
        #expect(Format.speed(0, sport: .run) == "—")
        #expect(Format.speed(0, sport: .ride) == "—")
    }

    @Test("les mesures absentes affichent un tiret")
    func formatsMissingValues() {
        #expect(Format.heartrate(nil) == "—")
        #expect(Format.power(nil) == "—")
        #expect(Format.heartrate(138.4) == "138 bpm")
        #expect(Format.power(156.3) == "156 W")
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'Format' in scope ».

- [ ] **Step 3: Écrire `Formatters`**

```swift
import Foundation

/// Display formatting, centralised so the same distance never appears two ways.
enum Format {
    private static let oneDecimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func distance(_ metres: Double) -> String {
        guard metres >= 1000 else { return "\(Int(metres.rounded())) m" }
        let kilometres = oneDecimal.string(from: (metres / 1000) as NSNumber) ?? "0,0"
        return "\(kilometres) km"
    }

    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min \(seconds % 60) s" }
        return String(format: "%d h %02d", seconds / 3600, (seconds % 3600) / 60)
    }

    static func elevation(_ metres: Double) -> String {
        "\(Int(metres.rounded())) m"
    }

    /// Runners think in pace, cyclists in speed. Showing the wrong one makes
    /// every number in the row useless to read at a glance.
    static func speed(_ metresPerSecond: Double, sport: SportType) -> String {
        guard metresPerSecond > 0 else { return "—" }
        switch sport {
        case .run, .trailRun, .walk, .hike, .swim:
            let secondsPerKilometre = Int((1000 / metresPerSecond).rounded())
            return String(
                format: "%d:%02d/km", secondsPerKilometre / 60, secondsPerKilometre % 60
            )
        default:
            let kilometresPerHour = metresPerSecond * 3.6
            let value = oneDecimal.string(from: kilometresPerHour as NSNumber) ?? "0,0"
            return "\(value) km/h"
        }
    }

    static func heartrate(_ bpm: Double?) -> String {
        bpm.map { "\(Int($0.rounded())) bpm" } ?? "—"
    }

    static func power(_ watts: Double?) -> String {
        watts.map { "\(Int($0.rounded())) W" } ?? "—"
    }

    static func cadence(_ rpm: Double?) -> String {
        rpm.map { "\(Int($0.rounded())) rpm" } ?? "—"
    }
}
```

- [ ] **Step 4: Écrire `AppEnvironment`**

```swift
import Foundation
import SwiftData
import Observation

/// Wires the app together in one place. Views receive it through the
/// environment and never build a client, engine or store themselves.
@MainActor
@Observable
final class AppEnvironment {
    let store: SecretStore
    let client: StravaClient
    let oauth: OAuthFlow
    let engine: SyncEngine
    let progress: SyncProgress

    var isAuthenticated: Bool
    var hasCredentials: Bool
    var athleteName: String?
    var errorMessage: String?

    private var runningTask: Task<Void, Never>?

    init(container: ModelContainer) {
        let store = KeychainStore()
        let progress = SyncProgress()
        let client = StravaClient(store: store)

        self.store = store
        self.client = client
        self.progress = progress
        self.oauth = OAuthFlow(store: store)
        self.engine = SyncEngine(
            source: client, container: container, progress: progress
        )
        self.isAuthenticated = store.tokens() != nil
        self.hasCredentials = store.credentials() != nil
    }

    func refreshAuthenticationState() {
        isAuthenticated = store.tokens() != nil
        hasCredentials = store.credentials() != nil
    }

    func saveCredentials(clientID: String, clientSecret: String) {
        do {
            try store.save(
                StravaCredentials(
                    clientID: clientID.trimmingCharacters(in: .whitespaces),
                    clientSecret: clientSecret.trimmingCharacters(in: .whitespaces)
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = "Impossible d'enregistrer les identifiants : \(error.localizedDescription)"
        }
        refreshAuthenticationState()
    }

    func connect() async {
        do {
            let athlete = try await oauth.authorize()
            athleteName = [athlete?.firstname, athlete?.lastname]
                .compactMap { $0 }.joined(separator: " ")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshAuthenticationState()
    }

    func disconnect() {
        try? store.clearTokens()
        athleteName = nil
        refreshAuthenticationState()
    }

    /// Full sync. Guarded against overlapping runs — two concurrent syncs would
    /// double-spend the API quota for nothing.
    func syncNow() {
        guard runningTask == nil, isAuthenticated else { return }
        runningTask = Task { [engine] in
            do {
                try await engine.syncAll()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            runningTask = nil
        }
    }

    func syncSummariesOnly() {
        guard runningTask == nil, isAuthenticated else { return }
        runningTask = Task { [engine] in
            do {
                try await engine.syncAthlete()
                try await engine.syncSummaries()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            runningTask = nil
        }
    }

    func cancelSync() {
        runningTask?.cancel()
        runningTask = nil
    }

    func loadDetail(stravaID: Int64) {
        Task { [engine] in
            try? await engine.fetchDetailIfNeeded(stravaID: stravaID)
        }
    }
}
```

- [ ] **Step 5: Écrire `SettingsScene`**

```swift
import SwiftUI
import SwiftData

struct SettingsScene: View {
    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem { Label("Compte", systemImage: "person.crop.circle") }
            SyncSettingsView()
                .tabItem { Label("Synchronisation", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 520, height: 380)
    }
}

private struct AccountSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isConnecting = false

    var body: some View {
        Form {
            Section {
                TextField("Client ID", text: $clientID)
                SecureField("Client Secret", text: $clientSecret)
                Button("Enregistrer les identifiants") {
                    app.saveCredentials(clientID: clientID, clientSecret: clientSecret)
                }
                .disabled(clientID.isEmpty || clientSecret.isEmpty)
            } header: {
                Text("Application Strava")
            } footer: {
                Text("""
                    Créez une application sur strava.com/settings/api en indiquant \
                    « localhost » comme Authorization Callback Domain, puis recopiez \
                    ici son Client ID et son Client Secret. Ils sont conservés dans \
                    le trousseau macOS.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Connexion") {
                if app.isAuthenticated {
                    LabeledContent("État", value: app.athleteName ?? "Connecté")
                    Button("Se déconnecter", role: .destructive) { app.disconnect() }
                } else {
                    Button {
                        isConnecting = true
                        Task {
                            await app.connect()
                            isConnecting = false
                        }
                    } label: {
                        if isConnecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Se connecter à Strava…")
                        }
                    }
                    .disabled(!app.hasCredentials || isConnecting)
                }
            }

            if let message = app.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red).font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            clientID = app.store.credentials()?.clientID ?? ""
            clientSecret = app.store.credentials()?.clientSecret ?? ""
        }
    }
}

private struct SyncSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @Query private var activities: [Activity]

    var body: some View {
        Form {
            Section("État") {
                LabeledContent("Activités locales", value: "\(activities.count)")
                LabeledContent("Synchronisation", value: app.progress.statusText)
                if let quota = app.progress.quota {
                    LabeledContent(
                        "Quota Strava",
                        value: "\(quota.shortTermUsage)/\(quota.shortTermLimit) · "
                            + "\(quota.dailyUsage)/\(quota.dailyLimit) aujourd'hui"
                    )
                }
                if let fraction = app.progress.fractionCompleted {
                    ProgressView(value: fraction)
                }
            }

            Section {
                Button("Synchroniser maintenant") { app.syncNow() }
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Button("Importer seulement les résumés") { app.syncSummariesOnly() }
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                if app.progress.isRunning {
                    Button("Interrompre", role: .cancel) { app.cancelSync() }
                }
            } footer: {
                Text("""
                    Les traces détaillées coûtent une requête par activité. Strava \
                    autorise 200 requêtes par quart d'heure et 2 000 par jour : un \
                    gros historique s'importe donc en plusieurs fois. L'import \
                    reprend automatiquement là où il s'est arrêté.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 6: Écrire `RootView` provisoire et câbler les scènes**

`StravaLocal/App/RootView.swift` :

```swift
import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @Query private var activities: [Activity]

    var body: some View {
        VStack(spacing: 12) {
            Text("\(activities.count) activités en local")
                .font(.title2)
            Text(app.progress.statusText)
                .foregroundStyle(.secondary)
            if !app.isAuthenticated {
                Text("Connectez-vous depuis Réglages (⌘,)")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
```

`StravaLocal/App/StravaLocalApp.swift` :

```swift
import SwiftUI
import SwiftData

@main
struct StravaLocalApp: App {
    private let container: ModelContainer
    @State private var app: AppEnvironment

    init() {
        let container: ModelContainer
        do {
            container = try AppModelContainer.make()
        } catch {
            fatalError("Impossible d'ouvrir la base locale : \(error)")
        }
        self.container = container
        _app = State(initialValue: AppEnvironment(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Synchroniser") { app.syncNow() }
                    .keyboardShortcut("r")
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
            }
        }

        Settings {
            SettingsScene()
                .environment(app)
                .modelContainer(container)
        }
    }
}
```

- [ ] **Step 7: Lancer les tests**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Vérifier le flux complet à la main**

Run: `xcodebuild -project StravaLocal.xcodeproj -scheme StravaLocal -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet build && open build/Build/Products/Debug/StravaLocal.app`

Puis, dans l'app : ⌘, → coller Client ID et Client Secret → Enregistrer → Se connecter à Strava → autoriser dans le navigateur → revenir à l'app → onglet Synchronisation → « Importer seulement les résumés ».
Expected: le compteur d'activités de la fenêtre principale devient non nul, et le statut repasse à « Dernière synchro … ».

- [ ] **Step 9: Commit**

```bash
git add StravaLocal Tests/FormattersTests.swift
git commit -m "feat(app): réglages, connexion Strava et première synchro"
```

---

### Task 14: Liste d'activités, tri et filtres

Deliverable : une `Table` façon Finder avec sidebar par sport, recherche texte et filtres composables.

**Files:**
- Create: `StravaLocal/Features/ActivityList/ActivityFilter.swift`
- Create: `StravaLocal/Features/ActivityList/FilterBar.swift`
- Create: `StravaLocal/Features/ActivityList/ActivityListView.swift`
- Create: `StravaLocal/App/SidebarView.swift`
- Modify: `StravaLocal/App/RootView.swift`
- Create: `Tests/ActivityFilterTests.swift`

**Interfaces:**
- Consumes: `Activity`, `SportType`, `Format`, `BoundingBox`.
- Produces:
  - `enum DatePeriod: String, CaseIterable, Sendable, Identifiable { case all, last30Days, last90Days, thisYear, lastYear; var displayName: String; func startDate(now: Date) -> Date?; func endDate(now: Date) -> Date? }`
  - `struct ActivityFilter: Sendable, Equatable { var searchText: String; var sports: Set<SportType>; var period: DatePeriod; var minDistanceKm: Double?; var maxDistanceKm: Double?; var minDurationMinutes: Double?; var minElevation: Double?; var region: BoundingBox?; static let none: ActivityFilter; var isActive: Bool; func predicate(now: Date) -> Predicate<Activity>; func matchesPrecisely(_ activity: Activity) -> Bool }`
  - `struct ActivityListView: View { init(filter: ActivityFilter, selection: Binding<Activity.ID?>) }`
  - `struct FilterBar: View { init(filter: Binding<ActivityFilter>) }`
  - `enum SidebarItem: Hashable { case all, sport(SportType), globalMap }`
  - `struct SidebarView: View`

`predicate(now:)` couvre tout ce que la base peut faire, région comprise via la bbox. `matchesPrecisely` complète en mémoire pour le seul test que SQL ne peut pas faire : la trace passe-t-elle vraiment dans la région.

- [ ] **Step 1: Écrire les tests d'abord**

`Tests/ActivityFilterTests.swift` :

```swift
import Testing
import SwiftData
import Foundation
@testable import StravaLocal

@Suite("ActivityFilter")
struct ActivityFilterTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeContext(_ configure: (ModelContext) throws -> Void) throws
        -> ModelContext
    {
        let context = ModelContext(try AppModelContainer.inMemory())
        try configure(context)
        try context.save()
        return context
    }

    private func insert(
        _ context: ModelContext, id: Int64, name: String = "Sortie",
        sport: SportType = .ride, daysAgo: Int = 1, distance: Double = 30_000,
        duration: Int = 3600, elevation: Double = 200,
        track: [Coordinate] = [Coordinate(latitude: 45.75, longitude: 4.83)]
    ) {
        let activity = Activity(stravaID: id, name: name, sportType: sport)
        activity.startDate = now.addingTimeInterval(Double(-daysAgo * 86_400))
        activity.startLocalDate = activity.startDate
        activity.distance = distance
        activity.movingTime = duration
        activity.elapsedTime = duration
        activity.totalElevationGain = elevation
        activity.apply(simplifiedCoordinates: track)
        if let box = BoundingBox(coordinates: track) { activity.apply(boundingBox: box) }
        context.insert(activity)
    }

    private func fetch(_ context: ModelContext, _ filter: ActivityFilter) throws
        -> [Activity]
    {
        try context
            .fetch(FetchDescriptor<Activity>(predicate: filter.predicate(now: now)))
            .filter(filter.matchesPrecisely)
    }

    @Test("le filtre vide laisse tout passer")
    func emptyFilterMatchesAll() throws {
        let context = try makeContext {
            insert($0, id: 1)
            insert($0, id: 2, sport: .run)
        }
        #expect(try fetch(context, .none).count == 2)
    }

    @Test("filtre par sport")
    func filtersBySport() throws {
        let context = try makeContext {
            insert($0, id: 1, sport: .ride)
            insert($0, id: 2, sport: .run)
            insert($0, id: 3, sport: .trailRun)
        }
        var filter = ActivityFilter.none
        filter.sports = [.run, .trailRun]
        #expect(try fetch(context, filter).count == 2)
    }

    @Test("filtre par texte, insensible à la casse")
    func filtersBySearchText() throws {
        let context = try makeContext {
            insert($0, id: 1, name: "Col de la Croix")
            insert($0, id: 2, name: "Footing matinal")
        }
        var filter = ActivityFilter.none
        filter.searchText = "croix"
        #expect(try fetch(context, filter).map(\.stravaID) == [1])
    }

    @Test("filtre par période")
    func filtersByPeriod() throws {
        let context = try makeContext {
            insert($0, id: 1, daysAgo: 5)
            insert($0, id: 2, daysAgo: 200)
        }
        var filter = ActivityFilter.none
        filter.period = .last30Days
        #expect(try fetch(context, filter).map(\.stravaID) == [1])
    }

    @Test("filtre par plage de distance")
    func filtersByDistance() throws {
        let context = try makeContext {
            insert($0, id: 1, distance: 5_000)
            insert($0, id: 2, distance: 50_000)
            insert($0, id: 3, distance: 120_000)
        }
        var filter = ActivityFilter.none
        filter.minDistanceKm = 20
        filter.maxDistanceKm = 100
        #expect(try fetch(context, filter).map(\.stravaID) == [2])
    }

    @Test("filtre par durée minimale et dénivelé minimal")
    func filtersByDurationAndElevation() throws {
        let context = try makeContext {
            insert($0, id: 1, duration: 1200, elevation: 50)
            insert($0, id: 2, duration: 7200, elevation: 1500)
        }
        var filter = ActivityFilter.none
        filter.minDurationMinutes = 60
        filter.minElevation = 1000
        #expect(try fetch(context, filter).map(\.stravaID) == [2])
    }

    @Test("les filtres se combinent")
    func combinesFilters() throws {
        let context = try makeContext {
            insert($0, id: 1, name: "Sortie longue", sport: .ride, distance: 120_000)
            insert($0, id: 2, name: "Sortie longue", sport: .run, distance: 30_000)
            insert($0, id: 3, name: "Sortie courte", sport: .ride, distance: 120_000)
        }
        var filter = ActivityFilter.none
        filter.searchText = "longue"
        filter.sports = [.ride]
        filter.minDistanceKm = 100
        #expect(try fetch(context, filter).map(\.stravaID) == [1])
    }

    @Test("le filtre par région écarte les traces hors zone")
    func filtersByRegion() throws {
        let context = try makeContext {
            insert(
                $0, id: 1,
                track: [
                    Coordinate(latitude: 45.75, longitude: 4.83),
                    Coordinate(latitude: 45.78, longitude: 4.88),
                ]
            )
            insert(
                $0, id: 2,
                track: [Coordinate(latitude: 48.85, longitude: 2.35)]
            )
        }
        var filter = ActivityFilter.none
        filter.region = BoundingBox(
            minLat: 45.74, maxLat: 45.76, minLon: 4.82, maxLon: 4.84
        )
        #expect(try fetch(context, filter).map(\.stravaID) == [1])
    }

    @Test("une bbox qui chevauche mais dont aucun point n'entre est écartée")
    func regionRejectsBoxOnlyOverlap() throws {
        // Trace en L : sa bbox couvre le coin visé, mais aucun point n'y passe.
        let context = try makeContext {
            insert(
                $0, id: 1,
                track: [
                    Coordinate(latitude: 45.70, longitude: 4.80),
                    Coordinate(latitude: 45.70, longitude: 4.90),
                    Coordinate(latitude: 45.80, longitude: 4.90),
                ]
            )
        }
        var filter = ActivityFilter.none
        filter.region = BoundingBox(
            minLat: 45.79, maxLat: 45.81, minLon: 4.79, maxLon: 4.81
        )
        #expect(try fetch(context, filter).isEmpty)
    }

    @Test("une activité sans trace n'apparaît jamais dans une recherche par région")
    func regionExcludesTracklessActivities() throws {
        let context = try makeContext { insert($0, id: 1, track: []) }
        var filter = ActivityFilter.none
        filter.region = BoundingBox.world
        #expect(try fetch(context, filter).isEmpty)
    }

    @Test("isActive distingue un filtre vide d'un filtre en cours")
    func reportsActivity() {
        #expect(!ActivityFilter.none.isActive)
        var filter = ActivityFilter.none
        filter.sports = [.run]
        #expect(filter.isActive)
    }

    @Test("les périodes calculent des bornes cohérentes")
    func computesPeriodBounds() {
        #expect(DatePeriod.all.startDate(now: now) == nil)
        #expect(DatePeriod.last30Days.startDate(now: now) != nil)
        #expect(DatePeriod.last30Days.startDate(now: now)! < now)
        #expect(DatePeriod.lastYear.endDate(now: now) != nil)
        #expect(DatePeriod.thisYear.endDate(now: now) == nil)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'ActivityFilter' in scope ».

- [ ] **Step 3: Écrire `ActivityFilter`**

```swift
import Foundation
import SwiftData

enum DatePeriod: String, CaseIterable, Sendable, Identifiable {
    case all, last30Days, last90Days, thisYear, lastYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "Toutes les dates"
        case .last30Days: "30 derniers jours"
        case .last90Days: "90 derniers jours"
        case .thisYear: "Cette année"
        case .lastYear: "L'an dernier"
        }
    }

    func startDate(now: Date) -> Date? {
        let calendar = Calendar(identifier: .gregorian)
        switch self {
        case .all: return nil
        case .last30Days: return calendar.date(byAdding: .day, value: -30, to: now)
        case .last90Days: return calendar.date(byAdding: .day, value: -90, to: now)
        case .thisYear:
            return calendar.date(from: calendar.dateComponents([.year], from: now))
        case .lastYear:
            guard let thisYear = calendar.date(
                from: calendar.dateComponents([.year], from: now)
            ) else { return nil }
            return calendar.date(byAdding: .year, value: -1, to: thisYear)
        }
    }

    func endDate(now: Date) -> Date? {
        guard case .lastYear = self else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: calendar.dateComponents([.year], from: now))
    }
}

/// The filter state, and its translation into a database predicate.
///
/// Everything expressible in SQL goes into `predicate` — including the
/// geographic pre-filter, thanks to the indexed bounding-box columns. Only the
/// precise "does the track actually enter this region" test happens in memory,
/// on the already-narrowed result.
struct ActivityFilter: Sendable, Equatable {
    var searchText: String = ""
    var sports: Set<SportType> = []
    var period: DatePeriod = .all
    var minDistanceKm: Double?
    var maxDistanceKm: Double?
    var minDurationMinutes: Double?
    var minElevation: Double?
    var region: BoundingBox?

    static let none = ActivityFilter()

    var isActive: Bool { self != .none }

    func predicate(now: Date = Date()) -> Predicate<Activity> {
        // Sentinel bounds instead of optionals: SwiftData predicates can't
        // unwrap captured optionals, but they compare captured scalars fine.
        let text = searchText.trimmingCharacters(in: .whitespaces)
        let sportValues = sports.map(\.rawValue)
        let filtersSport = !sportValues.isEmpty
        let start = period.startDate(now: now) ?? .distantPast
        let end = period.endDate(now: now) ?? .distantFuture
        let minDistance = (minDistanceKm ?? 0) * 1000
        let maxDistance = (maxDistanceKm ?? .greatestFiniteMagnitude) * 1000
        let minDuration = Int((minDurationMinutes ?? 0) * 60)
        let minGain = minElevation ?? 0
        let box = region ?? .world
        let filtersRegion = region != nil

        return #Predicate<Activity> { activity in
            (text.isEmpty || activity.name.localizedStandardContains(text))
                && (!filtersSport || sportValues.contains(activity.sportTypeRaw))
                && activity.startDate >= start
                && activity.startDate < end
                && activity.distance >= minDistance
                && activity.distance <= maxDistance
                && activity.movingTime >= minDuration
                && activity.totalElevationGain >= minGain
                && (!filtersRegion
                    || (activity.hasTrack
                        && activity.minLat <= box.maxLat
                        && activity.maxLat >= box.minLat
                        && activity.minLon <= box.maxLon
                        && activity.maxLon >= box.minLon))
        }
    }

    /// Second pass: bounding boxes can overlap a region a track never enters.
    func matchesPrecisely(_ activity: Activity) -> Bool {
        guard let region else { return true }
        guard activity.hasTrack else { return false }
        return region.containsAnyPoint(of: activity.simplifiedCoordinates)
    }
}
```

- [ ] **Step 4: Écrire `FilterBar`**

```swift
import SwiftUI

struct FilterBar: View {
    @Binding var filter: ActivityFilter

    var body: some View {
        HStack(spacing: 12) {
            Picker("Période", selection: $filter.period) {
                ForEach(DatePeriod.allCases) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .fixedSize()

            OptionalNumberField(
                title: "Distance min.", unit: "km", value: $filter.minDistanceKm
            )
            OptionalNumberField(
                title: "Distance max.", unit: "km", value: $filter.maxDistanceKm
            )
            OptionalNumberField(
                title: "Durée min.", unit: "min", value: $filter.minDurationMinutes
            )
            OptionalNumberField(
                title: "D+ min.", unit: "m", value: $filter.minElevation
            )

            Spacer()

            if filter.region != nil {
                Button {
                    filter.region = nil
                } label: {
                    Label("Zone de la carte", systemImage: "xmark.circle.fill")
                }
                .help("Retirer le filtre géographique")
            }

            if filter.isActive {
                Button("Réinitialiser") { filter = .none }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// A numeric field that stays empty when the filter isn't set, rather than
/// showing a misleading 0.
private struct OptionalNumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, text: $text)
                .frame(width: 72)
                .onChange(of: text) { _, new in
                    value = new.isEmpty
                        ? nil
                        : Double(new.replacingOccurrences(of: ",", with: "."))
                }
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
        .onChange(of: value) { _, new in
            if new == nil, !text.isEmpty { text = "" }
        }
    }
}
```

- [ ] **Step 5: Écrire `ActivityListView`**

```swift
import SwiftUI
import SwiftData

struct ActivityListView: View {
    let filter: ActivityFilter
    @Binding var selection: Activity.ID?

    /// Built in `init` from the incoming filter. The parent applies
    /// `.id(filter)` so a filter change re-instantiates the view, which is what
    /// rebuilds this query — `@Query` can't be mutated in place.
    @Query private var query: [Activity]

    @State private var sortOrder = [
        KeyPathComparator(\Activity.startDate, order: .reverse)
    ]

    init(filter: ActivityFilter, selection: Binding<Activity.ID?>) {
        self.filter = filter
        self._selection = selection
        _query = Query(
            filter: filter.predicate(),
            sort: [SortDescriptor(\Activity.startDate, order: .reverse)]
        )
    }

    private var rows: [Activity] {
        query.filter(filter.matchesPrecisely).sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.startLocalDate) { activity in
                Text(activity.startLocalDate.formatted(date: .abbreviated, time: .shortened))
            }
            .width(min: 140, ideal: 160)

            TableColumn("Nom", value: \.name) { activity in
                Label(activity.name, systemImage: activity.sportType.symbolName)
            }
            .width(min: 180, ideal: 280)

            TableColumn("Sport", value: \.sportTypeRaw) { activity in
                Text(activity.sportType.displayName)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Distance", value: \.distance) { activity in
                Text(Format.distance(activity.distance))
            }
            .width(min: 80, ideal: 90)

            TableColumn("Durée", value: \.movingTime) { activity in
                Text(Format.duration(activity.movingTime))
            }
            .width(min: 80, ideal: 90)

            TableColumn("D+", value: \.totalElevationGain) { activity in
                Text(Format.elevation(activity.totalElevationGain))
            }
            .width(min: 70, ideal: 80)

            TableColumn("Vitesse", value: \.averageSpeed) { activity in
                Text(Format.speed(activity.averageSpeed, sport: activity.sportType))
            }
            .width(min: 90, ideal: 100)
        }
        .navigationTitle(
            rows.count == 1 ? "1 activité" : "\(rows.count) activités"
        )
    }
}
```

- [ ] **Step 6: Écrire `SidebarView` et le vrai `RootView`**

`StravaLocal/App/SidebarView.swift` :

```swift
import SwiftUI
import SwiftData

enum SidebarItem: Hashable {
    case all
    case sport(SportType)
    case globalMap
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Query private var activities: [Activity]

    private var sportCounts: [(sport: SportType, count: Int)] {
        Dictionary(grouping: activities, by: \.sportType)
            .map { (sport: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Toutes les activités", systemImage: "list.bullet")
                    .badge(activities.count)
                    .tag(SidebarItem.all)
                Label("Carte globale", systemImage: "map")
                    .tag(SidebarItem.globalMap)
            }

            Section("Sports") {
                ForEach(sportCounts, id: \.sport) { entry in
                    Label(entry.sport.displayName, systemImage: entry.sport.symbolName)
                        .badge(entry.count)
                        .tag(SidebarItem.sport(entry.sport))
                }
            }
        }
        .listStyle(.sidebar)
    }
}
```

`StravaLocal/App/RootView.swift` (remplacement complet) :

```swift
import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var sidebarSelection: SidebarItem? = .all
    @State private var filter = ActivityFilter.none
    @State private var selectedActivity: Activity.ID?

    /// The sidebar picks a sport; the filter bar refines within it.
    private var effectiveFilter: ActivityFilter {
        var combined = filter
        if case let .sport(sport) = sidebarSelection {
            combined.sports = [sport]
        }
        return combined
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
                .frame(minWidth: 200)
        } content: {
            VStack(spacing: 0) {
                FilterBar(filter: $filter)
                Divider()
                ActivityListView(filter: effectiveFilter, selection: $selectedActivity)
                    .id(effectiveFilter)
            }
            .frame(minWidth: 520)
            .searchable(text: $filter.searchText, prompt: "Rechercher une activité")
        } detail: {
            Text("Sélectionnez une activité")
                .foregroundStyle(.secondary)
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                if app.progress.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(app.progress.statusText).font(.caption)
                    }
                }
            }
            ToolbarItem {
                Button {
                    app.syncNow()
                } label: {
                    Label("Synchroniser", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!app.isAuthenticated || app.progress.isRunning)
            }
        }
    }
}
```

- [ ] **Step 7: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Vérifier à la main**

Run: `xcodebuild -project StravaLocal.xcodeproj -scheme StravaLocal -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet build && open build/Build/Products/Debug/StravaLocal.app`
Expected: la liste affiche les activités déjà synchronisées ; le tri par colonne fonctionne, la sidebar filtre par sport, la recherche et les champs de distance/durée réduisent la liste.

- [ ] **Step 9: Commit**

```bash
git add StravaLocal Tests/ActivityFilterTests.swift
git commit -m "feat(list): table d'activités triable avec filtres composables"
```

---

### Task 15: Détail d'activité

Deliverable : sélectionner une activité affiche sa trace sur une carte, ses statistiques, ses courbes altitude/FC/puissance et ses tours ; le détail Strava est récupéré à la première ouverture.

**Files:**
- Create: `StravaLocal/Features/ActivityDetail/ActivityMapView.swift`
- Create: `StravaLocal/Features/ActivityDetail/StreamCharts.swift`
- Create: `StravaLocal/Features/ActivityDetail/ActivityDetailView.swift`
- Modify: `StravaLocal/App/RootView.swift`
- Create: `Tests/StreamSeriesTests.swift`

**Interfaces:**
- Consumes: `Activity`, `ActivityStreams`, `TrackBlob`, `Simplify`, `Format`, `AppEnvironment`.
- Produces:
  - `struct StreamSeries: Sendable, Identifiable { let id: String; let label: String; let unit: String; let points: [StreamPoint] }`
  - `struct StreamPoint: Sendable, Identifiable { let id: Int; let distanceKm: Double; let value: Double }`
  - `enum StreamSeriesBuilder { static let maxChartPoints: Int (= 600); static func series(from streams: ActivityStreams?, totalDistance: Double) -> [StreamSeries] }`
  - `struct ActivityMapView: NSViewRepresentable { init(coordinates: [Coordinate]) }`
  - `struct StreamChartsView: View { init(series: [StreamSeries]) }`
  - `struct ActivityDetailView: View { init(activity: Activity) }`

Les courbes sont indexées sur la distance parcourue plutôt que sur l'index de point : c'est ce qui rend un graphe lisible quand l'activité comporte des arrêts.

- [ ] **Step 1: Écrire les tests d'abord**

`Tests/StreamSeriesTests.swift` :

```swift
import Testing
import Foundation
@testable import StravaLocal

@Suite("StreamSeriesBuilder")
struct StreamSeriesTests {
    private func makeStreams(
        altitude: [Float]? = nil, heartrate: [Float]? = nil,
        watts: [Float]? = nil, pointCount: Int = 0
    ) -> ActivityStreams {
        let streams = ActivityStreams()
        streams.pointCount = pointCount
        streams.altitude = altitude.map(TrackBlob.encode(scalars:))
        streams.heartrate = heartrate.map(TrackBlob.encode(scalars:))
        streams.watts = watts.map(TrackBlob.encode(scalars:))
        return streams
    }

    @Test("sans streams, aucune série")
    func noStreamsNoSeries() {
        #expect(StreamSeriesBuilder.series(from: nil, totalDistance: 1000).isEmpty)
    }

    @Test("l'altitude produit une série étalée sur la distance totale")
    func buildsAltitudeSeries() {
        let streams = makeStreams(altitude: [100, 150, 200], pointCount: 3)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 10_000)

        #expect(series.count == 1)
        #expect(series[0].id == "altitude")
        #expect(series[0].points.count == 3)
        #expect(series[0].points.first?.distanceKm == 0)
        #expect(series[0].points.last?.distanceKm == 10)
        #expect(series[0].points.last?.value == 200)
    }

    @Test("chaque stream disponible donne sa propre série")
    func buildsAllAvailableSeries() {
        let streams = makeStreams(
            altitude: [1, 2], heartrate: [100, 120], watts: [200, 250], pointCount: 2
        )
        let ids = StreamSeriesBuilder.series(from: streams, totalDistance: 1000).map(\.id)
        #expect(ids == ["altitude", "heartrate", "watts"])
    }

    @Test("les streams absents ne créent pas de série vide")
    func skipsMissingStreams() {
        let streams = makeStreams(heartrate: [100, 110], pointCount: 2)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 1000)
        #expect(series.map(\.id) == ["heartrate"])
    }

    @Test("les longues séries sont sous-échantillonnées")
    func downsamplesLongSeries() {
        let values = (0..<20_000).map { Float($0) }
        let streams = makeStreams(altitude: values, pointCount: values.count)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 100_000)

        #expect(series[0].points.count <= StreamSeriesBuilder.maxChartPoints)
        #expect(series[0].points.first?.value == 0)
        #expect(series[0].points.last?.value == 19_999)
    }

    @Test("une distance nulle ne divise pas par zéro")
    func handlesZeroDistance() {
        let streams = makeStreams(altitude: [10, 20], pointCount: 2)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 0)
        #expect(series[0].points.allSatisfy { $0.distanceKm == 0 })
    }

    @Test("un stream d'un seul point reste exploitable")
    func handlesSinglePoint() {
        let streams = makeStreams(altitude: [42], pointCount: 1)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 1000)
        #expect(series[0].points.count == 1)
        #expect(series[0].points[0].distanceKm == 0)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier qu'ils échouent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: échec de compilation, « cannot find 'StreamSeriesBuilder' in scope ».

- [ ] **Step 3: Écrire `StreamCharts`**

```swift
import SwiftUI
import Charts

struct StreamPoint: Sendable, Identifiable {
    let id: Int
    let distanceKm: Double
    let value: Double
}

struct StreamSeries: Sendable, Identifiable {
    let id: String
    let label: String
    let unit: String
    let points: [StreamPoint]
}

enum StreamSeriesBuilder {
    /// Beyond this, Swift Charts spends more time laying out than the extra
    /// detail is worth at screen resolution.
    static let maxChartPoints = 600

    static func series(
        from streams: ActivityStreams?, totalDistance: Double
    ) -> [StreamSeries] {
        guard let streams else { return [] }
        let definitions: [(String, String, String, Data?)] = [
            ("altitude", "Altitude", "m", streams.altitude),
            ("heartrate", "Fréquence cardiaque", "bpm", streams.heartrate),
            ("watts", "Puissance", "W", streams.watts),
            ("cadence", "Cadence", "rpm", streams.cadence),
        ]

        return definitions.compactMap { id, label, unit, blob in
            guard let blob else { return nil }
            let values = Simplify.downsample(
                TrackBlob.decodeScalars(blob), to: maxChartPoints
            )
            guard !values.isEmpty else { return nil }

            // Spread evenly over the activity's distance rather than plotting
            // against point index, so stops don't distort the shape.
            let span = max(values.count - 1, 1)
            let points = values.enumerated().map { index, value in
                StreamPoint(
                    id: index,
                    distanceKm: totalDistance <= 0
                        ? 0
                        : (totalDistance / 1000) * Double(index) / Double(span),
                    value: Double(value)
                )
            }
            return StreamSeries(id: id, label: label, unit: unit, points: points)
        }
    }
}

struct StreamChartsView: View {
    let series: [StreamSeries]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(series) { serie in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(serie.label) (\(serie.unit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(serie.points) { point in
                        AreaMark(x: .value("km", point.distanceKm),
                                 y: .value(serie.label, point.value))
                        .opacity(0.15)
                        LineMark(x: .value("km", point.distanceKm),
                                 y: .value(serie.label, point.value))
                    }
                    .chartXAxisLabel("km")
                    .frame(height: 120)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Écrire `ActivityMapView`**

```swift
import SwiftUI
import MapKit

/// Single-track map. Uses MKMapView rather than SwiftUI's `Map` because the
/// global map (Task 16) needs MKMapView anyway, and sharing the renderer keeps
/// the two maps looking identical.
struct ActivityMapView: NSViewRepresentable {
    let coordinates: [Coordinate]

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsZoomControls = true
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        guard coordinates.count > 1 else { return }

        let polyline = MKPolyline(
            coordinates: coordinates.map(\.clLocation), count: coordinates.count
        )
        mapView.addOverlay(polyline)
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
            animated: false
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .controlAccentColor
            renderer.lineWidth = 4
            return renderer
        }
    }
}
```

- [ ] **Step 5: Écrire `ActivityDetailView`**

```swift
import SwiftUI
import SwiftData

struct ActivityDetailView: View {
    let activity: Activity
    @Environment(AppEnvironment.self) private var app

    private var trackCoordinates: [Coordinate] {
        // Full-resolution track when the streams are in; the simplified one is
        // a perfectly good stand-in until then.
        let detailed = activity.streams?.coordinates ?? []
        return detailed.isEmpty ? activity.simplifiedCoordinates : detailed
    }

    private var series: [StreamSeries] {
        StreamSeriesBuilder.series(
            from: activity.streams, totalDistance: activity.distance
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if trackCoordinates.count > 1 {
                    ActivityMapView(coordinates: trackCoordinates)
                        .frame(height: 320)
                        .clipShape(.rect(cornerRadius: 8))
                } else {
                    ContentUnavailableView(
                        "Pas de trace", systemImage: "map",
                        description: Text(
                            activity.isManual
                                ? "Activité saisie manuellement."
                                : "La trace n'a pas encore été synchronisée."
                        )
                    )
                    .frame(height: 200)
                }

                statistics

                if !series.isEmpty {
                    StreamChartsView(series: series)
                }

                if !activity.laps.isEmpty {
                    laps
                }

                if let description = activity.activityDescription,
                   !description.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes").font(.headline)
                        Text(description)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(activity.name)
        .task(id: activity.stravaID) {
            app.loadDetail(stravaID: activity.stravaID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(activity.sportType.displayName, systemImage: activity.sportType.symbolName)
                .foregroundStyle(.secondary)
            Text(activity.name).font(.largeTitle.weight(.semibold))
            Text(activity.startLocalDate.formatted(date: .complete, time: .shortened))
                .foregroundStyle(.secondary)
        }
    }

    private var statistics: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
            spacing: 16
        ) {
            StatTile("Distance", Format.distance(activity.distance))
            StatTile("Temps en mouvement", Format.duration(activity.movingTime))
            StatTile("Temps total", Format.duration(activity.elapsedTime))
            StatTile("Dénivelé +", Format.elevation(activity.totalElevationGain))
            StatTile(
                "Vitesse moyenne",
                Format.speed(activity.averageSpeed, sport: activity.sportType)
            )
            StatTile(
                "Vitesse max",
                Format.speed(activity.maxSpeed, sport: activity.sportType)
            )
            StatTile("FC moyenne", Format.heartrate(activity.averageHeartrate))
            StatTile("FC max", Format.heartrate(activity.maxHeartrate))
            StatTile("Puissance moyenne", Format.power(activity.averageWatts))
            StatTile("Puissance normalisée", Format.power(activity.weightedAverageWatts))
            StatTile("Cadence", Format.cadence(activity.averageCadence))
            if let gear = activity.gear {
                StatTile("Matériel", gear.name)
            }
        }
    }

    private var laps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tours").font(.headline)
            Table(activity.laps.sorted { $0.lapIndex < $1.lapIndex }) {
                TableColumn("#") { Text("\($0.lapIndex)") }.width(30)
                TableColumn("Distance") { Text(Format.distance($0.distance)) }
                TableColumn("Temps") { Text(Format.duration($0.movingTime)) }
                TableColumn("D+") { Text(Format.elevation($0.totalElevationGain)) }
                TableColumn("Vitesse") {
                    Text(Format.speed($0.averageSpeed, sport: activity.sportType))
                }
                TableColumn("FC") { Text(Format.heartrate($0.averageHeartrate)) }
            }
            .frame(height: min(CGFloat(activity.laps.count) * 28 + 28, 240))
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit())
        }
    }
}
```

- [ ] **Step 6: Brancher le détail dans `RootView`**

Dans `StravaLocal/App/RootView.swift`, ajouter la requête permettant de résoudre la sélection, et remplacer le bloc `detail:` :

```swift
    @Query private var allActivities: [Activity]

    private var selected: Activity? {
        allActivities.first { $0.id == selectedActivity }
    }
```

```swift
        } detail: {
            if let selected {
                ActivityDetailView(activity: selected)
            } else {
                ContentUnavailableView(
                    "Aucune activité sélectionnée", systemImage: "figure.run",
                    description: Text("Choisissez une activité dans la liste.")
                )
            }
        }
```

- [ ] **Step 7: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 8: Vérifier à la main**

Run: `xcodebuild -project StravaLocal.xcodeproj -scheme StravaLocal -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet build && open build/Build/Products/Debug/StravaLocal.app`
Expected: cliquer une activité affiche sa trace cadrée sur la carte, les statistiques, et les courbes si les streams sont importés. À la première ouverture, la description et les tours apparaissent après un court instant (récupération du détail).

- [ ] **Step 9: Commit**

```bash
git add StravaLocal Tests/StreamSeriesTests.swift
git commit -m "feat(detail): carte de trace, statistiques, courbes et tours"
```

---

### Task 16: Carte globale

Deliverable : une carte affichant toutes les traces de la base, fluide sur plusieurs milliers d'activités.

**Files:**
- Create: `StravaLocal/Features/GlobalMap/GlobalMapView.swift`
- Create: `StravaLocal/Features/GlobalMap/SelectionOverlayView.swift`
- Modify: `StravaLocal/App/RootView.swift`

**Interfaces:**
- Consumes: `Activity`, `Coordinate`, `BoundingBox`.
- Produces:
  - `struct GlobalMapView: View { init(activities: [Activity], selection: Binding<Activity.ID?>, region: Binding<BoundingBox?>) }`
  - `struct TrackMapRepresentable: NSViewRepresentable` — usage interne à `GlobalMapView`.
  - `final class SelectionOverlayView: NSView { var isEnabled: Bool; var onSelection: ((NSRect) -> Void)? }` — la saisie du rectangle vit ici, la Task 17 s'occupe de son exploitation.

Un unique `MKMultiPolyline` porte toutes les traces : c'est la seule façon de rester fluide, MapKit s'effondrant sur des milliers d'overlays distincts.

- [ ] **Step 1: Écrire `GlobalMapView`**

```swift
import SwiftUI
import MapKit

struct GlobalMapView: View {
    let activities: [Activity]
    @Binding var selection: Activity.ID?
    @Binding var region: BoundingBox?

    @State private var isSelectingRegion = false

    private var tracks: [[Coordinate]] {
        activities.compactMap {
            let track = $0.simplifiedCoordinates
            return track.count > 1 ? track : nil
        }
    }

    var body: some View {
        TrackMapRepresentable(
            tracks: tracks,
            isSelectingRegion: isSelectingRegion,
            onRegionSelected: { box in
                region = box
                isSelectingRegion = false
            }
        )
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                Toggle(isOn: $isSelectingRegion) {
                    Label("Sélectionner une zone", systemImage: "dot.viewfinder")
                }
                .toggleStyle(.button)
                .help("Tracez un rectangle sur la carte pour ne garder que les activités qui le traversent")

                if region != nil {
                    Button {
                        region = nil
                    } label: {
                        Label("Effacer la zone", systemImage: "xmark.circle")
                    }
                }
            }
            .padding()
        }
        .overlay(alignment: .bottomLeading) {
            Text(
                tracks.count == 1
                    ? "1 trace affichée" : "\(tracks.count) traces affichées"
            )
            .font(.caption)
            .padding(6)
            .background(.regularMaterial, in: .rect(cornerRadius: 6))
            .padding()
        }
        .navigationTitle("Carte globale")
    }
}
```

- [ ] **Step 2: Écrire `TrackMapRepresentable`**

Dans le même fichier :

```swift
/// All tracks in a single `MKMultiPolyline`.
///
/// One overlay per activity brings MapKit to its knees at a few thousand
/// activities; one multi-polyline renders the same geometry in a single pass.
/// The thin translucent stroke also gives repeated routes a heatmap look for
/// free.
struct TrackMapRepresentable: NSViewRepresentable {
    let tracks: [[Coordinate]]
    let isSelectingRegion: Bool
    let onRegionSelected: (BoundingBox) -> Void

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = true
        mapView.showsZoomControls = true

        let overlay = SelectionOverlayView()
        overlay.onSelection = { rect in
            guard let box = context.coordinator.boundingBox(for: rect, in: mapView)
            else { return }
            onRegionSelected(box)
        }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: mapView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: mapView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: mapView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: mapView.trailingAnchor),
        ])
        context.coordinator.selectionOverlay = overlay
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.selectionOverlay?.isEnabled = isSelectingRegion
        // Panning must stop while drawing, otherwise the drag moves the map.
        mapView.isScrollEnabled = !isSelectingRegion

        guard context.coordinator.renderedTrackCount != tracks.count else { return }
        context.coordinator.renderedTrackCount = tracks.count

        mapView.removeOverlays(mapView.overlays)
        guard !tracks.isEmpty else { return }

        let polylines = tracks.map {
            MKPolyline(coordinates: $0.map(\.clLocation), count: $0.count)
        }
        let multi = MKMultiPolyline(polylines)
        mapView.addOverlay(multi)
        mapView.setVisibleMapRect(
            multi.boundingMapRect,
            edgePadding: NSEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
            animated: false
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var renderedTrackCount = -1
        weak var selectionOverlay: SelectionOverlayView?

        func mapView(
            _ mapView: MKMapView, rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            let renderer = MKMultiPolylineRenderer(overlay: overlay)
            renderer.strokeColor = NSColor.systemOrange.withAlphaComponent(0.45)
            renderer.lineWidth = 2
            return renderer
        }

        func boundingBox(for rect: NSRect, in mapView: MKMapView) -> BoundingBox? {
            guard rect.width > 4, rect.height > 4 else { return nil }
            let topLeft = mapView.convert(
                NSPoint(x: rect.minX, y: rect.maxY), toCoordinateFrom: mapView
            )
            let bottomRight = mapView.convert(
                NSPoint(x: rect.maxX, y: rect.minY), toCoordinateFrom: mapView
            )
            return BoundingBox(
                minLat: min(topLeft.latitude, bottomRight.latitude),
                maxLat: max(topLeft.latitude, bottomRight.latitude),
                minLon: min(topLeft.longitude, bottomRight.longitude),
                maxLon: max(topLeft.longitude, bottomRight.longitude)
            )
        }
    }
}
```

- [ ] **Step 3: Écrire `SelectionOverlayView`**

`StravaLocal/Features/GlobalMap/SelectionOverlayView.swift` :

```swift
import AppKit

/// Transparent layer above the map that captures a rubber-band drag.
///
/// Drawing the rectangle here rather than in MKMapView keeps map gestures and
/// selection gestures from fighting over the same drag: when disabled, the view
/// declines every hit test and the map behaves exactly as if it weren't there.
final class SelectionOverlayView: NSView {
    var isEnabled = false {
        didSet {
            if !isEnabled { currentRect = nil }
            needsDisplay = true
        }
    }
    var onSelection: ((NSRect) -> Void)?

    private var anchor: NSPoint?
    private var currentRect: NSRect? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isEnabled ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        anchor = convert(event.locationInWindow, from: nil)
        currentRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, let anchor else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(anchor.x, point.x), y: min(anchor.y, point.y),
            width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, let rect = currentRect else {
            anchor = nil
            return
        }
        anchor = nil
        currentRect = nil
        onSelection?(rect)
    }

    override func resetCursorRects() {
        guard isEnabled else { return }
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isEnabled else { return }

        // Faint wash so it's obvious the map is in selection mode.
        NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
        bounds.fill()

        guard let rect = currentRect else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.20).setFill()
        rect.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()
    }
}
```

- [ ] **Step 4: Brancher la carte globale dans `RootView`**

Remplacer le bloc `content:` de `RootView` par un aiguillage sur la sidebar :

```swift
        } content: {
            switch sidebarSelection {
            case .globalMap:
                GlobalMapView(
                    activities: allActivities.filter(effectiveFilter.matchesPrecisely),
                    selection: $selectedActivity,
                    region: $filter.region
                )
                .frame(minWidth: 520)
            default:
                VStack(spacing: 0) {
                    FilterBar(filter: $filter)
                    Divider()
                    ActivityListView(filter: effectiveFilter, selection: $selectedActivity)
                        .id(effectiveFilter)
                }
                .frame(minWidth: 520)
                .searchable(text: $filter.searchText, prompt: "Rechercher une activité")
            }
        }
```

- [ ] **Step 5: Vérifier la compilation et les tests**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 6: Vérifier à la main**

Run: `xcodebuild -project StravaLocal.xcodeproj -scheme StravaLocal -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet build && open build/Build/Products/Debug/StravaLocal.app`
Expected: sidebar → Carte globale → toutes les traces sont visibles d'un coup, le zoom et le déplacement restent fluides. Le bouton « Sélectionner une zone » change l'aspect de la carte mais son effet sur la liste arrive en Task 17.

- [ ] **Step 7: Commit**

```bash
git add StravaLocal/Features/GlobalMap StravaLocal/App/RootView.swift
git commit -m "feat(map): carte globale de toutes les traces en MKMultiPolyline"
```

---

### Task 17: Recherche géographique par la carte

Deliverable : dessiner un rectangle sur la carte globale filtre la liste sur les activités qui traversent réellement cette zone.

**Files:**
- Modify: `StravaLocal/App/RootView.swift`
- Modify: `Tests/ActivityFilterTests.swift`

**Interfaces:**
- Consumes: `BoundingBox`, `ActivityFilter.region` (Task 14), `SelectionOverlayView` et `GlobalMapView` (Task 16).
- Produces: aucun type nouveau — cette tâche relie des pièces existantes.

Tout est déjà en place : le filtrage géographique est écrit et testé en Task 14 (`predicate` pour la bbox indexée, `matchesPrecisely` pour le test précis), et la saisie du rectangle en Task 16. Il ne reste qu'à faire en sorte que le résultat d'une sélection soit visible.

- [ ] **Step 1: Basculer sur la liste dès qu'une zone est choisie**

Dans `RootView`, le rectangle doit renvoyer l'utilisateur vers la liste filtrée — sinon le résultat de sa recherche est invisible. Remplacer la construction de `GlobalMapView` par :

```swift
            case .globalMap:
                GlobalMapView(
                    activities: allActivities.filter(effectiveFilter.matchesPrecisely),
                    selection: $selectedActivity,
                    region: Binding(
                        get: { filter.region },
                        set: { newRegion in
                            filter.region = newRegion
                            if newRegion != nil { sidebarSelection = .all }
                        }
                    )
                )
                .frame(minWidth: 520)
```

- [ ] **Step 2: Ajouter un test de bout en bout du filtre géographique**

Ajouter cette méthode **à l'intérieur** du `struct ActivityFilterTests` existant — elle réutilise ses helpers privés `makeContext`, `insert` et `fetch` :

```swift
    @Test("le filtre géographique se combine avec les autres critères")
    func regionCombinesWithOtherFilters() throws {
        let lyonTrack = [
            Coordinate(latitude: 45.75, longitude: 4.83),
            Coordinate(latitude: 45.76, longitude: 4.84),
        ]
        let context = try makeContext {
            insert($0, id: 1, sport: .ride, distance: 80_000, track: lyonTrack)
            insert($0, id: 2, sport: .run, distance: 10_000, track: lyonTrack)
            insert(
                $0, id: 3, sport: .ride, distance: 80_000,
                track: [Coordinate(latitude: 48.85, longitude: 2.35)]
            )
        }
        var filter = ActivityFilter.none
        filter.region = BoundingBox(
            minLat: 45.74, maxLat: 45.77, minLon: 4.82, maxLon: 4.85
        )
        filter.sports = [.ride]
        filter.minDistanceKm = 50

        #expect(try fetch(context, filter).map(\.stravaID) == [1])
    }
```

- [ ] **Step 3: Lancer les tests pour vérifier qu'ils passent**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -quiet`
Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Vérifier à la main**

Run: `xcodebuild -project StravaLocal.xcodeproj -scheme StravaLocal -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet build && open build/Build/Products/Debug/StravaLocal.app`
Expected: sidebar → Carte globale → toutes les traces sont visibles ; activer « Sélectionner une zone », tracer un rectangle sur un quartier → l'app revient à la liste, réduite aux activités qui y passent, avec un bouton pour retirer le filtre de zone.

- [ ] **Step 5: Commit**

```bash
git add StravaLocal Tests/ActivityFilterTests.swift
git commit -m "feat(map): recherche d'activités par zone dessinée sur la carte"
```

---

### Task 18: Finitions macOS et vérification complète

Deliverable : l'app se comporte comme une app système (menus, raccourcis, état vide explicite), un README explique l'installation, et l'ensemble du parcours est vérifié de bout en bout.

**Files:**
- Create: `StravaLocal/Features/Shared/WelcomeView.swift`
- Modify: `StravaLocal/App/StravaLocalApp.swift`
- Modify: `StravaLocal/App/RootView.swift`
- Create: `README.md`

**Interfaces:**
- Consumes: tout.
- Produces: `struct WelcomeView: View`.

- [ ] **Step 1: Écrire `WelcomeView`**

Sans cet écran, une app fraîchement installée affiche une liste vide sans expliquer quoi faire.

```swift
import SwiftUI

struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentUnavailableView {
            Label("Aucune donnée locale", systemImage: "arrow.down.circle")
        } description: {
            Text(
                app.isAuthenticated
                    ? "Lancez une synchronisation pour récupérer vos activités Strava."
                    : "Connectez votre compte Strava pour commencer, puis lancez une synchronisation."
            )
        } actions: {
            if app.isAuthenticated {
                Button("Synchroniser maintenant") { app.syncNow() }
                    .disabled(app.progress.isRunning)
            } else {
                Button("Ouvrir les réglages…") { openSettings() }
            }
        }
    }
}
```

- [ ] **Step 2: Afficher l'écran d'accueil quand la base est vide**

Dans `RootView`, envelopper le `NavigationSplitView` :

```swift
    var body: some View {
        Group {
            if allActivities.isEmpty && !app.progress.isRunning {
                WelcomeView()
                    .frame(minWidth: 900, minHeight: 600)
            } else {
                splitView
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            // … contenu inchangé …
        }
    }
```

Renommer l'ancien corps en `splitView` et laisser son contenu tel quel.

- [ ] **Step 3: Compléter les commandes de menu**

Dans `StravaLocalApp`, remplacer le bloc `.commands` :

```swift
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Strava") {
                Button("Synchroniser") { app.syncNow() }
                    .keyboardShortcut("r")
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Button("Importer seulement les résumés") { app.syncSummariesOnly() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!app.isAuthenticated || app.progress.isRunning)
                Divider()
                Button("Interrompre la synchronisation") { app.cancelSync() }
                    .disabled(!app.progress.isRunning)
            }
        }
```

`CommandGroup(replacing: .newItem) {}` retire « Nouveau » et « Ouvrir » : l'app n'a pas de document, et laisser des entrées mortes dans le menu Fichier est précisément ce qui trahit une app non native.

- [ ] **Step 4: Écrire le README**

````markdown
# StravaLocal

Application macOS native qui conserve une copie locale de vos données Strava et
permet de les consulter hors ligne : liste filtrable, détail d'activité avec
trace et courbes, carte de toutes vos traces, et recherche d'activités par zone
géographique.

## Prérequis

- macOS 15 ou plus récent
- Xcode 26
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) : `brew install xcodegen`

## Compilation

```bash
xcodegen generate
open StravaLocal.xcodeproj
```

Le projet Xcode est généré à partir de `project.yml` et n'est pas versionné.

## Configuration Strava

L'application utilise votre propre application API Strava — aucune donnée ne
transite par un service tiers.

1. Ouvrez <https://www.strava.com/settings/api> et créez une application.
2. Renseignez `localhost` comme **Authorization Callback Domain**.
3. Lancez StravaLocal, ouvrez les réglages (⌘,) et collez le **Client ID** et le
   **Client Secret**.
4. Cliquez « Se connecter à Strava » : l'autorisation s'ouvre dans votre
   navigateur, puis l'application récupère ses jetons.

Identifiants et jetons sont conservés dans le trousseau macOS, jamais sur disque
en clair.

## Synchronisation

La synchronisation se déroule en deux temps :

1. **Résumés** — quelques requêtes suffisent pour tout l'historique. La liste et
   la carte globale sont utilisables immédiatement.
2. **Traces détaillées** — une requête par activité. Strava autorise 200
   requêtes par quart d'heure et 2 000 par jour : un gros historique s'importe
   donc en plusieurs sessions. L'import est reprenable, il repart toujours de là
   où il s'est arrêté.

Les synchronisations suivantes sont incrémentales.

## Emplacement des données

`~/Library/Application Support/StravaLocal/StravaLocal.store`
````

- [ ] **Step 5: Lancer la suite de tests complète**

Run: `xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' 2>&1 | tail -30`
Expected: `TEST SUCCEEDED`, et le nombre de tests exécutés est cohérent avec les suites écrites (Geo, TrackBlob, Simplify, BoundingBox, Model, StravaDTO, TokenStore, RateLimiter, StravaClient, ImportMapper, SyncEngine ×2, Format, ActivityFilter, StreamSeriesBuilder).

- [ ] **Step 6: Vérifier l'absence d'avertissements de concurrence**

Run: `xcodebuild -project StravaLocal.xcodeproj -scheme StravaLocal -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build build 2>&1 | grep -E "warning:" | head -20`
Expected: aucune sortie. S'il y a des avertissements de `Sendable` ou d'isolation d'acteur, les corriger — en mode langage Swift 6 ce sont des bugs de concurrence en sursis, pas du bruit.

- [ ] **Step 7: Parcours de vérification manuelle complet**

Run: `open build/Build/Products/Debug/StravaLocal.app`

Vérifier dans l'ordre :

1. Base vide → l'écran d'accueil propose d'ouvrir les réglages.
2. ⌘, → coller les identifiants → « Se connecter à Strava » → autorisation dans le navigateur → l'onglet Compte affiche le nom de l'athlète.
3. ⌘R → la toolbar affiche la progression, puis la liste se remplit.
4. Trier par distance décroissante → la plus longue sortie est en tête.
5. Sidebar → un sport → la liste ne contient plus que ce sport, le compteur du titre suit.
6. Recherche « col » (ou un mot présent dans vos titres) → la liste se réduite.
7. Distance min. 50 km → seules les longues sorties restent ; « Réinitialiser » les fait revenir.
8. Cliquer une activité → carte cadrée sur la trace, statistiques, courbes altitude/FC, tours.
9. Sidebar → Carte globale → toutes les traces sont visibles, le zoom et le déplacement sont fluides.
10. « Sélectionner une zone » → tracer un rectangle → retour à la liste filtrée sur cette zone ; ouvrir une des activités et vérifier sur sa carte qu'elle y passe bien.
11. Quitter pendant une synchro de traces, relancer, ⌘R → l'import reprend sans redemander les traces déjà récupérées (le compteur `x/y` repart d'un total réduit).
12. Couper le Wi-Fi → ⌘R affiche une erreur explicite ; la consultation des activités déjà en base continue de fonctionner.

- [ ] **Step 8: Commit**

```bash
git add StravaLocal README.md
git commit -m "feat(app): écran d'accueil, menus macOS et README"
```
