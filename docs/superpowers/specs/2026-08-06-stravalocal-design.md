# StravaLocal — Design

**Date:** 2026-08-06
**Statut:** validé

## 1. Objectif

Application macOS native qui conserve une copie locale et complète des données Strava
de l'utilisateur, et permet de les consulter sans réseau : liste filtrable et triable
des activités, détail d'une activité avec sa trace et ses courbes, carte globale de
toutes les traces, et recherche d'activités par zone géographique.

Un seul athlète : le propriétaire du Mac. Pas de multi-compte, pas de partage,
pas de synchro montante vers Strava — la copie locale est en lecture seule vis-à-vis
de Strava.

### Critères de réussite

- Après la première synchro, l'app est pleinement utilisable hors ligne.
- La liste et la carte globale restent fluides sur un historique de plusieurs
  milliers d'activités.
- Une synchro interrompue (quota atteint, app quittée, réseau coupé) reprend où
  elle s'était arrêtée sans réimporter ce qui est déjà là.
- L'interface est indiscernable d'une app macOS système : composants standard,
  aucun style custom.

## 2. Stack et contraintes

| Choix | Valeur |
|---|---|
| Langage | Swift 6.3, strict concurrency |
| UI | SwiftUI + AppKit (`NSViewRepresentable`) là où SwiftUI ne suffit pas |
| Persistance | SwiftData |
| Cartographie | MapKit |
| Graphes | Swift Charts |
| Cible | macOS 15+ |
| Sandbox | désactivé |
| Projet | généré par XcodeGen depuis `project.yml` |

**XcodeGen** : `project.yml` est versionné, `StravaLocal.xcodeproj` est ignoré par git.
Un fichier de configuration lisible et diffable remplace un `pbxproj` illisible.
`xcodegen generate` régénère le projet.

**Sandbox désactivé** : outil personnel, mono-utilisateur. Évite les frictions sur le
serveur loopback OAuth, l'accès Keychain et l'emplacement de la base. Le store
SwiftData vit dans `~/Library/Application Support/StravaLocal/`.

## 3. Architecture

```
StravaLocal/
  App/            StravaLocalApp, RootView, scène Settings
  Model/          SwiftData : Athlete, Activity, ActivityStreams, Lap, Gear, SyncState
  Strava/         StravaClient, DTOs, OAuth, TokenStore, RateLimiter
  Sync/           SyncEngine (actor), ImportMapper
  Geo/            Polyline, BoundingBox, TrackBlob
  Features/
    ActivityList/
    ActivityDetail/
    GlobalMap/
    Settings/
Tests/            GeoTests, ImportMapperTests, RateLimiterTests
```

Les dépendances vont dans un seul sens : `Features` → `Sync` → `Strava` / `Model` → `Geo`.
`Geo` ne dépend de rien d'autre que Foundation et CoreLocation, `Strava` ne connaît pas
SwiftData (il produit des DTOs), `ImportMapper` est le seul point de contact entre les
deux mondes. Chaque couche est donc testable seule.

## 4. Modèle de données

### `Athlete`

Profil Strava : identifiant, prénom/nom, ville/pays, photo (URL), poids, date de
création. Un seul enregistrement.

### `Activity`

Métadonnées issues du résumé Strava :

- identité : `stravaID` (unique, indexé), `name`, `sportType`, `startDate` (indexé),
  `timezone`, `startLocalDate`
- mesures : `distance`, `movingTime`, `elapsedTime`, `totalElevationGain`,
  `averageSpeed`, `maxSpeed`, `averageHeartrate`, `maxHeartrate`, `averageWatts`,
  `weightedAverageWatts`, `kilojoules`, `averageCadence`, `calories`
- drapeaux : `isCommute`, `isTrainer`, `isManual`, `isPrivate`
- social : `kudosCount`, `achievementCount`, `prCount`, `athleteCount`
- géographie : `startLatitude`, `startLongitude`, `endLatitude`, `endLongitude`
- **bounding box** : `minLat`, `maxLat`, `minLon`, `maxLon`, chacune indexée
- **`simplifiedTrack: Data?`** — trace allégée, coordonnées packées
- détail paresseux : `description`, `deviceName`, `detailFetchedAt`
- relations : `gear` (→ `Gear`), `laps` (→ `[Lap]`), `streams` (→ `ActivityStreams?`)

La bounding box et `simplifiedTrack` sont le cœur des performances : ils permettent
d'afficher la carte globale et d'exécuter une recherche géographique sans jamais
charger les streams complets.

### `ActivityStreams`

Relation 1-1 avec `Activity`, chaque stream stocké comme un blob binaire en
`@Attribute(.externalStorage)` : `latlng`, `altitude`, `time`, `heartrate`, `cadence`,
`watts`, `velocitySmooth`, `temp`, `grade`, `moving`. Plus `pointCount`.

Format des blobs (`Geo/TrackBlob`) : tableaux de valeurs à taille fixe, little-endian,
sans en-tête — `Float64` par paire pour `latlng`, `Float32` pour les scalaires,
`Int32` pour `time`. Décodage par `withUnsafeBytes`, donc quasi gratuit. Bien plus
compact et rapide que du JSON, et le blob est un détail d'implémentation confiné à
`TrackBlob` : aucun autre module ne connaît le format.

### `Lap`, `Gear`, `SyncState`

`Lap` : index, nom, distance, temps, D+, vitesse et FC moyennes, plage d'indices dans
les streams. `Gear` : identifiant Strava, nom, marque/modèle, type (vélo/chaussure),
distance totale. `SyncState` : enregistrement unique portant l'état de la synchro —
date du dernier résumé importé, curseur de pagination, file d'attente des streams
restants, date/erreur de la dernière tentative.

### Hors périmètre

`segment_efforts` (volumineux, faible valeur d'usage ici), photos, commentaires,
kudoers, itinéraires, et toute écriture vers Strava.

## 5. Authentification

L'utilisateur crée sa propre application API sur `strava.com/settings/api` avec
`localhost` comme *Authorization Callback Domain*, puis colle Client ID et Client
Secret dans les Réglages. Les deux valeurs et les jetons vivent dans le **Keychain**
(`TokenStore`), jamais sur disque en clair ni dans le dépôt.

Flux loopback (RFC 8252) : `NWListener` ouvre un port éphémère sur la loopback →
`NSWorkspace.open` ouvre la page d'autorisation Strava dans le navigateur par défaut,
avec `redirect_uri=http://localhost:<port>/callback` et le scope
`read,activity:read_all,profile:read_all` → Strava redirige avec le code →
le listener le capte, répond une page de confirmation minimale et se ferme →
échange code contre jetons.

`ASWebAuthenticationSession` est écarté volontairement : il ne peut compléter que sur
un scheme custom ou un universal link `https`, jamais sur `http://localhost`, qui est
le seul type de callback qu'accepte le champ *Authorization Callback Domain* de Strava
pour une app de bureau. Passer par le navigateur par défaut a un bénéfice
supplémentaire : la session Strava de l'utilisateur y est déjà ouverte.

Un paramètre `state` aléatoire est généré à chaque tentative et vérifié au retour ; le
listener rejette toute requête dont le `state` ne correspond pas.

Le rafraîchissement est automatique : `StravaClient` vérifie l'expiration avant chaque
appel et renouvelle si nécessaire. Un refresh refusé (jeton révoqué côté Strava) purge
les jetons et fait repasser l'app en état « déconnecté » sans toucher aux données.

## 6. Moteur de synchronisation

`SyncEngine` est un `actor`. Deux phases.

**Phase A — résumés.** Pagination de `GET /athlete/activities` (200 par page,
paramètre `after` pour l'incrémental). Chaque page est importée immédiatement :
métadonnées, décodage de `map.summary_polyline`, calcul de la bounding box et de
`simplifiedTrack`. Quelques requêtes suffisent pour tout l'historique, donc **la liste
et la carte globale sont exploitables dès la fin de la phase A**.

**Phase B — streams.** Les activités sans streams forment une file persistée dans
`SyncState`. Une requête par activité :
`GET /activities/{id}/streams?keys=…&key_by_type=true` ramène tous les streams d'un
coup. Après import, `simplifiedTrack` est recalculé depuis le stream `latlng`
(plus précis que la polyline de résumé).

**Rate limiting.** `RateLimiter` lit les en-têtes `X-RateLimit-Limit` et
`X-RateLimit-Usage` de chaque réponse (200 requêtes / 15 min, 2000 / jour) et refuse
de partir en requête quand la marge est trop faible : la phase B se met en pause
jusqu'à la fenêtre suivante plutôt que de se faire jeter. Un `429` déclenche un
backoff exponentiel. `RateLimiter` reçoit son horloge par injection, donc il se teste
sans attendre réellement.

**Reprise.** Tout l'état de progression est en base. Quitter l'app, perdre le réseau
ou épuiser le quota interrompt la synchro sans la corrompre : au redémarrage elle
repart de la file restante. L'import est idempotent — un `stravaID` déjà présent est
mis à jour, pas dupliqué.

**Détail paresseux.** `GET /activities/{id}` (description, laps, appareil) n'est
appelé qu'à l'ouverture d'une activité, puis mis en cache via `detailFetchedAt`. La
synchro initiale coûte ainsi une requête par activité au lieu de deux.

## 7. Interface

Fenêtre principale en `NavigationSplitView` à trois colonnes.

**Sidebar** : Toutes les activités, une entrée par sport pratiqué (avec compteur),
Carte globale.

**Liste** : `Table` SwiftUI — colonnes triables et réorganisables (date, nom, sport,
distance, durée, D+, vitesse moyenne, FC moyenne), multi-sélection, `.searchable`
sur le nom. Une barre de filtres au-dessus : sport, période, et plages
distance / durée / dénivelé. Les filtres se composent et se traduisent en un
`Predicate` SwiftData, donc le filtrage se fait en base et non en mémoire.

**Détail** : carte de la trace, grille de statistiques, graphes Swift Charts
(altitude, et fréquence cardiaque ou puissance quand la donnée existe), tableau des
laps. Les streams ne sont chargés qu'ici.

**Réglages** : scène `Settings` standard, onglets *Compte* (credentials, connexion,
athlète) et *Synchronisation* (état, progression, quota restant, synchro complète ou
incrémentale).

Progression de synchro dans la toolbar. Menus, raccourcis (⌘R pour synchroniser),
clair/sombre, restauration de fenêtre : tout par comportement système. **Aucun style
custom** — c'est ce qui donne l'aspect natif.

## 8. Carte globale et recherche géographique

`MKMapView` enveloppé dans un `NSViewRepresentable`. Toutes les traces sont rendues
dans **un unique `MKMultiPolyline`** : des milliers d'overlays indépendants
effondrent MapKit, un seul overlay multi-tracés non. Les tracés viennent de
`simplifiedTrack`, jamais des streams complets. Trait fin et semi-transparent, ce qui
produit naturellement un effet de heatmap sur les passages répétés.

**Recherche géographique** : un mode « sélection » dans lequel l'utilisateur dessine
un rectangle sur la carte. Le filtrage est en deux passes — d'abord intersection des
bounding boxes (colonnes indexées, quasi instantané), ensuite test précis de
présence d'un point du `simplifiedTrack` dans le rectangle. La liste se met à jour
avec le résultat. Cliquer une trace sélectionne l'activité correspondante.

## 9. Tests

Pas de couverture exhaustive : des tests unitaires là où les bugs sont coûteux et
invisibles à l'œil nu, le reste se vérifie en lançant l'app.

- **`Geo`** : décodage de polylines Strava (vecteurs de référence connus), aller-retour
  d'encodage/décodage `TrackBlob`, simplification Douglas-Peucker (préservation des
  extrémités, tolérance respectée), calcul de bounding box, intersection et test
  d'appartenance.
- **`ImportMapper`** : mapping DTO → modèle sur des fixtures JSON de réponses Strava
  réelles, y compris champs absents/nuls et activité manuelle sans trace ;
  idempotence du réimport.
- **`RateLimiter`** : parsing des en-têtes, décision d'attente à l'approche du quota,
  backoff sur 429 — avec horloge injectée.

## 10. Décisions et compromis

- **SwiftData plutôt que GRDB/SQLite direct** : c'est le choix natif, il supprime
  beaucoup de code de persistance. Le risque connu (requêtes complexes limitées) est
  contourné par les colonnes de bounding box indexées et le pré-filtre en deux passes.
- **Streams en blobs binaires plutôt qu'en tables de points** : une table de points
  ferait des dizaines de millions de lignes pour un gain nul — les streams ne sont
  jamais interrogés, seulement lus en entier.
- **Trace simplifiée dupliquée** : redondante avec les streams, mais c'est elle qui
  permet de tout afficher et filtrer sans les charger. Coût disque négligeable.
- **Détail d'activité paresseux** : divise par deux le coût de la synchro initiale
  au prix d'un appel réseau à la première ouverture d'une activité.
- **Streams complets synchronisés d'emblée** : la première synchro d'un gros
  historique s'étale sur plusieurs fenêtres de quota, voire plusieurs jours au-delà
  de 2000 activités. Accepté : l'app reste utilisable pendant, grâce à la phase A.
