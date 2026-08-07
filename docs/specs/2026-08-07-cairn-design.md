# Cairn — le journal devient la référence

Conception validée le 7 août 2026. Remplace la prémisse d'origine de StravaLocal.

## L'intention

StravaLocal était une copie locale de Strava. Cairn est un **journal d'activités
physiques dont Strava n'est qu'une source d'alimentation**. La différence n'est pas
cosmétique : elle décide qui gagne en cas de désaccord, ce qu'on peut créer sans
Strava, et ce qui reste si le service ferme.

Trois conséquences, dans l'ordre où elles comptent :

1. Une activité peut naître dans Cairn, sans passer par Strava.
2. Ce que tu édites dans Cairn n'est plus écrasé par une synchro.
3. Ce que tu supprimes reste supprimé.

Le nom change pour cesser de mentir : un cairn est le tas de pierres qui marque un
passage en montagne — une trace qu'on laisse et qui dure.

## Décisions prises

| Question | Choix | Pourquoi |
|---|---|---|
| Sens de l'édition | **Local uniquement** | La prémisse même. Aucune écriture chez Strava, donc pas de scope `activity:write` à redemander, pas de quota consommé, pas de mode d'échec à gérer. |
| Granularité de la protection | **Champ par champ** | Renommer une sortie ne doit pas empêcher une resynchro d'apporter la distance ou le cardio corrigés. Figer l'activité entière rendrait la synchro inutile après la première édition. |
| Suppression | **Pierre tombale** | Une suppression est une décision ; le journal étant la référence, une resynchro ne doit pas la défaire. |
| Ajout | **Saisie manuelle + import GPX** | Sans import de fichiers, la dépendance à Strava reste entière là où elle compte : les traces. |
| Renommage | **Complet, avec migration** | Une incohérence sous le capot se voit dès qu'on ouvre le Finder. |

### Ce que l'API Strava permet, vérifié

Relevé dans le schéma OpenAPI (`developers.strava.com/swagger/activity.json`), pas
dans la documentation HTML :

- `PUT /activities/{id}` (scope `activity:write`) accepte `name`, `description`,
  `sport_type`, `gear_id`, `commute`, `trainer`, `hide_from_home`. **Le nom est donc
  modifiable depuis une application tierce**, contrairement à ce qu'on supposait.
- `POST /activities` crée une activité manuelle, sans trace.
- `POST /uploads` crée une activité avec trace depuis un GPX, TCX ou FIT.
- **Aucun `DELETE`** sur `/activities/{id}`.

Rien de tout cela n'est utilisé : l'édition reste locale par choix, pas par
contrainte. C'est consigné ici pour que le choix reste révisable en connaissance de
cause.

## Le modèle

### Identité

`stravaID` est aujourd'hui la clé unique (`#Unique<Activity>([\.stravaID])`). Une
activité créée dans Cairn n'en a pas, et plusieurs zéros violeraient la contrainte.

L'identité se déplace :

- `uuid: String`, toujours renseigné, devient la clé unique.
- `stravaID: Int64` reste, vaut 0 pour ce qui ne vient pas de Strava, et perd sa
  contrainte d'unicité.

On échange un garde-fou de base de données contre le `fetch-or-create` de
`ImportMapper`, qui est déjà le mécanisme réel et déjà couvert par un test de
réimport. Le champ cesse de mentir, ce qui vaut mieux qu'un identifiant négatif
inventé pour satisfaire un index.

### Ajouts sur `Activity`

- `sourceRaw: String` — `strava`, `manual` ou `file`, derrière un enum
  `ActivitySource`. Permet à la synchro d'ignorer d'emblée ce qui ne la concerne
  pas, et de l'afficher dans le détail.
- `editedFields: [String]` — les clés des champs que l'utilisateur a touchés.
- `editedAt: Date?` — pour l'afficher dans le détail.

Les clés viennent d'un `enum ActivityField: String, CaseIterable` plutôt que de
chaînes libres : une faute de frappe échouerait en silence, et le seul symptôme
serait une édition écrasée à la synchro suivante — un bug indétectable à la
lecture.

### Protection à la synchro

`ImportMapper.upsert(summary:)` réécrit une vingtaine de champs sans condition, et
c'est le seul endroit à modifier. Chaque affectation passe par un point de contrôle
unique qui consulte `editedFields` :

```swift
mapper.assign(.name, to: dto.name)   // n'écrit que si le champ n'est pas édité
```

Un champ absent de `editedFields` continue d'être mis à jour normalement. Une
activité dont `source != .strava` n'est jamais touchée par la synchro.

### Suppression

Nouveau modèle `DiscardedActivity` : `stravaID: Int64`, `discardedAt: Date`.

- La synchro écarte ces identifiants **avant** de créer quoi que ce soit, phase A
  comprise, pour ne pas dépenser de requête sur une activité écartée.
- Un écran dans les réglages les liste et permet d'annuler. Sans lui, une
  suppression accidentelle serait définitive et invisible — le pire des deux.

### Migration de schéma

Trois champs avec valeurs par défaut et un modèle supplémentaire : SwiftData
migre légèrement, sans code. Aucun champ existant n'est renommé ni supprimé, ce qui
est précisément la condition pour que ce soit vrai.

`uuid` doit être renseigné pour les lignes existantes. Un passage unique au
lancement le fait pour les activités dont l'`uuid` est vide, au même endroit que le
déplacement du dossier de données — un seul point d'entrée pour tout ce qui doit
arriver une fois, plutôt que deux mécanismes à retrouver plus tard.

## Les gestes

### Édition

Une feuille modale (⌘E), pas d'édition en ligne. Deux raisons : un
« Enregistrer » explicite fait savoir quels champs ont réellement été touchés — ce
qui est exactement ce que `editedFields` doit contenir — et une modification par
inadvertance ne fige pas un champ pour toujours.

Modifiables : nom, sport, date et heure, distance, durée, D+, notes, marqueurs
domicile-travail et home-trainer.

Non modifiables : les séries mesurées — cardio, puissance, cadence, altitude — qui
viennent de l'appareil et dont aucune valeur unique saisie à la main n'aurait de
sens. La trace non plus.

Seuls les champs dont la valeur diffère de l'existante entrent dans
`editedFields`. Rouvrir la feuille et enregistrer sans rien changer ne fige rien.

### Ajout manuel

La même feuille, vide. Sport, date et durée obligatoires. `source: .manual`,
`stravaID: 0`, aucune trace.

### Suppression

⌘⌫ et menu contextuel, avec confirmation — et la confirmation dit laquelle des deux
suppressions elle est. Une activité Strava laisse une pierre tombale et ne
reviendra pas à la resynchro ; une activité locale disparaît simplement. Ce ne sont
pas les mêmes conséquences, ce ne peut pas être le même texte.

### Import GPX

Fichier → Importer… (⌘O), sélection multiple.

`GPXImporter` isolé et testable : `Data` en entrée, une valeur `GPXTrack` en
sortie, via `XMLParser` de Foundation — aucune dépendance ajoutée. Lit `trkpt`
(`lat`, `lon`), `ele`, `time`, et le `name` de la trace.

La couche géo existante enchaîne derrière, sans rien de neuf : `Simplify`,
`BoundingBox`, `DistanceAxis`, `TrackBlob`.

Trois points de conception assumés :

- **Le sport n'est pas fiable dans un GPX.** Le panneau d'import le demande, une
  fois pour le lot.
- **Le temps en mouvement ne se déduit pas honnêtement** sans inventer un seuil de
  vitesse. `movingTime = elapsedTime`, et le champ est modifiable. Mieux vaut un
  chiffre visiblement approximatif qu'un chiffre qui aurait l'air mesuré.
- **Le doublon est le cas réel** : importer le GPX d'une sortie déjà synchronisée.
  Seuils explicites plutôt que « proche » : départ à moins de **15 minutes** et
  distance à moins de **5 %** ⇒ l'import le signale et laisse choisir, plutôt que de
  créer un jumeau silencieux. Quinze minutes parce qu'une montre et Strava peuvent
  diverger sur l'instant de départ ; 5 % parce que la distance d'un même parcours
  varie avec l'algorithme qui l'a calculée.

## Le renommage

### Portée

Cible et nom de produit, identifiant de bundle `com.florianmaisonnial.Cairn`,
dossier source `StravaLocal/` → `Cairn/`, icône, textes visibles, README, dépôt.

Strava garde son nom là où il s'agit bien de Strava : la connexion, les
identifiants, la synchro.

### Migration des données

Le dossier `Application Support/StravaLocal` est déplacé vers `Cairn`, **en gardant
le nom du fichier** `StravaLocal.store` à l'intérieur.

C'est délibéré. Les streams sont en `@Attribute(.externalStorage)`, donc hors de la
base, dans un dossier annexe dont SwiftData dérive le nom de celui du fichier.
Renommer le fichier reviendrait à parier sur une convention interne, et une erreur
orphelinerait précisément les blobs les plus coûteux à retélécharger — 200 requêtes
par quart d'heure. Le nom du fichier ne se voit pas ; le dossier, si.

Le déplacement n'a lieu que si le nouveau dossier n'existe pas et l'ancien oui.
Idempotent, et sans effet sur une installation neuve.

### Trousseau

Au lancement, si rien n'existe sous `…Cairn` et que des identifiants existent sous
`…StravaLocal`, ils sont recopiés puis l'ancien est supprimé. Sinon il faudrait
recoller Client ID et secret à la main.

### Réglages

L'onglet « Synchronisation » devient « Sources ». Strava n'y est plus qu'une entrée,
à côté de l'import de fichiers. C'est le repositionnement rendu visible à l'endroit
où on le cherche.

### Icône

Un cairn géométrique — trois ou quatre pierres empilées, à plat — généré par script
dans les dix tailles du catalogue. Point de départ remplaçable, pas une œuvre.

## Ordre de mise en œuvre

Six chantiers, trop pour un seul lot. L'ordre n'est pas indifférent :

1. **Le modèle et la protection.** `uuid`, `source`, `editedFields`, le point de
   contrôle dans `ImportMapper`, `DiscardedActivity`. Rien de visible, mais tout le
   reste en dépend, et c'est là qu'est le risque sur les données.
2. **Les gestes.** Feuille d'édition, ajout manuel, suppression avec confirmation,
   écran des activités écartées. Rend le lot 1 utilisable.
3. **L'import GPX.** Indépendant des deux précédents : un lecteur isolé, ses
   fixtures, la détection de doublon, le panneau d'import.
4. **Le renommage et la migration.** En dernier, délibérément : renommer d'abord
   obligerait à réécrire chaque fichier touché par les lots précédents, et mélanger
   un renommage massif avec des changements de comportement rend toute régression
   indémêlable.

## Tests

Ce qui doit être couvert, et pourquoi :

- **`editedFields` protège, et seulement ce qu'il faut.** Un champ édité survit à un
  réimport ; un champ non édité est bien mis à jour par le même réimport. Les deux
  assertions comptent : la seconde est ce qui distingue la protection champ par
  champ du gel de l'activité entière.
- **Enregistrer sans modifier ne fige rien.**
- **Une activité `source != .strava` est ignorée par la synchro.**
- **Une pierre tombale survit à une resynchro complète**, et l'annuler ramène
  l'activité au passage suivant.
- **`GPXImporter`** sur fixtures : trace nominale, fichier sans altitude, fichier
  sans horodatage, XML malformé, fichier vide. Un GPX mal formé ne doit pas faire
  tomber l'application.
- **Détection de doublon** aux deux bornes : dans les seuils ⇒ signalé ; juste
  au-delà de l'un des deux ⇒ importé sans question. Un seuil ne se teste qu'en le
  franchissant.
- **Migration** : dossier ancien présent et nouveau absent ⇒ déplacé ; les deux
  présents ⇒ intact ; aucun des deux ⇒ sans effet.

## Hors périmètre

Nommé pour qu'on ne l'y glisse pas sans décision :

- Écriture vers Strava, sous quelque forme que ce soit.
- FIT et TCX. Le FIT est binaire : c'est un chantier à lui seul, plus gros que tout
  ce lot.
- Édition des séries mesurées et des traces.
- Autres sources (Apple Santé, Garmin Connect). L'enum `ActivitySource` laisse la
  place sans rien promettre.
