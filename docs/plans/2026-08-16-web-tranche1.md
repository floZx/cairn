# Tranche 1 — le socle du miroir Supabase

> **Pour les agents :** SOUS-SKILL REQUISE : utiliser `superpowers:subagent-driven-development`
> (recommandé) ou `superpowers:executing-plans` pour dérouler ce plan tâche par
> tâche. Les étapes sont en cases à cocher (`- [ ]`).

**But :** le Mac téléverse sa bibliothèque dans Supabase et l'y maintient à
jour. Aucune PWA, aucun pull, aucune fusion.

**Architecture :** un client PostgREST écrit à la main sur `URLSession`, sur le
patron de `StravaClient`. Chaque modèle SwiftData gagne un `uuid` stable. Une
*outbox*, alimentée par la notification `ModelContext.willSave`, enregistre ce
qui a changé ; un moteur la rejoue en upsert. Les blobs partent dans Supabase
Storage, où ils ne sont jamais qu'une copie.

**Pile :** Swift 6.0, SwiftData, Swift Testing, `URLSession`. **Aucune
dépendance SPM ajoutée.**

**Spécification :** `docs/specs/2026-08-16-cairn-web-design.md`

## Contraintes globales

Elles s'appliquent à **toutes** les tâches, sans être répétées dans chacune.

- **Le Mac ne dépend jamais de Supabase.** Aucun chemin de lancement, de
  lecture, d'écriture, de recherche, d'export ou de sauvegarde ne doit attendre
  le réseau. Le miroir est une tâche de fond dont l'échec n'a d'autre effet
  qu'un indicateur dans les réglages. La tâche 11 en fait un test.
- **Aucune dépendance SPM.** `project.yml` ne gagne pas de bloc `packages:`.
- **Migrations additives seulement.** Propriétés nouvelles avec valeur par
  défaut ou optionnelles. Jamais de type modifié, jamais de contrainte
  d'unicité ajoutée — voir l'avertissement en tête de `Cairn/Model/Activity.swift`.
- **Identifiants en anglais, texte affiché en français.** C'est la convention du
  dépôt.
- **Swift Testing**, jamais XCTest : 91 fichiers de tests, zéro `import XCTest`.
- **Concurrence stricte Swift 6.** Tout ce qui traverse un `await` est `Sendable`.
- **`xcodegen generate` après tout ajout de fichier source.**
- **Les initialiseurs de modèles cités dans les tests sont indicatifs.** Le plan
  écrit `WeightEntry(dateKey:weightKg:note:)`, `Activity(stravaID:name:sportType:)` et
  consorts ; lire la signature réelle dans `Cairn/Model/` et l'adapter. Cela vaut
  pour toutes les tâches, pas seulement celle où c'est rappelé.
- Build et tests :
  ```bash
  xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
  ```

## Structure des fichiers

**Nouveau dossier `Cairn/Mirror/`** — « Mirror » et non « Sync », qui appartient
déjà à Strava et désigne autre chose.

| Fichier | Responsabilité |
|---|---|
| `MirrorCredentials.swift` | URL du projet, clé anon, session ; rangées au trousseau |
| `MirrorClient.swift` | PostgREST et Storage sur `URLSession` |
| `MirrorRow.swift` | Le protocole : ce qu'un modèle devient en JSON |
| `MirrorRows+Activity.swift` | Encodage des modèles d'activité |
| `MirrorRows+Nutrition.swift` | Encodage des modèles d'alimentation |
| `MirrorOutbox.swift` | Le modèle SwiftData qui note ce qui a changé |
| `MirrorRecorder.swift` | Le branchement sur `ModelContext.willSave` |
| `MirrorEngine.swift` | Amorçage et push, reprenables |
| `MirrorProgress.swift` | État affichable, sur le patron de `SyncProgress` |
| `MirrorSettingsView.swift` | L'onglet de réglages |
| `supabase/schema.sql` | Tables, RLS, triggers |
| `supabase/README.md` | Comment l'appliquer |

Les modèles existants ne gagnent que des propriétés ; aucun n'est déplacé.

---

### Tâche 1 : Le schéma Postgres et sa politique

**Fichiers :**
- Créer : `supabase/schema.sql`
- Créer : `supabase/README.md`

**Interfaces :**
- Produit : les tables `activity`, `activity_streams`, `activity_photo`, `lap`,
  `gear`, `athlete`, `discarded_activity`, `nutrition_day`, `food_entry`,
  `meal_note`, `recipe`, `recipe_item`, `favorite_food`, `weight_entry`,
  `day_type`, `meal_slot`, et les buckets Storage `streams` et `photos`.
  Chacune porte `uuid text primary key`, `user_id uuid`, `updated_at timestamptz`,
  `edited_at timestamptz`, `deleted_at timestamptz`.

- [ ] **Étape 1 : Écrire le schéma**

Créer `supabase/schema.sql`. Le gabarit ci-dessous est complet pour `activity` et
`weight_entry` ; les quatorze autres tables se calquent dessus, colonne pour
colonne avec le modèle SwiftData correspondant, en `snake_case`.

```sql
-- Toute table du miroir porte ces cinq colonnes. `updated_at` vient du serveur
-- et ne sert qu'au curseur de pull ; `edited_at` vient de l'appareil qui a fait
-- le geste et ne sert qu'à l'arbitrage. Les confondre casserait le hors-ligne.
create or replace function touch_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create table activity (
  uuid            text primary key,
  user_id         uuid not null references auth.users on delete cascade,
  updated_at      timestamptz not null default now(),
  edited_at       timestamptz,
  deleted_at      timestamptz,

  strava_id       bigint not null default 0,
  source_raw      text not null default 'strava',
  edited_fields   text[] not null default '{}',
  field_edited_at jsonb not null default '{}',
  name            text not null default '',
  sport_type_raw  text not null default 'other',
  start_date      timestamptz not null,
  start_local_date timestamptz not null,
  timezone_identifier text,

  distance        double precision not null default 0,
  moving_time     integer not null default 0,
  elapsed_time    integer not null default 0,
  total_elevation_gain double precision not null default 0,
  average_speed   double precision not null default 0,
  max_speed       double precision not null default 0,
  average_heartrate double precision,
  max_heartrate   double precision,
  average_watts   double precision,
  weighted_average_watts double precision,
  kilojoules      double precision,
  average_cadence double precision,
  calories        double precision,

  is_favorite     boolean not null default false,
  is_commute      boolean not null default false,
  is_trainer      boolean not null default false,
  is_manual       boolean not null default false,
  is_private      boolean not null default false,
  workout_type    integer,
  workout_label_raw text,

  kudos_count     integer not null default 0,
  achievement_count integer not null default 0,
  pr_count        integer not null default 0,
  athlete_count   integer not null default 1,

  start_latitude  double precision,
  start_longitude double precision,
  end_latitude    double precision,
  end_longitude   double precision,

  min_lat         double precision not null default -90,
  max_lat         double precision not null default 90,
  min_lon         double precision not null default -180,
  max_lon         double precision not null default 180,
  has_track       boolean not null default false,

  -- La trace simplifiée reste dans la ligne : quelques kilo-octets, et c'est ce
  -- qui permettra à la carte globale du web de s'afficher en une requête.
  simplified_track bytea,
  summary_polyline text,
  activity_description text,
  device_name     text,
  detail_fetched_at timestamptz,
  photos_fetched_at timestamptz,
  photo_count     integer,
  gear_id         text
);

create trigger activity_touch before insert or update on activity
  for each row execute function touch_updated_at();

-- Le curseur de pull lit dans cet ordre ; sans index, il fera un balayage
-- complet à chaque passage.
create index activity_sync on activity (user_id, updated_at);
create index activity_start on activity (user_id, start_date);

create table weight_entry (
  uuid          text primary key,
  user_id       uuid not null references auth.users on delete cascade,
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz,
  date_key_raw  text not null default '',
  weight_kg     double precision not null default 0,
  note          text
);

create trigger weight_entry_touch before insert or update on weight_entry
  for each row execute function touch_updated_at();
create index weight_entry_sync on weight_entry (user_id, updated_at);
```

Les quatorze tables restantes se dérivent mécaniquement de leur modèle SwiftData.
La procédure est déterministe : ouvrir le fichier dans `Cairn/Model/`, prendre
chaque `var` déclarée, convertir le nom en `snake_case`, et le type selon cette
table. Aucun jugement à porter.

| Swift | Postgres | Nul ? |
|---|---|---|
| `String` | `text not null default ''` | non |
| `String?` | `text` | oui |
| `Int` / `Int64` | `bigint not null default 0` | non |
| `Int?` | `bigint` | oui |
| `Double` | `double precision not null default 0` | non |
| `Double?` | `double precision` | oui |
| `Bool` | `boolean not null default false` | non |
| `Date` | `timestamptz not null` | non |
| `Date?` | `timestamptz` | oui |
| `Data?` | `bytea` | oui |
| `[String]` | `text[] not null default '{}'` | non |
| relation `X?` | `x_uuid text` | oui |
| relation `[X]` | rien — c'est l'enfant qui porte `..._uuid` | — |

Deux exceptions, et elles seules : `ActivityStreams` et `ActivityPhoto`
remplacent leur propriété `Data?` d'octets par `storage_path text`, puisque le
contenu part dans Storage. Les octets ne traversent jamais une ligne.

Puis, pour **chacune** des seize tables :

```sql
alter table activity enable row level security;

create policy "propriétaire seul" on activity
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
```

Et les deux buckets, privés :

```sql
insert into storage.buckets (id, name, public) values
  ('streams', 'streams', false),
  ('photos', 'photos', false);

create policy "propriétaire seul, streams" on storage.objects
  for all
  using (bucket_id = 'streams' and owner = auth.uid())
  with check (bucket_id = 'streams' and owner = auth.uid());

create policy "propriétaire seul, photos" on storage.objects
  for all
  using (bucket_id = 'photos' and owner = auth.uid())
  with check (bucket_id = 'photos' and owner = auth.uid());
```

- [ ] **Étape 2 : Écrire le mode d'emploi**

`supabase/README.md` doit dire, sans supposer de contexte : créer un projet sur
supabase.com ; coller `schema.sql` dans l'éditeur SQL et l'exécuter ; créer
l'utilisateur unique dans Authentication → Users, avec une adresse et un mot de
passe ; relever l'URL du projet et la clé `anon` dans Settings → API. Préciser
que la clé `anon` est publique par construction et que c'est RLS, et seulement
RLS, qui protège les données.

- [ ] **Étape 3 : Appliquer et vérifier que RLS mord**

Appliquer le schéma, puis, en remplaçant les deux valeurs :

```bash
curl -s "https://VOTRE-PROJET.supabase.co/rest/v1/activity?select=uuid" -H "apikey: VOTRE_CLE_ANON"
```

Attendu : `[]`. Un tableau vide prouve que la table existe et que la politique
refuse les lignes d'autrui — un `42P01` voudrait dire que la table manque, et un
résultat non vide que la politique n'a pas pris.

- [ ] **Étape 4 : Commit**

```bash
git add supabase/
git commit -m "feat(miroir): le schéma Postgres et sa politique d'accès"
```

---

### Tâche 2 : Une identité stable sur chaque modèle

`Activity` et `ActivityPhoto` ont déjà un `uuid`. Douze modèles ne l'ont pas, et
sans lui aucune ligne n'est reconnaissable d'un côté à l'autre.

**Seul `uuid` est ajouté, et c'est délibéré.** La spécification donne quatre
colonnes de synchronisation à chaque table ; trois d'entre elles n'ont pas de
raison d'exister côté SwiftData en tranche 1. `updated_at` est l'heure du serveur
et ne sert qu'au curseur de pull, qui n'existe pas encore. `deleted_at` est un
effacement doux côté Postgres ; le Mac, lui, supprime pour de bon et c'est
l'outbox qui porte la trace. `edited_at` est l'heure de l'auteur, que porte le
`changedAt` de l'outbox. Ajouter ces trois propriétés maintenant serait de la
place prise pour rien dans 852 lignes.

**Fichiers :**
- Modifier : `Cairn/Model/FoodEntry.swift`, `Lap.swift`, `ActivityStreams.swift`,
  `WeightEntry.swift`, `NutritionDay.swift`, `FavoriteFood.swift`, `Recipe.swift`
  (deux modèles : `Recipe` et `RecipeItem`), `MealNote.swift`, `MealSlot.swift`,
  `DiscardedActivity.swift`, `Gear.swift`, `DayType.swift`
- Créer : `Tests/MirrorIdentityTests.swift`

**Interfaces :**
- Produit : `var uuid: String = UUID().uuidString` sur chacun de ces modèles.

- [ ] **Étape 1 : Écrire le test qui échoue**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Identités du miroir")
struct MirrorIdentityTests {
    /// Chaque modèle naît avec un identifiant à lui, et deux instances n'en
    /// partagent jamais un : c'est la seule chose qui rendra une ligne
    /// reconnaissable d'un magasin à l'autre.
    @Test func chaqueModeleNaitAvecUnIdentifiant() throws {
        let first = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        let second = WeightEntry(dateKey: DateKey(raw: "2026-08-17")!, weightKg: 71)

        #expect(!first.uuid.isEmpty)
        #expect(first.uuid != second.uuid)
    }

    /// Une ligne écrite puis relue garde le même identifiant. Un `uuid`
    /// recalculé à la lecture ne serait pas une identité.
    @Test func lIdentifiantSurvitAuDisque() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        let expected = entry.uuid
        context.insert(entry)
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<WeightEntry>())
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.uuid == expected)
    }
}
```

Adapter l'initialiseur de `WeightEntry` à sa signature réelle, lue dans
`Cairn/Model/WeightEntry.swift`.

- [ ] **Étape 2 : Lancer le test et le voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorIdentityTests
```

Attendu : ÉCHEC à la compilation, `value of type 'WeightEntry' has no member 'uuid'`.

- [ ] **Étape 3 : Ajouter la propriété aux douze modèles**

Sur chacun, à l'identique de ce que porte déjà `Activity` :

```swift
    /// Stable local identity, independent of any external service. Assigned
    /// once, at creation, and never recomputed: it is what makes a row
    /// recognisable from one store to the other.
    var uuid: String = UUID().uuidString
```

Valeur par défaut, aucun type modifié, aucune contrainte ajoutée : SwiftData
traite l'ajout en migration légère. **Ne pas** l'ajouter à `#Index` — modifier un
index existant est précisément ce qui produit un magasin qui refuse de s'ouvrir.

- [ ] **Étape 4 : Lancer le test et le voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorIdentityTests
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Lancer la suite entière**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

Attendu : SUCCÈS. Une migration de schéma se vérifie sur toute la suite, pas sur
un fichier.

- [ ] **Étape 6 : Commit**

```bash
git add Cairn/Model/ Tests/MirrorIdentityTests.swift
git commit -m "feat(miroir): une identité stable sur chaque modèle"
```

---

### Tâche 3 : Les identifiants Supabase au trousseau

`SecretStore` sait déjà ranger des secrets Strava. Il apprend Supabase, sur le
même patron, plutôt que d'inventer un second mécanisme.

**Fichiers :**
- Créer : `Cairn/Mirror/MirrorCredentials.swift`
- Modifier : `Cairn/Strava/TokenStore.swift` (protocole `SecretStore` et ses
  deux implémentations)
- Créer : `Tests/MirrorCredentialsTests.swift`

**Interfaces :**
- Produit :
  ```swift
  struct MirrorCredentials: Sendable, Equatable, Codable {
      let projectURL: URL
      let anonKey: String
  }
  struct MirrorSession: Sendable, Equatable, Codable {
      let accessToken: String
      let refreshToken: String
      let expiresAt: Date
      let userID: String
      var isExpired: Bool { expiresAt.timeIntervalSinceNow < 300 }
  }
  ```
  et, sur `SecretStore` : `func mirrorCredentials() -> MirrorCredentials?`,
  `func save(_ credentials: MirrorCredentials) throws`,
  `func mirrorSession() -> MirrorSession?`,
  `func save(_ session: MirrorSession) throws`,
  `func clearMirror() throws`.

- [ ] **Étape 1 : Écrire le test qui échoue**

```swift
import Testing
import Foundation
@testable import Cairn

@Suite("Identifiants du miroir")
struct MirrorCredentialsTests {
    /// La marge de cinq minutes qui protège `StravaTokens` protège aussi une
    /// session du miroir : un push long ne doit pas démarrer sur un jeton qui
    /// meurt en vol.
    @Test func uneSessionQuiExpireDansLaMinuteEstDejaExpiree() {
        let session = MirrorSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(60), userID: "u"
        )
        #expect(session.isExpired)
    }

    @Test func uneSessionQuiExpireDansUneHeureNeLEstPas() {
        let session = MirrorSession(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600), userID: "u"
        )
        #expect(!session.isExpired)
    }

    /// Effacer le miroir ne touche pas à Strava. Ce sont deux relations
    /// indépendantes, et se déconnecter de l'une ne dit rien de l'autre.
    @Test func effacerLeMiroirLaisseStravaEnPlace() throws {
        let store = InMemorySecretStore(
            credentials: StravaCredentials(clientID: "c", clientSecret: "s")
        )
        try store.save(
            MirrorCredentials(
                projectURL: URL(string: "https://x.supabase.co")!, anonKey: "k"
            )
        )
        try store.clearMirror()

        #expect(store.mirrorCredentials() == nil)
        #expect(store.credentials() != nil)
    }
}
```

- [ ] **Étape 2 : Lancer le test et le voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorCredentialsTests
```

Attendu : ÉCHEC à la compilation, `cannot find 'MirrorSession' in scope`.

- [ ] **Étape 3 : Écrire les types et étendre le protocole**

Créer `Cairn/Mirror/MirrorCredentials.swift` avec les deux structures de la
section « Interfaces ». Ajouter les cinq méthodes au protocole `SecretStore`,
puis les implémenter dans `KeychainStore` — deux comptes de plus,
`"mirror-credentials"` et `"mirror-session"`, à travers les `read`/`write`/`delete`
privés qui existent — et dans `InMemorySecretStore`, sous le même verrou que le
reste.

Ne **pas** faire passer les nouveaux comptes par `adopting(_:account:)` : la
reprise depuis l'ancien service ne concerne que Strava, et Supabase n'a pas de
passé.

- [ ] **Étape 4 : Lancer les tests et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorCredentialsTests
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Commit**

```bash
xcodegen generate
git add Cairn/Mirror/ Cairn/Strava/TokenStore.swift Tests/MirrorCredentialsTests.swift
git commit -m "feat(miroir): les identifiants Supabase au trousseau"
```

---

### Tâche 4 : Le client PostgREST

**Fichiers :**
- Créer : `Cairn/Mirror/MirrorClient.swift`
- Créer : `Tests/MirrorTestSupport.swift`
- Créer : `Tests/MirrorClientTests.swift`

**Interfaces :**
- Consomme : `MirrorCredentials`, `MirrorSession`, `SecretStore` (tâche 3).
- Produit :
  ```swift
  enum MirrorError: Error, Equatable {
      case notConfigured
      case unauthorized
      case http(status: Int, body: String)
      case transport(String)
  }

  protocol MirrorTransport: Sendable {
      func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
  }

  actor MirrorClient {
      init(store: SecretStore, transport: MirrorTransport = URLSessionTransport())
      func signIn(email: String, password: String) async throws
      func upsert(table: String, rows: [[String: MirrorValue]]) async throws
      func upload(bucket: String, path: String, data: Data, contentType: String) async throws
      var isConfigured: Bool { get }
  }
  ```

- [ ] **Étape 1 : Écrire l'outillage de test partagé**

`Tests/MirrorTestSupport.swift`. Les tâches 6, 7, 9 et 11 s'en servent ; il est
écrit une fois, complet, ici.

```swift
import Foundation
@testable import Cairn

/// A scriptable transport. The client — and everything above it — is tested
/// entirely without a network, which is also what lets the whole suite run
/// with no Supabase project in existence.
actor StubTransport: MirrorTransport {
    private var scripted: [(Data, HTTPURLResponse)]
    private let fallback: HTTPURLResponse?
    private var sent: [URLRequest] = []

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://x.supabase.co")!,
            statusCode: status, httpVersion: nil, headerFields: nil
        )!
    }

    /// Replies with a fixed script, then refuses. Use when the sequence matters.
    init(responses: [(Data, Int)]) {
        scripted = responses.map { ($0.0, Self.response($0.1)) }
        fallback = nil
    }

    /// Replies the same status to everything, forever. Use when only the
    /// requests sent are under test.
    init(alwaysRespondingWith status: Int) {
        scripted = []
        fallback = Self.response(status)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        if !scripted.isEmpty { return scripted.removeFirst() }
        guard let fallback else {
            throw MirrorError.transport("aucune réponse scriptée")
        }
        return (Data(), fallback)
    }

    func requests() -> [URLRequest] { sent }

    /// The tables written to, in the order they were written. `/rest/v1/activity`
    /// gives "activity".
    func tableOrder() -> [String] {
        sent.compactMap { request in
            guard let path = request.url?.path,
                  path.hasPrefix("/rest/v1/") else { return nil }
            return String(path.dropFirst("/rest/v1/".count))
        }
    }

    /// Every `uuid` sent to one table, across all requests.
    func upsertedUUIDs(table: String) -> [String] {
        sent.compactMap { request -> [String]? in
            guard request.url?.path == "/rest/v1/\(table)",
                  let body = request.httpBody,
                  let rows = try? JSONSerialization.jsonObject(with: body)
                      as? [[String: Any]]
            else { return nil }
            return rows.compactMap { $0["uuid"] as? String }
        }.flatMap { $0 }
    }
}

/// A secret store already holding a valid, unexpired mirror session.
func configuredStore() throws -> InMemorySecretStore {
    let store = InMemorySecretStore()
    try store.save(
        MirrorCredentials(
            projectURL: URL(string: "https://x.supabase.co")!, anonKey: "anon"
        )
    )
    try store.save(
        MirrorSession(
            accessToken: "jeton", refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600), userID: "u"
        )
    )
    return store
}
```

- [ ] **Étape 2 : Écrire le test qui échoue**

```swift
import Testing
import Foundation
@testable import Cairn

@Suite("Client du miroir")
struct MirrorClientTests {
    /// Un upsert doit porter l'en-tête qui en fait un upsert. Sans lui,
    /// PostgREST refuse toute ligne déjà présente, et un push rejoué —
    /// c'est-à-dire le cas normal après une coupure — échouerait entièrement.
    @Test func lUpsertDemandeLaFusionDesDoublons() async throws {
        let transport = StubTransport(responses: [(Data(), 201)])
        let client = MirrorClient(store: try configuredStore(), transport: transport)

        try await client.upsert(
            table: "weight_entry",
            rows: [["uuid": .string("abc"), "kilograms": .double(70)]]
        )

        let sent = await transport.requests()
        #expect(sent.count == 1)
        let prefer = sent[0].value(forHTTPHeaderField: "Prefer") ?? ""
        #expect(prefer.contains("resolution=merge-duplicates"))
        #expect(sent[0].url?.path == "/rest/v1/weight_entry")
        #expect(sent[0].value(forHTTPHeaderField: "apikey") == "anon")
        #expect(sent[0].value(forHTTPHeaderField: "Authorization") == "Bearer jeton")
    }

    /// Sans identifiants, le client refuse tout de suite et proprement. C'est
    /// l'état d'une installation qui n'a jamais configuré de miroir, et c'est
    /// un cas ordinaire, pas une erreur.
    @Test func sansIdentifiantsLeClientRefuseSansReseau() async throws {
        let transport = StubTransport(responses: [])
        let client = MirrorClient(store: InMemorySecretStore(), transport: transport)

        await #expect(throws: MirrorError.notConfigured) {
            try await client.upsert(table: "weight_entry", rows: [])
        }
        #expect(await transport.requests().isEmpty)
    }

    /// Un 401 devient `unauthorized` et non une erreur HTTP générique : c'est le
    /// seul statut auquel l'appelant peut répondre par quelque chose d'utile,
    /// à savoir rafraîchir la session.
    @Test func unQuatreCentUnDevientUnRefusIdentifie() async throws {
        let transport = StubTransport(responses: [(Data(), 401)])
        let client = MirrorClient(store: try configuredStore(), transport: transport)

        await #expect(throws: MirrorError.unauthorized) {
            try await client.upsert(
                table: "weight_entry", rows: [["uuid": .string("a")]]
            )
        }
    }
}
```

- [ ] **Étape 3 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorClientTests
```

Attendu : ÉCHEC à la compilation, `cannot find 'MirrorClient' in scope`.

- [ ] **Étape 4 : Écrire le client**

`Cairn/Mirror/MirrorClient.swift`. Points à respecter :

```swift
/// A value a mirrored row can hold. Explicit rather than `Any`, because the
/// rows are built in code and `JSONSerialization` on `Any` would let a wrong
/// type through to a 400 from PostgREST rather than to a compiler error.
enum MirrorValue: Sendable, Equatable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case stringArray([String])
    case null
}
```

- Trois en-têtes sur chaque requête REST : `apikey` (la clé anon), `Authorization: Bearer <accessToken>`, `Content-Type: application/json`.
- Sur un upsert, en plus : `Prefer: resolution=merge-duplicates,return=minimal`.
  `return=minimal` évite de rapatrier les lignes écrites, ce qui n'a aucun
  intérêt et double le trafic.
- `signIn` frappe `POST /auth/v1/token?grant_type=password` et range la
  `MirrorSession` obtenue au trousseau.
- Avant toute requête, si la session est `isExpired`, la rafraîchir par
  `POST /auth/v1/token?grant_type=refresh_token`. Un seul rafraîchissement à la
  fois — c'est ce que l'`actor` garantit.
- Les dates partent en ISO 8601 avec fractions de seconde ; un `Data` part en
  base64, ce que Postgres accepte pour un `bytea` via PostgREST.
- `upload` frappe `POST /storage/v1/object/<bucket>/<path>` avec
  `x-upsert: true`, pour qu'un amorçage rejoué ne bute pas sur ce qu'il a déjà
  déposé.
- Toute erreur de `URLSession` devient `MirrorError.transport`, jamais une
  exception qui remonte telle quelle : l'appelant ne doit avoir qu'un seul type
  d'erreur à traiter.

- [ ] **Étape 5 : Lancer les tests et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorClientTests
```

Attendu : SUCCÈS.

- [ ] **Étape 6 : Commit**

```bash
xcodegen generate
git add Cairn/Mirror/MirrorClient.swift Tests/MirrorTestSupport.swift Tests/MirrorClientTests.swift
git commit -m "feat(miroir): un client PostgREST écrit à la main"
```

---

### Tâche 5 : D'un modèle à une ligne

La conversion est pure : aucun réseau, aucun magasin. C'est la partie la plus
facile à casser en silence et la plus facile à tester.

**Fichiers :**
- Créer : `Cairn/Mirror/MirrorRow.swift`
- Créer : `Cairn/Mirror/MirrorRows+Activity.swift`
- Créer : `Cairn/Mirror/MirrorRows+Nutrition.swift`
- Créer : `Tests/MirrorRowTests.swift`

**Interfaces :**
- Consomme : `MirrorValue` (tâche 4), `uuid` sur les modèles (tâche 2).
- Produit :
  ```swift
  protocol MirrorRow {
      static var mirrorTable: String { get }
      var uuid: String { get }
      func mirrorRow(userID: String) -> [String: MirrorValue]
  }
  ```
  conformé par les seize modèles. `Activity.mirrorTable == "activity"`,
  `WeightEntry.mirrorTable == "weight_entry"`, etc.

- [ ] **Étape 1 : Écrire le test qui échoue**

```swift
import Testing
import Foundation
@testable import Cairn

@Suite("Lignes du miroir")
struct MirrorRowTests {
    /// Les noms de colonnes sont en `snake_case` côté Postgres et en
    /// `camelCase` côté Swift. Aucune conversion automatique ne fait ce
    /// travail, donc il est écrit à la main — et donc il se teste.
    @Test func uneActiviteDonneSesColonnes() {
        let activity = Activity(stravaID: 42, name: "Sortie", sportType: .ride)
        activity.distance = 12_345
        activity.movingTime = 3_600

        let row = activity.mirrorRow(userID: "u")

        #expect(row["uuid"] == .string(activity.uuid))
        #expect(row["user_id"] == .string("u"))
        #expect(row["strava_id"] == .int(42))
        #expect(row["name"] == .string("Sortie"))
        #expect(row["sport_type_raw"] == .string(SportType.ride.rawValue))
        #expect(row["distance"] == .double(12_345))
        #expect(row["moving_time"] == .int(3_600))
        #expect(Activity.mirrorTable == "activity")
    }

    /// Une valeur absente part en `null` explicite, jamais omise. Une colonne
    /// omise d'un upsert garde son ancienne valeur : un cardio effacé
    /// localement resterait alors indéfiniment dans le miroir.
    @Test func unChampAbsentPartEnNulExplicite() {
        let activity = Activity(stravaID: 1, name: "", sportType: .run)
        activity.averageHeartrate = nil

        let row = activity.mirrorRow(userID: "u")

        #expect(row["average_heartrate"] == .null)
        #expect(row.keys.contains("average_heartrate"))
    }

    /// La trace simplifiée traverse en octets bruts. C'est ce qui permettra au
    /// web de la relire avec un `Float64Array` sans rien décoder d'autre.
    @Test func laTraceSimplifieeTraverseEnOctets() {
        let activity = Activity(stravaID: 1, name: "", sportType: .run)
        activity.apply(simplifiedCoordinates: [
            Coordinate(latitude: 45.1, longitude: 5.7),
        ])

        let row = activity.mirrorRow(userID: "u")

        #expect(row["simplified_track"] == .data(activity.simplifiedTrack!))
    }

    /// Le contenu des blobs ne passe pas par la ligne : il part dans Storage, et
    /// la ligne n'en garde qu'un chemin. Sans cette règle, 178 Mo de photos
    /// finiraient dans une base de 500 Mo.
    @Test func unePhotoNEmportePasSesOctets() {
        let photo = ActivityPhoto(uniqueID: "p1")
        photo.data = Data(repeating: 0xFF, count: 1_000)
        photo.activityUUID = "a1"

        let row = photo.mirrorRow(userID: "u")

        #expect(row["storage_path"] == .string("u/p1"))
        #expect(row["activity_uuid"] == .string("a1"))
        #expect(!row.keys.contains("data"))
    }
}
```

Adapter `.ride` / `.run` aux cas réels de `SportType`, lus dans
`Cairn/Model/SportType.swift`.

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorRowTests
```

Attendu : ÉCHEC à la compilation, `value of type 'Activity' has no member 'mirrorRow'`.

- [ ] **Étape 3 : Écrire le protocole et les conformances**

`MirrorRow.swift` porte le protocole. Les deux fichiers `MirrorRows+*.swift`
portent une extension par modèle, chacune énumérant ses colonnes à la main.

Trois règles, valables partout :

1. **Toute colonne est présente**, même nulle. Un upsert PostgREST n'écrit que
   les colonnes fournies ; une colonne omise garde son ancienne valeur.
2. **Les blobs ne traversent pas la ligne.** `ActivityStreams` et
   `ActivityPhoto` émettent un `storage_path`, jamais leurs octets. Le chemin
   est `"<userID>/<identifiant naturel>"` — `uniqueID` pour une photo, `uuid`
   pour un stream.
3. **Aucune valeur calculée.** Ce qui est dérivé sur le Mac se redérivera sur le
   web ; ce qui est mesuré traverse.

- [ ] **Étape 4 : Lancer les tests et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorRowTests
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Vérifier qu'aucune colonne du schéma n'est orpheline**

Relire `supabase/schema.sql` en regard des seize extensions. Toute colonne du
schéma que nulle extension n'émet est soit un oubli, soit une colonne à
supprimer du schéma.

Quatre colonnes font exception et ne doivent **pas** être émises par
`mirrorRow` : `updated_at`, posée par le trigger ; `edited_at` et `deleted_at`,
posées par le moteur au moment de l'envoi (tâches 6 et 9) ; `field_edited_at`,
qui reste vide jusqu'à la tranche 5. `uuid` et `user_id`, en revanche, sont bien
émises par `mirrorRow`.

- [ ] **Étape 6 : Commit**

```bash
xcodegen generate
git add Cairn/Mirror/ Tests/MirrorRowTests.swift
git commit -m "feat(miroir): la conversion d'un modèle en ligne"
```

---

### Tâche 6 : L'amorçage, reprenable

**Fichiers :**
- Créer : `Cairn/Mirror/MirrorEngine.swift`
- Créer : `Cairn/Mirror/MirrorProgress.swift`
- Créer : `Tests/MirrorBootstrapTests.swift`

**Interfaces :**
- Consomme : `MirrorClient` (tâche 4), `MirrorRow` (tâche 5).
- Produit :
  ```swift
  @MainActor @Observable final class MirrorProgress {
      var phase: MirrorPhase
      var lastPushAt: Date?
      var statusText: String { get }
  }
  enum MirrorPhase: Sendable, Equatable {
      case idle
      case bootstrapping(table: String, done: Int, total: Int)
      case pushing(done: Int, total: Int)
      case failed(String)
  }
  actor MirrorEngine {
      init(client: MirrorClient, container: ModelContainer, progress: MirrorProgress)
      func bootstrap() async throws
  }
  ```

- [ ] **Étape 1 : Écrire le test qui échoue**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Amorçage du miroir")
struct MirrorBootstrapTests {
    /// Un amorçage interrompu reprend là où il s'est arrêté, et un amorçage
    /// rejoué en entier ne casse rien. C'est la même propriété — l'idempotence —
    /// vue sous deux angles, et c'est le cœur de ce que 290 Mo sur une
    /// connexion domestique exigent.
    @Test func unAmorcageRejoueNEcritPasDeDoublon() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        for index in 0..<5 {
            context.insert(
                Activity(stravaID: Int64(index), name: "S\(index)", sportType: .run)
            )
        }
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress()
        )

        try await engine.bootstrap()
        try await engine.bootstrap()

        let uuids = await transport.upsertedUUIDs(table: "activity")
        #expect(Set(uuids).count == 5)
    }

    /// Les parents partent avant les enfants. Une ligne `lap` dont l'activité
    /// n'est pas encore là n'a rien à quoi se rattacher.
    @Test func lesParentsPartentAvantLesEnfants() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let activity = Activity(stravaID: 1, name: "S", sportType: .run)
        context.insert(activity)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress()
        )
        try await engine.bootstrap()

        let order = await transport.tableOrder()
        let activityIndex = order.firstIndex(of: "activity")
        let lapIndex = order.firstIndex(of: "lap")
        if let activityIndex, let lapIndex { #expect(activityIndex < lapIndex) }
        #expect(activityIndex != nil)
    }
}
```

`StubTransport` et `configuredStore()` viennent de `Tests/MirrorTestSupport.swift`,
écrit en tâche 4. Le moteur est testé à travers un vrai `MirrorClient` plutôt
que contre un faux client : c'est ce qui met aussi l'encodage réel des requêtes
sous test.

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorBootstrapTests
```

Attendu : ÉCHEC à la compilation, `cannot find 'MirrorEngine' in scope`.

- [ ] **Étape 3 : Écrire le moteur**

L'amorçage parcourt les tables dans un ordre fixe, parents d'abord :

```swift
/// Parents before children: a `lap` whose activity is not there yet has
/// nothing to hang from. The order is fixed rather than derived, because it is
/// a fact about the schema and reading it from the schema would be a way of
/// pretending it might change.
static let bootstrapOrder: [String] = [
    "athlete", "gear", "day_type", "meal_slot",
    "activity", "activity_streams", "activity_photo", "lap",
    "discarded_activity",
    "nutrition_day", "food_entry", "meal_note",
    "recipe", "recipe_item", "favorite_food", "weight_entry",
]
```

Pour chaque table : lire les modèles par lots de 200, les convertir en lignes,
les envoyer en un upsert par lot, avancer un curseur persistant. Le curseur —
`(table, dernier uuid envoyé)` — va dans `UserDefaults`, pas dans le magasin : il
décrit la relation du Mac avec Supabase, comme `SyncState` décrit sa relation
avec Strava, et il n'a rien à faire dans les données de l'utilisateur.

Entre chaque lot, `try Task.checkCancellation()` : un amorçage doit pouvoir être
interrompu par la fermeture de la fenêtre de réglages.

- [ ] **Étape 4 : Lancer les tests et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorBootstrapTests
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Commit**

```bash
xcodegen generate
git add Cairn/Mirror/ Tests/MirrorBootstrapTests.swift
git commit -m "feat(miroir): l'amorçage, reprenable et idempotent"
```

---

### Tâche 7 : Les blobs vers Storage

**Fichiers :**
- Modifier : `Cairn/Mirror/MirrorEngine.swift`
- Modifier : `Cairn/Model/ActivityPhoto.swift` et `Cairn/Model/ActivityStreams.swift`
  (ajout de `mirroredAt`)
- Créer : `Tests/MirrorBlobTests.swift`

**Interfaces :**
- Consomme : `MirrorClient.upload` (tâche 4), `storage_path` sur les lignes
  (tâche 5), `StubTransport` et `configuredStore()` (tâche 4).
- Produit : `MirrorEngine.uploadPendingBlobs()`, appelée par `bootstrap()`, et
  `var mirroredAt: Date?` sur `ActivityPhoto` et `ActivityStreams`.

- [ ] **Étape 1 : Écrire le test qui échoue**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Blobs du miroir")
struct MirrorBlobTests {
    /// Une photo part une fois, dans son bucket, au chemin que sa ligne
    /// annonce. Un chemin qui ne correspondrait pas à la ligne donnerait une
    /// image introuvable depuis le web.
    @Test func unePhotoPartAuCheminQueSaLigneAnnonce() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let photo = ActivityPhoto(uniqueID: "p1")
        photo.data = Data(repeating: 0xAB, count: 128)
        photo.activityUUID = "a1"
        context.insert(photo)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 200)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress()
        )
        try await engine.uploadPendingBlobs()

        let paths = await transport.requests().compactMap(\.url?.path)
        #expect(paths.contains { $0.hasSuffix("/storage/v1/object/photos/u/p1") })
    }

    /// Une photo sans octets ne produit aucune requête. Les activités
    /// synchronisées avant l'arrivée des photos en ont, et téléverser du vide
    /// coûterait 852 requêtes pour rien.
    @Test func unePhotoSansOctetsNeProduitAucuneRequete() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let photo = ActivityPhoto(uniqueID: "p1")
        photo.data = nil
        context.insert(photo)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 200)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress()
        )
        try await engine.uploadPendingBlobs()

        #expect(await transport.requests().isEmpty)
    }
}
```

`StubTransport` et `configuredStore()` viennent de `Tests/MirrorTestSupport.swift`,
écrit en tâche 4. Rien à extraire.

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorBlobTests
```

Attendu : ÉCHEC à la compilation, `value of type 'MirrorEngine' has no member 'uploadPendingBlobs'`.

- [ ] **Étape 3 : Écrire le téléversement**

Parcourir `ActivityPhoto` puis `ActivityStreams`, sauter ceux dont `data` est
nul, téléverser un par un — jamais en parallèle : 342 photos lancées ensemble
saturent le lien et l'egress. Marquer l'envoi par un `mirroredAt: Date?` ajouté
aux deux modèles (propriété optionnelle, migration légère) afin qu'un amorçage
rejoué ne renvoie pas 290 Mo.

**Storage est une copie, jamais l'original.** Les octets restent dans le
stockage externe de SwiftData ; rien n'est effacé localement après envoi.

- [ ] **Étape 4 : Lancer les tests et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorBlobTests
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Commit**

```bash
xcodegen generate
git add Cairn/Mirror/ Cairn/Model/ Tests/
git commit -m "feat(miroir): les traces et les photos vers Storage"
```

---

### Tâche 8 : Savoir ce qui a changé

**Le point risqué du plan, et c'est pour ça qu'il est isolé.** Poser un
`changedAt` à chaque écriture voudrait dire instrumenter des centaines
d'endroits ; `ModelContext.willSave` offre un point unique, au prix d'une API
aux angles vifs.

**Si l'étape 1 montre que la notification ne donne pas ce qu'il faut**, le repli
est écrit : instrumenter les quelques goulots par lesquels les écritures passent
réellement — `ImportMapper`, les éditeurs d'activité, `JournalStore`, les vues
de nutrition — et poser l'entrée d'outbox là. Plus verbeux, sans surprise.

**Fichiers :**
- Créer : `Cairn/Mirror/MirrorOutbox.swift`
- Créer : `Cairn/Mirror/MirrorRecorder.swift`
- Modifier : `Cairn/Model/ModelContainer+App.swift` (ajouter `MirrorOutbox` au schéma)
- Créer : `Tests/MirrorOutboxTests.swift`

**Interfaces :**
- Produit :
  ```swift
  @Model final class MirrorOutbox {
      var table: String = ""
      var rowUUID: String = ""
      var isDeletion: Bool = false
      var changedAt: Date = Date()
  }
  @MainActor final class MirrorRecorder {
      init(container: ModelContainer)
      func start()
      func stop()
  }
  ```

- [ ] **Étape 1 : Écrire le test qui décide de l'approche**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Outbox du miroir")
@MainActor
struct MirrorOutboxTests {
    /// Ce test décide l'architecture de la tâche : si `ModelContext.willSave`
    /// donne bien ce qui a changé, l'outbox se remplit depuis un seul endroit.
    /// S'il échoue, appliquer le repli décrit en tête de tâche.
    @Test func uneEcritureLaisseUneTraceDansLOutbox() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        try context.save()

        let pending = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(pending.contains { $0.rowUUID == entry.uuid && $0.table == "weight_entry" })
    }

    /// Une suppression laisse une trace qui survit à l'objet. Sans elle, une
    /// ligne effacée sur le Mac resterait indéfiniment dans le miroir.
    @Test func uneSuppressionLaisseUneTraceQuiSurvitALObjet() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        let uuid = entry.uuid
        context.insert(entry)
        try context.save()

        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        context.delete(entry)
        try context.save()

        let pending = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(pending.contains { $0.rowUUID == uuid && $0.isDeletion })
    }

    /// L'outbox ne s'enregistre pas elle-même. Sans cette garde, écrire une
    /// entrée déclencherait la notification qui en écrirait une autre.
    @Test func lOutboxNeSEnregistrePasElleMeme() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let context = ModelContext(container)
        context.insert(WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70))
        try context.save()

        let pending = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(pending.allSatisfy { $0.table != "mirror_outbox" })
        #expect(pending.count == 1)
    }
}
```

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorOutboxTests
```

Attendu : ÉCHEC à la compilation, `cannot find 'MirrorRecorder' in scope`.

- [ ] **Étape 3 : Écrire le modèle et l'enregistreur**

`MirrorOutbox` est un `@Model` ordinaire, ajouté au tableau
`AppModelContainer.schema` — un modèle nouveau est une migration légère, comme
le note déjà le commentaire du bloc nutrition.

`MirrorRecorder` s'abonne à `ModelContext.willSave` sur `NotificationCenter.default`.
Dans la réponse : lire `insertedModelsArray`, `changedModelsArray` et
`deletedModelsArray` du contexte, ne garder que ce qui conforme `MirrorRow`, et
insérer une entrée d'outbox par ligne. Les entrées d'outbox elles-mêmes sont
ignorées, sinon la notification se nourrit d'elle-même.

Écrire l'outbox depuis un **second** `ModelContext`, pas depuis celui qui est en
train de sauvegarder : insérer dans un contexte pendant son propre `willSave` est
un comportement qu'aucune documentation ne garantit.

- [ ] **Étape 4 : Lancer les tests**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorOutboxTests
```

Attendu : SUCCÈS. **En cas d'échec persistant sur la notification elle-même,
appliquer le repli décrit en tête de tâche** — ne pas s'acharner sur l'API.

- [ ] **Étape 5 : Lancer la suite entière**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

Attendu : SUCCÈS. Un observateur global de `willSave` peut affecter n'importe
quel test qui écrit — d'où la suite complète ici.

- [ ] **Étape 6 : Commit**

```bash
xcodegen generate
git add Cairn/Mirror/ Cairn/Model/ModelContainer+App.swift Tests/MirrorOutboxTests.swift
git commit -m "feat(miroir): une outbox alimentée par les sauvegardes"
```

---

### Tâche 9 : Le push incrémental

**Fichiers :**
- Modifier : `Cairn/Mirror/MirrorEngine.swift`
- Créer : `Tests/MirrorPushTests.swift`

**Interfaces :**
- Consomme : `MirrorOutbox` (tâche 8), `MirrorClient` (tâche 4).
- Produit : `MirrorEngine.push()`.

- [ ] **Étape 1 : Écrire le test qui échoue**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Push du miroir")
struct MirrorPushTests {
    /// Une entrée d'outbox part, puis disparaît. Une entrée qui survivrait à son
    /// envoi ferait repartir la même ligne à chaque passage.
    @Test func uneEntreeEnvoyeeEstConsommee() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        let pending = MirrorOutbox()
        pending.table = "weight_entry"
        pending.rowUUID = entry.uuid
        context.insert(pending)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress()
        )
        try await engine.push()

        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
        #expect(await transport.requests().count == 1)
    }

    /// Un envoi qui échoue laisse l'entrée en place. C'est toute la raison
    /// d'être d'une outbox : une coupure ne doit rien perdre.
    @Test func unEnvoiQuiEchoueLaisseLEntreeEnPlace() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        let pending = MirrorOutbox()
        pending.table = "weight_entry"
        pending.rowUUID = entry.uuid
        context.insert(pending)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 500)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress()
        )
        _ = try? await engine.push()

        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).count == 1)
    }

    /// Une suppression part en `deleted_at`, jamais en DELETE. Effacer la ligne
    /// pour de bon la ferait revenir au prochain amorçage.
    @Test func uneSuppressionPartEnEffacementDoux() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let pending = MirrorOutbox()
        pending.table = "weight_entry"
        pending.rowUUID = "disparue"
        pending.isDeletion = true
        context.insert(pending)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress()
        )
        try await engine.push()

        let sent = await transport.requests()
        let body = String(data: sent[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("deleted_at"))
        #expect(sent[0].httpMethod == "POST")
    }
}
```

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorPushTests
```

Attendu : ÉCHEC à la compilation, `value of type 'MirrorEngine' has no member 'push'`.

- [ ] **Étape 3 : Écrire le push**

Lire l'outbox groupée par table, retrouver chaque modèle par son `uuid`,
convertir, envoyer un upsert par table. Ne supprimer les entrées **qu'après** un
envoi réussi. Une entrée dont le modèle a disparu sans être marquée
`isDeletion` — cas possible si l'application a été tuée entre deux sauvegardes —
est jetée sans bruit.

Une suppression n'envoie pas la ligne entière, seulement
`{uuid, user_id, deleted_at}` : le reste n'a plus de source locale.

- [ ] **Étape 4 : Lancer les tests et les voir passer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorPushTests
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Commit**

```bash
git add Cairn/Mirror/MirrorEngine.swift Tests/MirrorPushTests.swift
git commit -m "feat(miroir): le push de ce qui a changé"
```

---

### Tâche 10 : L'onglet de réglages

**Fichiers :**
- Créer : `Cairn/Mirror/MirrorSettingsView.swift`
- Modifier : `Cairn/App/AppEnvironment.swift`
- Modifier : `Cairn/App/CairnApp.swift` (ajouter l'onglet à la scène `Settings`)
- Créer : `Tests/MirrorProgressTests.swift`

**Interfaces :**
- Consomme : `MirrorEngine`, `MirrorProgress` (tâche 6).
- Produit : sur `AppEnvironment` — `let mirror: MirrorEngine`,
  `let mirrorProgress: MirrorProgress`, `func startBootstrap()`,
  `func pushNow()`, `var isMirrorConfigured: Bool`.

- [ ] **Étape 1 : Écrire le test qui échoue**

```swift
import Testing
import Foundation
@testable import Cairn

@Suite("État du miroir")
@MainActor
struct MirrorProgressTests {
    /// Jamais muet : un miroir jamais configuré et un miroir à jour ne doivent
    /// pas se lire pareil. C'est la leçon déjà tirée sur `SyncProgress`.
    @Test func unMiroirJamaisConfigureLeDit() {
        let progress = MirrorProgress()
        #expect(progress.statusText.contains("Jamais"))
    }

    @Test func unAmorcageEnCoursAnnonceOuIlEnEst() {
        let progress = MirrorProgress()
        progress.phase = .bootstrapping(table: "activity", done: 120, total: 852)
        #expect(progress.statusText.contains("120"))
        #expect(progress.statusText.contains("852"))
    }

    @Test func unEchecEstDit() {
        let progress = MirrorProgress()
        progress.phase = .failed("réseau injoignable")
        #expect(progress.statusText.contains("réseau injoignable"))
    }
}
```

- [ ] **Étape 2 : Lancer les tests et les voir échouer**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorProgressTests
```

Attendu : ÉCHEC, `statusText` absent ou vide.

- [ ] **Étape 3 : Écrire `statusText` et la vue**

`statusText` se calque sur celui de `SyncProgress`, y compris sur sa règle : ne
jamais rester silencieux.

La vue offre : l'URL du projet et la clé anon en saisie, l'adresse et le mot de
passe pour la connexion, un bouton « Lancer l'amorçage », l'état courant, et un
bouton « Oublier ce miroir » qui appelle `clearMirror()`. Le texte affiché est en
français ; suivre `Cairn/Features/Settings/` pour la mise en forme.

Câbler dans `AppEnvironment` sur le patron de `engine` / `progress`, et ajouter
l'onglet à la scène `Settings` de `CairnApp.swift`.

- [ ] **Étape 4 : Lancer la suite entière**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

Attendu : SUCCÈS.

- [ ] **Étape 5 : Vérifier dans l'application**

Lancer l'application, ouvrir les réglages, saisir de vrais identifiants, lancer
l'amorçage. Puis, dans l'éditeur SQL de Supabase :

```sql
select count(*) from activity;
```

Attendu : 852. Vérifier aussi qu'un bucket `photos` non vide s'affiche dans
Storage.

- [ ] **Étape 6 : Commit**

```bash
xcodegen generate
git add Cairn/ Tests/MirrorProgressTests.swift
git commit -m "feat(miroir): l'onglet de réglages et l'amorçage à la main"
```

---

### Tâche 11 : Le garde-fou d'autonomie

La contrainte fondatrice devient un test. Sans lui, elle n'est qu'une intention
dans un document.

**Fichiers :**
- Créer : `Tests/MirrorAutonomyTests.swift`
- Modifier : `Cairn/App/AppEnvironment.swift` si le test le réclame
- Modifier : `README.md`

- [ ] **Étape 1 : Écrire le test**

```swift
import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Autonomie face au miroir")
@MainActor
struct MirrorAutonomyTests {
    /// Le Mac ne dépend jamais de Supabase. Ce test est la forme exécutable de
    /// la contrainte fondatrice : construire l'environnement complet avec un
    /// miroir injoignable doit être sans effet observable.
    @Test func lApplicationSeConstruitAvecUnMiroirInjoignable() throws {
        let container = try AppModelContainer.inMemory()
        let environment = AppEnvironment(container: container)

        #expect(!environment.isMirrorConfigured)
        #expect(environment.errorMessage == nil)
    }

    /// Écrire, lire et chercher n'attendent rien du réseau. Un `save()` qui
    /// bloquerait sur un push serait une régression invisible en test unitaire
    /// mais fatale à l'usage.
    @Test func lesEcrituresLocalesNAttendentRien() throws {
        let container = try AppModelContainer.inMemory()
        let recorder = MirrorRecorder(container: container)
        recorder.start()
        defer { recorder.stop() }

        let context = ModelContext(container)
        let started = Date()
        for index in 0..<100 {
            context.insert(
                Activity(stravaID: Int64(index), name: "S\(index)", sportType: .run)
            )
        }
        try context.save()

        #expect(Date().timeIntervalSince(started) < 2)
        #expect(try context.fetch(FetchDescriptor<Activity>()).count == 100)
    }
}
```

- [ ] **Étape 2 : Lancer le test**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build -only-testing:CairnTests/MirrorAutonomyTests
```

Attendu : SUCCÈS. **En cas d'échec, c'est le code qui a tort, pas le test** :
retirer du chemin de lancement tout ce qui attend le miroir.

- [ ] **Étape 3 : Lancer la suite entière, sans miroir configuré**

```bash
xcodebuild test -project Cairn.xcodeproj -scheme Cairn -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

Attendu : SUCCÈS, et aucun test ne doit avoir mis plus de quelques secondes à
échouer sur un délai réseau. Un test lent ici signale un appel au miroir sur un
chemin qui ne devrait pas en avoir.

- [ ] **Étape 4 : Documenter dans le README**

Ajouter une section « Miroir en ligne » après « Sauvegarde », disant : ce qu'est
le miroir et ce qu'il n'est pas (une copie, jamais l'original) ; que Cairn
fonctionne intégralement sans lui ; comment le configurer, en renvoyant à
`supabase/README.md` ; et que l'oublier ne perd aucune donnée locale.

- [ ] **Étape 5 : Commit**

```bash
git add Tests/MirrorAutonomyTests.swift Cairn/App/AppEnvironment.swift README.md
git commit -m "feat(miroir): l'autonomie du Mac devient un test"
```

---

## Ce que la tranche 1 ne fait pas

À vérifier avant de la déclarer finie — chacun de ces points est délibéré et
appartient à une tranche ultérieure.

- **Aucun pull.** Rien ne redescend de Supabase. Le curseur `updated_at` est dans
  le schéma et n'est lu par personne.
- **Aucune fusion.** `fieldEditedAt` n'existe pas encore côté Swift ; la colonne
  `field_edited_at` est présente et reste vide. Tranche 5.
- **Les notes du journal ne partent pas.** Elles vivent encore dans le coffre et
  n'ont pas de table. Tranche 2.
- **Aucune ligne de front.**
