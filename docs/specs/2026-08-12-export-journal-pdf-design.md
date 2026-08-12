# Exporter un carnet — le journal en PDF

**Date** : 2026-08-12
**Statut** : validé

## Objectif

Sortir de Cairn un **carnet à relire** : un PDF d'une période choisie, où
chaque journée porte ce qui a été vécu et écrit ce jour-là — la note du coffre,
les sorties avec leur trace et leurs courbes, les photos, l'alimentation et le
poids.

Un carnet, pas une archive. Ce qui aide à revivre la journée entre ; le reste —
le détail aliment par aliment, les tours, les champs Strava bruts — reste dans
l'application, où il est déjà lisible.

## Décisions structurantes (validées avec l'utilisateur)

1. **HTML puis `WKWebView.createPDF`.** La seule vraie difficulté d'un tel
   document est la pagination : une journée tient en dix lignes ou en trois
   pages selon le nombre de sorties, et rien ne doit se couper au milieu d'une
   carte. WebKit sait le faire ; ni `ImageRenderer` — qui rend une vue par page
   et laisserait le découpage à écrire à la main — ni Core Graphics ne le
   savent. Le prix assumé : une seconde pile de rendu (HTML/CSS) entre dans une
   application qui n'en avait pas. En échange, l'apparence se règle dans une
   feuille de style, sans recompiler.

2. **Une période libre**, deux dates à choisir avant d'exporter, préremplies
   sur le mois affiché.

3. **Un jour muet ne prend pas de place.** Un carnet où une page sur deux dit
   « rien » n'est pas un carnet. Une journée entre si elle porte au moins une
   des quatre choses : une note du coffre, une sortie, une note de repas ou de
   pesée, un poids.

4. **Le document est autonome.** Images en `data:` URI dans le HTML — un
   fichier, aucun dossier d'accompagnement.

5. **Aucun réglage d'apparence.** La feuille de style est la réponse.

## Le contenu

### Page de garde

La période en toutes lettres, et ce qu'elle pèse : nombre de sorties, distance,
dénivelé et temps cumulés, répartis par sport ; le poids au début et à la fin de
la période quand les deux existent.

### Une section par journée

Dans cet ordre, chaque partie disparaissant si elle est vide :

1. **La date**, en toutes lettres.
2. **La note du coffre**, rendue en Markdown — titres, listes, citations, gras
   et italique — avec ses tags en fin de bloc, sans leur dièse, comme partout
   où une note se lit dans l'application.
3. **Chaque sortie**, dans l'ordre où elles ont eu lieu :
   - la carte, trace comprise ;
   - l'heure de départ, lue dans le fuseau où la sortie a eu lieu, le sport, le
     nom ;
   - distance, temps en mouvement, dénivelé positif, FC moyenne, allure ou
     vitesse selon le sport — la même règle d'unité qu'à l'écran, y compris la
     cadence comptée en pas pour la course ;
   - les courbes d'altitude et de fréquence cardiaque, quand les flux existent ;
   - les photos de la sortie ;
   - la note de la sortie, rendue en Markdown elle aussi.
4. **Alimentation et poids** : le poids du jour et son commentaire, puis par
   repas ses totaux (kcal, P/G/L) et sa note.

## L'architecture

Trois pièces, chacune testable seule, et une quatrième qui les assemble.

### 1. La collecte — `JournalBook`

Une fonction pure : deux dates et les données du magasin en entrée, la liste
des journées à imprimer en sortie, dans l'ordre, avec pour chacune sa note, ses
sorties, ses repas, son poids. Aucune vue, aucune image, aucun accès disque.

C'est ici que vit la règle du jour muet, et c'est ici qu'elle se teste.

Le jour d'une sortie est le `DateKey` de son instant dans le calendrier de ce
Mac, la règle que `JournalDaySources` applique déjà — un carnet et une liste qui
rangeraient une sortie sous deux jours différents seraient un défaut à eux seuls.

### 2. Les images — `JournalBookAssets`

Produites une fois chacune, avant le HTML, et rendues sous forme de `data:` URI
indexés par ce qu'ils illustrent :

- **les cartes**, par `MKMapSnapshotter`, la trace dessinée par-dessus
  l'instantané avec la couleur du sport ;
- **les courbes**, par `ImageRenderer` sur les mêmes vues Swift Charts que
  l'écran, alimentées par `StreamSeriesBuilder` ;
- **les photos**, qui sont déjà des octets en base — rien à télécharger, juste
  à encoder.

Cette pièce est la seule à toucher au réseau et à la vue. C'est elle qui prend
du temps : elle rend sa progression, une image après l'autre.

### 3. Le HTML — `JournalBookHTML`

Une fonction pure `[Journée] → String`, la feuille de style incluse. Elle porte
tout le « joli » et se teste sans rien afficher : structure, échappement,
présence ou absence des blocs.

Le Markdown des notes passe par un nouveau petit rendu `MarkdownHTML`, adossé au
`MarkdownParser` qui existe déjà pour l'écran : mêmes blocs reconnus, donc une
note rendue pareil dans le carnet et dans l'application. L'inline — gras,
italique, code — et l'échappement des caractères HTML sont son affaire propre.

La pagination est dite au CSS, pas calculée : `break-inside: avoid` sur un bloc
de sortie, sur une carte, sur une photo ; une journée peut se couper entre deux
sorties, jamais au milieu de l'une.

### 4. L'assemblage — `JournalBookExporter`

Collecte, images, HTML, puis `WKWebView.createPDF`, puis l'écriture. Le
`WKWebView` est hors écran, chargé avec `loadHTMLString`, et le PDF demandé
quand le chargement est fini.

## L'interface

*Fichier ▸ Exporter le journal en PDF…*, dans le même groupe que l'export GPX,
qui est déjà là où macOS range ces choses.

Une feuille demande les deux dates, préremplies sur le mois affiché, et rien
d'autre. Puis le panneau d'enregistrement.

La feuille **reste à l'écran** pendant la fabrication et y montre sa
progression — « carte 3 sur 12 » — au lieu de se refermer sur une fenêtre qui
ne répond plus : les instantanés de cartes sont la partie lente, et dix
secondes de silence passent pour un gel. Elle se ferme quand le fichier est
écrit.

## Ce qui peut rater

- **Sans réseau**, `MKMapSnapshotter` ne rend rien. La sortie garde alors sa
  trace dessinée en vectoriel — la projection de `TrackThumbnail`, déjà écrite
  et déjà testée, émise en SVG. Moins joli qu'une carte, mais jamais un trou.
- **Une photo illisible** est sautée. Une image manquante ne vaut pas un export
  perdu.
- **Une période sans une seule journée** : l'export est refusé avant le panneau
  d'enregistrement, avec un message qui le dit. Un PDF d'une page de garde
  seule serait une déception silencieuse.
- **L'échec d'écriture** se dit dans la même alerte que l'export GPX.

## Tests

- La collecte : un jour muet n'entre pas ; un jour qui ne porte qu'une note de
  repas entre ; une sortie est rangée sous le jour de son instant local ; les
  journées sortent dans l'ordre.
- Les totaux de la page de garde : distance, dénivelé, temps et compte par
  sport sur une période connue.
- Le HTML : une journée sans sortie ne produit aucun bloc de sortie ; un `&`
  ou un `<` dans une note ressort échappé ; une note en Markdown ressort avec
  ses balises HTML et sans le dièse de ses tags ; une image absente ne laisse
  pas de `<img src="">`.
- `MarkdownHTML` : les blocs que le parseur reconnaît déjà, plus l'inline et
  l'échappement.

Les images et le PDF lui-même ne sont pas testés automatiquement : ils
demandent le réseau, une vue et WebKit. La vérification est à l'œil, sur un
export réel.

## Hors périmètre

- Le détail aliment par aliment, les tours d'une sortie, les champs Strava
  bruts.
- Tout réglage d'apparence dans l'interface.
- L'export d'une sélection d'activités, ou d'une année entière en un clic : la
  période libre les couvre déjà toutes les deux.
