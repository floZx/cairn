# StravaLocal

Application macOS native qui conserve une copie locale de vos données Strava et
permet de les consulter hors ligne : liste filtrable, détail d'activité avec
trace et courbes, carte de toutes vos traces, recherche d'activités par zone
géographique et statistiques.

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
`xcodegen generate` est à relancer après l'ajout de tout fichier source.

En ligne de commande, la sortie va dans `build/` :

```bash
xcodebuild build -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

```bash
xcodebuild test -project StravaLocal.xcodeproj -scheme StravaLocal -destination 'platform=macOS,arch=arm64' -derivedDataPath build
```

L'application construite est alors à `build/Build/Products/Debug/StravaLocal.app`.
Ce `-derivedDataPath` n'est pas cosmétique : sans lui, Xcode écrit dans son
`DerivedData` global et deux bundles portant le même identifiant coexistent à
deux chemins. LaunchServices s'y perd et le Dock finit par afficher une icône
générique, alors que l'icône est bien dans les deux bundles.

Vérifier une reconstruction se fait sur `StravaLocal.debug.dylib`, pas sur
l'exécutable `StravaLocal` : ce dernier n'est qu'une amorce de 59 ko dont
l'horodatage ne bouge pas toujours.

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

## Statistiques

La vue Statistiques porte sur les activités **que les filtres laissent**, jamais
sur la bibliothèque entière : le sous-titre de la fenêtre rappelle toujours ce
qui est inclus. Elle donne les cumuls, un histogramme des douze derniers mois,
une ventilation par sport et les records.

Un choix de fond : aucune distance totale n'est affichée globalement. Additionner
une natation, une sortie en vélo électrique et un trail donne un nombre qui
n'informe sur rien. Seuls le nombre d'activités, le temps et le dénivelé sont
cumulés globalement ; la distance se lit par sport.

## Fonds de carte

Trois fonds proviennent d'Apple et ne sollicitent aucun service tiers : Plan,
Satellite, Satellite et noms. Tous rendent le relief du terrain, ce qui a fait
disparaître l'entrée « Plan avec relief » : elle aurait été la même carte sous un
second nom.

Deux fonds topographiques apportent les courbes de niveau et les sentiers, que
MapKit n'offre sous aucune forme. Ce sont les seuls à contacter un serveur
extérieur : chaque déplacement de la carte y envoie des requêtes. Leur
attribution est affichée dès qu'ils sont actifs, comme leurs licences l'exigent.

- **Topographique IGN** — [Plan IGN v2](https://geoservices.ign.fr) via la
  Géoplateforme, accessible sans clé, zoom jusqu'à 19. Le meilleur rendu en
  France : courbes de niveau, bois nommés, hameaux, sentiers. Le SCAN25 au
  1:25000 est en revanche sous licence et refusé aux clients anonymes.
  Attribution : © IGN — Géoplateforme
- **Topographique monde** — [OpenTopoMap](https://opentopomap.org), zoom jusqu'à
  17, couverture mondiale. Attribution : © OpenStreetMap · SRTM · OpenTopoMap
  (CC-BY-SA)

Les tuiles sont conservées dans un cache disque d'un gigaoctet sous
`~/Library/Caches/StravaLocal/Tiles`, et une tuile déjà présente est utilisée
quel que soit son âge : une zone consultée une fois ne se retélécharge pas, même
après un redémarrage. Les réglages affichent la taille occupée et permettent de
la vider.

Le fond d'Apple continue d'être dessiné sous les tuiles topographiques. C'est
volontaire : en le supprimant, toute tuile pas encore dessinée laissait du noir,
et chaque changement de niveau de zoom faisait donc flasher la carte — même
au-dessus d'un terrain déjà en cache, puisqu'il s'écoule toujours un instant
entre le moment où MapKit réclame une tuile et celui où il la dessine. Les deux
fournisseurs servant des tuiles opaques, ce fond est invisible dès qu'elles
arrivent.

En mode sombre, ce fond est en outre épinglé en apparence claire quand un calque
topographique est actif. Les deux fournisseurs ne servent que des tuiles claires
— les capacités WMTS de la Géoplateforme ne déclarent aucune déclinaison nuit de
PLAN IGN — donc un fond sombre en dessous ressortait comme un trou noir le temps
qu'un zoom se stabilise. Les fonds d'Apple, eux, ont un vrai mode sombre et
continuent de suivre le système.

Rien de plus n'est ajouté autour du chargement. Une version antérieure avait
introduit, en même temps que ce cache, un plafond de connexions simultanées et
des réessais : les tuiles cessaient d'arriver. La cause s'est révélée être
ailleurs — des propriétés de `MKMapView` réécrites à chaque mise à jour de vue —
mais la leçon vaut d'être retenue : ne changer qu'une chose à la fois.

Le choix du fond est mémorisé et partagé par les trois cartes.

Sur la carte d'une activité, la caméra est inclinée au chargement pour donner le
relief à voir. Les deux autres restent à plat : elles se lisent d'au-dessus, et
sur la carte globale une zone tracée à l'écran couvrirait un trapèze au sol, ce
qui fausserait la conversion en filtre géographique.

## Emplacement des données

`~/Library/Application Support/StravaLocal/StravaLocal.store`
