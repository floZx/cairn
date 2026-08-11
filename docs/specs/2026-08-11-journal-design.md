# Journal — une note par jour, dans un coffre Obsidian

**Date** : 2026-08-11
**Statut** : validé

## Objectif

Une section « Journal » dans Cairn : **une note Markdown par jour**, rangées
dans un dossier choisi par l'utilisateur, **compatibles avec les notes du jour
d'Obsidian**. La recherche porte sur toutes les notes, et les tags servent de
filtre.

Le coffre de référence est
`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/cairn`, où le module
*Daily notes* d'Obsidian est actif avec ses réglages par défaut : format
`YYYY-MM-DD`, à la racine du coffre.

## Décisions structurantes (validées avec l'utilisateur)

1. **Liste + détail**, à la manière de « Mes activités » : la colonne centrale
   liste les notes, le volet de droite affiche celle qui est sélectionnée. Pas
   de « un jour à la fois » comme Alimentation.
2. **Lecture en Markdown rendu, édition au clic** : le volet de droite affiche
   la note rendue — titres, listes, citations — et devient un champ de texte dès
   qu'on clique dedans, ou sur `e`, `n` ou `⏎` depuis la liste. Échap rend la
   note à nouveau.

   *Révision du 11 août 2026.* La première version était « toujours éditable,
   texte brut », au motif qu'un journal est fait pour être écrit et qu'un aperçu
   met une frappe entre la pensée et la page. L'usage a tranché dans l'autre
   sens : on relit son journal bien plus souvent qu'on ne l'écrit, et les `#` et
   les `-` en tête de chaque ligne ne sont du bruit que les jours où l'on ne
   fait que lire. Écrire coûte maintenant un clic, ou la touche qu'on tapait
   déjà pour écrire.

   Trois conséquences assumées : le curseur se place **en fin de texte** et non
   à l'endroit cliqué — ce sont deux vues, et SwiftUI ne transporte pas la
   position du clic de l'une à l'autre ; **changer de note revient toujours en
   lecture**, arriver dans l'éditeur se demande ; une note illisible garde son
   écran d'indisponibilité et ne devient jamais éditable.
3. **Tags dans la barre latérale**, en cases à cocher avec leur nombre, à la
   place des filtres d'activité.
4. **Uniquement les notes du jour** : seuls les fichiers `AAAA-MM-JJ.md` à la
   racine du dossier existent pour Cairn. Le reste du coffre est ignoré, y
   compris en recherche.
5. **Surveillance du dossier en direct**, parce que les mêmes fichiers sont
   édités depuis Obsidian sur iPhone et arrivent par iCloud.

## 1. Le dossier est la base de données

Rien dans SwiftData. Le disque est la seule vérité : un miroir en base créerait
deux sources qui divergeraient à la première note écrite ailleurs, et c'est
précisément la compatibilité Obsidian qu'on achète en s'en passant.

- **Nom de fichier** : `AAAA-MM-JJ.md`, à la racine du dossier. Le nom *est* la
  clé, et `DateKey` valide déjà exactement ce format — `DateKey(raw:)` sert donc
  de filtre : ce qu'il refuse n'est pas une note du jour. Aucun `DateFormatter`,
  donc aucune dépendance à la locale ou au fuseau.
- **Sous-dossiers** : non parcourus.
- **Contenu en mémoire** : le texte entier de chaque note est gardé. Dix ans de
  journal font quelques mégaoctets ; la recherche n'a alors aucun fichier à
  ouvrir, et l'index FTS5 qu'on aurait pu construire n'aurait servi qu'à
  rattraper une lenteur qui n'existe pas.

### `JournalNote`

Une valeur, pas un objet :

| Champ | Type |
|---|---|
| `date` | `DateKey` |
| `text` | `String` |
| `tags` | `Set<JournalTag>` |

Les tags sont dérivés de `text` à la lecture, jamais stockés sur disque.

### Écriture

- Enregistrement automatique **0,7 s après la dernière frappe**, et immédiat
  quand on change de note, quitte la section, ou ferme la fenêtre.
- Écriture atomique (`Data.write(to:options:.atomic)`).
- **Une note vidée est supprimée du disque.** Ouvrir la note du jour et ne rien
  y écrire ne doit pas laisser un fichier vide dans le coffre, où Obsidian le
  listerait pour rien. Le critère est « vide après suppression des blancs ».
  Ce fichier-là est effacé directement, sans passer par la corbeille : il ne
  contient rien, et une corbeille pleine de notes jamais écrites est du bruit.
- **La suppression demandée met à la corbeille** (`FileManager.trashItem`),
  elle ne détruit pas. Ce sont les fichiers de l'utilisateur dans son propre coffre, pas
  les lignes d'une base dont l'app est propriétaire.

### Surveillance

Un `DispatchSource.makeFileSystemObjectSource` sur le descripteur du dossier,
événements `.write | .rename | .delete`, coalescé pour ne pas relire dix fois
pendant qu'iCloud dépose une rafale de fichiers.

À chaque réveil, le dossier est relu. Si le fichier modifié est **celui qui est
en cours d'édition et que le tampon est sale**, Cairn garde le texte tapé et
affiche un bandeau « Modifiée ailleurs — Recharger ». Écraser silencieusement
ferait disparaître une phrase sous le curseur ; écraser dans l'autre sens ferait
perdre ce qui a été écrit sur le téléphone.

### Sauvegarde iCloud

Le journal **n'entre pas** dans la sauvegarde de `BackupService`. Le dossier est
déjà dans iCloud Drive, et copier un dossier iCloud dans iCloud n'ajoute aucune
protection. Le pied de page du réglage le dit explicitement, pour que l'absence
se lise comme un choix et non comme un oubli.

## 2. Les tags

Extraits à la lecture de chaque note.

**Inline `#tag`** — caractères admis : lettres, chiffres, `_`, `-`, `/`. Deux
exclusions, qui sont celles d'Obsidian :

- un titre Markdown n'est pas un tag : `#` suivi d'une espace ;
- un tag entièrement numérique n'en est pas un : `#2026` est une année.

**Frontmatter YAML** — un bloc `---` en tête de fichier avec une clé `tags:`,
en liste sur une ligne (`tags: [sam, promenade]`) ou en liste à puces. Obsidian
en écrit, autant les lire.

**Imbriqués** — `#projet/cairn` compte pour lui-même *et* pour `#projet`, sinon
cocher le parent ne montrerait rien.

### Dans la barre latérale

Quand `Journal` est sélectionné, les sections Sports / Filtres / Étiquettes
disparaissent (même mécanisme que `showsFilters` pour Alimentation et Poids) et
une section **Tags** prend leur place : chaque tag avec son nombre, trié par
fréquence décroissante puis par nom, case à cocher comme les Sports.

**Plusieurs tags cochés se combinent en ET**, à l'inverse des sports. Une
activité n'a qu'un sport, donc un ET n'y donnerait jamais rien ; une note en a
plusieurs, et l'intérêt de cocher le deuxième est de resserrer.

### Cliquer un tag

Dans le volet de droite, un clic passe en édition et un clic dans l'éditeur pose
le curseur : les tags n'y sont cliquables ni en lecture ni en écriture. Ils le
sont **en pastilles** : sur la ligne de la liste, et dans l'en-tête au-dessus de
la note. Un clic sur une pastille coche le tag correspondant dans la barre
latérale.

## 3. L'écran

`SidebarItem.journal`, entre `.statistics` et `.nutrition`, icône
`text.book.closed`, badge = nombre de notes.

**Colonne centrale** — la liste, la plus récente en haut. Chaque ligne : la date
en toutes lettres (« mardi 11 août 2026 »), un extrait, les pastilles de tags.
Le champ `.searchable` cherche dans le texte entier, insensible à la casse et
aux accents. Recherche et tags cochés se cumulent : la liste montre les notes
qui satisfont les deux.

Quand une recherche est active, **l'extrait montre le passage qui correspond**
plutôt que le début de la note : une liste de résultats qui n'affiche nulle part
ce qu'elle a trouvé oblige à ouvrir chaque note pour le savoir.

**Volet de droite** — un en-tête (la date, les pastilles de tags) puis, sur
toute la hauteur restante, la note rendue par `MarkdownText`, le composant qui
sert déjà les notes d'activité, ou le `TextEditor` quand on écrit.

Toute la surface du volet prend le clic, pas seulement le texte : une note vide
n'offre rien à viser, et une invite discrète — « Cliquez pour écrire » — le dit,
faute de quoi un volet blanc qui se transforme en éditeur ne s'annonce nulle
part.

Le **frontmatter n'est pas rendu** : `JournalNote.body(of:)` l'enlève avant
d'appeler le renderer, sinon chaque note en porterait un paragraphe « --- tags:
[sam] --- » en tête. Ce saut est dans le journal et non dans `MarkdownParser`,
qui rend aussi les notes d'activité : celles-ci sont un champ de base de
données et jamais un fichier, un `---` qu'on y tape est un séparateur voulu, et
un parseur qui l'avalerait interpréterait un texte qui ne le lui demande pas.

Le bandeau de conflit et la ligne d'échec d'écriture sont dans l'en-tête, donc
visibles dans les deux modes : ce sont eux qui préviennent d'une perte.

**Sans dossier configuré** — un panneau à la manière de `WelcomeView` : ce
qu'est le journal, un bouton « Choisir un dossier… », et le fait qu'un dossier
de notes du jour Obsidian existant s'ouvre tel quel.

### Clavier et barre d'outils

| | |
|---|---|
| `gj` | aller au journal |
| ⌘N | la note du jour — la crée si besoin, la sélectionne, place le curseur dedans |
| `j` `k` `gg` `G` `⌃d` `⌃u` | parcourir la liste, comme partout |
| `e` · ⏎ | passer le clavier dans l'éditeur |
| clic dans le volet | passer en édition, curseur en fin de texte |
| `/` | aller au champ de recherche |
| `échap` | sortir de l'éditeur — la note repasse en lecture —, puis vider la recherche, puis les tags cochés, puis la sélection |
| ⌘⌫ · `x` | supprimer la note, après confirmation |

⌘N veut déjà dire « nouvelle activité » : dans la section Journal il change de
sens, en aiguillant `app.requestNewActivity` sur la section ouverte plutôt qu'en
ajoutant un second raccourci. La barre d'outils remplace de même le groupe
d'actions d'activité par un bouton « Note du jour » (`showsActivityActions`
couvre déjà ce cas de figure).

Les commandes qui touchent une activité sont refusées dans le journal, comme
elles le sont dans Alimentation : un `x` égaré ne doit pas supprimer une sortie
restée sélectionnée derrière l'écran. `performInNutrition` porte déjà cette
règle et sera renommé pour couvrir les trois sections de journal.

## 4. Réglages

Un sixième onglet dans `SettingsScene`, « Journal », icône `text.book.closed` :

- le chemin du dossier, ou « aucun dossier choisi » ;
- un bouton « Choisir… » — `NSOpenPanel`, `canChooseDirectories`, dossiers
  seulement ;
- le nombre de notes trouvées, qui confirme immédiatement qu'on a désigné le bon
  dossier ;
- un pied de page sur la compatibilité Obsidian et sur l'exclusion de la
  sauvegarde.

Le chemin va dans `@AppStorage("journalFolderPath")`, sous forme de chemin en
clair. L'app n'est pas en bac à sable (`com.apple.security.app-sandbox` à
`false`), donc aucun bookmark à portée de sécurité n'est nécessaire.

### Pannes prévues

| Cas | Traitement |
|---|---|
| Dossier disparu ou renommé | Message dans la section ; le réglage est conservé, pour qu'un volume non monté ne fasse pas perdre le chemin |
| Échec d'écriture | L'alerte existante « Échec de l'enregistrement » ; le tampon n'est pas vidé |
| Fichier iCloud non téléchargé | Un coffre synchronisé présente des marque-places `.2026-08-11.md.icloud` : `startDownloadingUbiquitousItem` est appelé, la note apparaît quand le fichier arrive |
| Fichier illisible (encodage) | La note est listée avec un extrait « contenu illisible » plutôt que d'être omise — une note invisible est une note perdue |

## 5. Découpage

`Cairn/Features/Journal/` :

| Fichier | Rôle |
|---|---|
| `JournalNote.swift` | la valeur, l'extraction des tags, l'extrait autour d'une correspondance |
| `JournalTag.swift` | le tag, ses parents imbriqués, le décompte trié |
| `JournalFolder.swift` | lire, écrire, supprimer — le seul fichier qui touche le disque |
| `JournalStore.swift` | l'état observable, la surveillance, l'enregistrement différé |
| `JournalListView.swift` | la liste et sa recherche |
| `JournalDetailView.swift` | l'en-tête, la note rendue et l'éditeur |

`Cairn/Features/Settings/JournalSettingsView.swift`.

Retouches : `SidebarView` (cas `.journal` + section Tags), `RootView` (routage
des deux colonnes, ⌘N, barre d'outils), `SettingsScene` (onglet), `VimCommand`
(`gj`), `KeyboardHelpSheet` (le tableau).

`xcodegen generate` après l'ajout des fichiers.

## 6. Tests

`Tests/Journal*Tests.swift`, Swift Testing, noms français, comme le reste de la
suite. La logique est presque toute en valeurs pures, donc en tests rapides :

- **Tags** : inline, frontmatter en ligne et à puces, imbriqués et leurs
  parents, exclusion d'un titre `# Titre`, exclusion de `#2026`.
- **Filtrage** : deux tags cochés se combinent en ET ; aucun tag coché ne filtre
  rien.
- **Recherche** : insensible à la casse et aux accents ; extrait centré sur la
  correspondance, y compris quand elle est en fin de note.
- **Décompte** : tri par fréquence puis par nom.
- **Règle du vide** : une note faite d'espaces et de retours à la ligne est
  considérée comme vide.
- **Corps rendu** : le frontmatter est enlevé du corps, un `---` en milieu de
  note y reste, un bloc jamais refermé ne perd que sa première ligne — et
  `MarkdownParser`, lui, ne touche à rien de tout cela.
- **`JournalFolder`**, sur un dossier temporaire : aller-retour lecture /
  écriture, nom de fichier produit pour une date, rejet de ce qui n'est pas une
  note du jour (`notes.md`, `2026-13-01.md`, un sous-dossier).

## Hors périmètre

Volontairement absents de cette première version, à rouvrir si le besoin se
fait sentir à l'usage :

- tout lien entre une note et les activités, repas ou pesées du même jour ;
- les liens `[[wikilink]]` et la navigation entre notes ;
- les notes autres que celles du jour ;
- les modèles (*templates*) de note.
