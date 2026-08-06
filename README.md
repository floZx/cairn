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

## Fonds de carte

Quatre fonds proviennent d'Apple et ne sollicitent aucun service tiers : Plan,
Plan avec relief, Satellite, Satellite et noms.

Le fond **Topographique** utilise les tuiles d'[OpenTopoMap](https://opentopomap.org),
qui apportent les courbes de niveau et les sentiers — MapKit n'offre aucun
équivalent. C'est le seul fond qui contacte un serveur extérieur : chaque
déplacement de la carte y envoie une requête. Son attribution est affichée dès
qu'il est actif, comme sa licence l'exige :

> © OpenStreetMap · SRTM · OpenTopoMap (CC-BY-SA)

Le choix du fond est mémorisé et partagé par la carte d'activité et la carte
globale.

## Emplacement des données

`~/Library/Application Support/StravaLocal/StravaLocal.store`
