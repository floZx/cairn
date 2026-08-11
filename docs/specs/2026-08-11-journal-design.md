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

   Trois conséquences assumées : **le curseur ne suit pas le clic** — ce sont
   deux vues, et SwiftUI ne transporte pas la position du clic de l'une à
   l'autre ; **changer de note revient toujours en lecture**, arriver dans
   l'éditeur se demande ; une note illisible garde son écran d'indisponibilité
   et ne devient jamais éditable.

   **En entrant** dans l'éditeur, le curseur se pose **en fin de texte** —
   constaté au clavier le 11 août 2026. C'est ce que fait `TextEditor` quand
   `@FocusState` le désigne, et cela tombe bien : on ajoute à la suite d'un
   journal bien plus souvent qu'on ne reprend son milieu. Les contournements
   restent hors périmètre.

   *Ce que l'usage a tranché, en revanche* (11 août 2026). Tant que l'éditeur
   tenait son texte du store — `Binding(get: { text }, set: onEdit)` —, chaque
   frappe repassait par `update(_:for:)`, qui reconstruit `notes`, que la vue
   lit : le corps était réévalué et `TextEditor` recevait sa chaîne de
   l'extérieur. Un `TextEditor` dont la valeur liée est remplacée du dehors perd
   sa sélection : la lettre s'insérait bien là où était le curseur, puis le
   curseur sautait **à la fin de la note**. Corriger une phrase — l'essentiel de
   ce qu'on fait dans un journal — était impossible.

   **Tant que l'éditeur détient le texte, le texte est à lui.** Il le garde en
   état local, l'écrit vers le store à chaque frappe — l'extrait de la ligne,
   les tags, le décompte de la barre latérale et la réconciliation suivent donc
   toujours la frappe et non la temporisation — et ne le relit jamais en
   continu. Il le reprend à trois moments, et à ceux-là seulement : entrer dans
   l'éditeur, une autre note arrivant dans le volet, et `textRevision`, le
   compteur par lequel le store annonce qu'il a remplacé le texte lui-même
   (reprise d'une modification externe sur une note propre, ou **Recharger**).

   **La règle a une condition, et c'est elle qu'il faut tenir** : le store
   n'annonce le texte que d'une note qu'il *sait* ouverte. L'éditeur le prévient
   donc qu'il la prend (`beginEditing(_:)`) — sans quoi une modification arrivée
   du téléphone pendant qu'une note est ouverte sans avoir été touchée
   n'atteindrait plus l'écran, l'ancien montage la faisant passer par la
   relecture continue qu'on vient de supprimer. Et tout ce qui fait lâcher le
   tampon au store (`discardBuffer()` : **Recharger**, suppression, changement
   de dossier) lui fait aussi oublier la note, alors que le volet, lui, ne
   bouge pas : **Recharger** ne referme pas l'éditeur et ne déplace pas le
   curseur. Ces chemins-là rendent donc la note tout de suite, et l'éditeur se
   réannonce à chaque avancée de `textRevision` s'il est toujours dedans. Sans
   cela, la modification suivante arrivait dans la liste sans un mot pour
   l'éditeur, qui écrivait ensuite par-dessus, sans bandeau, un texte que
   personne n'avait vu.
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
  Le *fichier* seulement : la ligne, elle, reste dans la liste tant que la note
  est celle qu'on écrit. Tout sélectionner, effacer, puis réfléchir sept
  dixièmes de seconde à la phrase suivante est une pause au milieu de
  l'écriture, et c'est de cette ligne qu'est construit le volet où se trouve le
  curseur.
- **Le jour ouvert garde sa ligne**, même sans fichier derrière lui, tant que
  c'est celui qu'on écrit. La note du jour créée par ⌘N n'existe qu'en mémoire :
  sans cette règle, la première rafale d'événements du coffre — et un coffre
  iCloud en produit sans qu'on lui demande — reprenait la ligne, donc le volet,
  donc le curseur qui venait d'y être posé.
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

**Rien ne s'écrit tant que le bandeau est levé.** Il ne peut se lever que sur un
tampon non enregistré, c'est-à-dire alors qu'un enregistrement est déjà en
attente : sans cette règle, la temporisation de 0,7 s écrivait le tampon
par-dessus le fichier même dont le bandeau prévenait — et le laissait debout,
offrant un **Recharger** qui rechargeait désormais votre propre texte. La phrase
écrite sur le téléphone disparaissait sans que rien ne le dise. Un ⌘-Tab hors de
la fenêtre et un clic sur une autre note passaient par le même chemin.
`saveNow()` renonce donc tant que `conflict` n'est pas nil, et c'est **Garder**
qui écrit : c'est le bouton par lequel on répond à la question. Changer de note
vaut « Garder », de propos délibéré — partir, c'est conserver ce qu'on a tapé,
et non emporter une question sans réponse sur la note suivante.

Le prix est **dit dans le bandeau plutôt que réglé en douce** : tant que la
question est sans réponse, le texte n'est qu'en mémoire, et quitter Cairn le
laisse partir — le fichier reste tel que l'autre écriture l'a fait. Le persister
ailleurs demanderait un troisième endroit où vit une note, dans un coffre qui
est justement celui d'Obsidian, et pour un état qui dure le temps de lire deux
lignes. Une seconde ligne sous le bandeau l'annonce donc, comme la ligne d'échec
d'écriture annonce le sien.

Quitter n'est pas le seul chemin : **changer de dossier sous un bandeau coûte la
même chose** — `choose(_:)` purge le tampon après un `saveNow()` qui, justement,
ne fait rien tant que la question est ouverte. La ligne du bandeau ne nomme que
le fait de quitter, et c'est voulu : c'est le cas qu'on rencontre, désigner un
autre coffre en pleine réponse à un conflit n'arrive pas ; l'écrire ici suffit
et évite un bandeau à rallonge. Recharger, Garder, ou répondre avant de partir.

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

### Le dièse ne s'affiche pas

*Ajouté le 11 août 2026, à l'usage.* Ni dans la barre latérale, dont la section
s'intitule déjà « Tags », ni sur les pastilles, que leur capsule annonce déjà,
ni dans la note lue. C'est de la syntaxe : elle reste dans le fichier, qu'Obsidian
attend ainsi, et dans l'éditeur, où l'on écrit bien du Markdown.

La reconnaissance passe par `JournalTag.isAllowed` et `JournalTag.init?(name:)`,
et non par une seconde copie des règles : les tags dont le dièse tombe dans la
note sont exactement ceux que la barre latérale liste, et le resteront.

*Étendu le 11 août 2026 aux notes d'activité*, partout où elles se lisent — le
détail, l'aperçu de la fenêtre d'édition, et le rappel au-dessus d'une note du
jour. Les deux sortes de notes s'écrivent de la même main ; un `#Sam` nu à côté
d'un `Sam` sans dièse ne se justifiait par rien. L'option reste inactive par
défaut sur `MarkdownText`, parce qu'elle retire des caractères de ce qui
s'affiche, et que cela se demande plutôt que cela ne s'hérite.

*Et la couleur, essayée le même jour, a été retirée.* Le tag prenait la couleur
d'accent, celle des liens et des boutons : dans une note il se lisait comme
quelque chose qu'on peut cliquer, alors qu'il n'y a rien à cliquer là. Le dièse
retiré suffit ; il ne reste que du texte.

## 3. L'écran

`SidebarItem.journal`, entre `.statistics` et `.nutrition`, icône
`text.book.closed`, badge = nombre de notes.

**Barre latérale** *(ajouté le 11 août 2026)* — un `MiniCalendarView`, le même
que celui du journal alimentaire, au-dessus de la section Tags : il répond à la
question qu'on a en arrivant — « qu'est-ce que j'ai écrit le 6 ? » — là où les
tags répondent à celle qui vient ensuite. Une pastille marque les jours qui
portent une note.

Cliquer un jour l'ouvre. Un jour **sans note** en reçoit une, vide et en mémoire
seulement : rien n'est écrit tant qu'on n'a pas tapé, ce qui donne l'écriture
rétroactive sans laisser de fichier derrière si l'on se ravise — la règle de
`open(_:)`, dont `openToday()` n'est plus que le cas d'aujourd'hui.

Le passage par `selectJournalNote` est obligatoire, et l'ordre l'est aussi : la
sélection est demandée d'abord, le jour n'est ouvert dans le store *que si* elle
a bougé. Ouvrir en premier insérerait une ligne et confierait au store une note
sur laquelle la liste n'est jamais allée.

L'éditeur n'est délibérément pas focalisé. ⌘N veut dire « écrire aujourd'hui »
et pose le curseur ; cliquer un jour veut dire « montre-moi ce jour-là », et une
note qu'on voulait relire ne doit pas s'ouvrir avec un curseur dedans. Pour le
jour qu'on voulait écrire, l'invite du lecteur est déjà là.

### Le journal réunit deux sources

*Ajouté le 11 août 2026, sur demande.* La liste ne venait que des fichiers du
coffre, si bien qu'un jour dont on n'avait écrit que sur la sortie elle-même —
« jambes lourdes, vent de face » dans une note Strava — était dans le journal
sans être dans sa liste, et aucune recherche ne le trouvait.

`JournalDay` réunit les deux : la note du jour venue du coffre, et ce que
portent les sorties de ce jour-là.

- **Un jour sans fichier apparaît** si au moins une de ses sorties a écrit
  quelque chose. Un jour d'entraînement muet n'entre pas : ce n'est pas une
  entrée de journal.
- **La recherche lit les deux**, et l'extrait vient du texte qui a répondu.
- **Les tags des deux comptent** dans la barre latérale, et cocher un tag écrit
  dans une sortie ramène ce jour-là.
- **Le coffre reste la seule chose que Cairn écrit.** Une note d'activité est
  lue ici et se modifie là où elle vit. Écrire dans un jour qui n'existait que
  par une sortie crée le fichier — par `open(_:)`, donc rien sur le disque tant
  qu'on n'a pas tapé — et `x` y est refusé, faute de fichier à mettre à la
  corbeille.
- **Toute note listée par le store est gardée, vide ou non** : le jour qu'on est
  en train d'écrire y a une ligne vide exprès, et la faire tomber ici
  emporterait le volet et le curseur au milieu d'une phrase.

Le jour auquel une sortie appartient est le `DateKey` de son instant dans le
calendrier du Mac — la même règle que le filtre du rappel, pour que la liste
d'un jour et son rappel ne puissent pas être en désaccord sur ce qui lui
appartient. Les activités sont récupérées déjà restreintes à celles qui ont
écrit quelque chose : quarante-quatre sur huit cent quarante-sept ici, ce qui
rend la fusion assez peu coûteuse pour tenir dans `body`.

**Colonne centrale** — la liste, la plus récente en haut. Chaque ligne : la date
en toutes lettres (« mardi 11 août 2026 »), un extrait, les pastilles de tags.
Le champ `.searchable` cherche dans le texte entier, insensible à la casse et
aux accents. Recherche et tags cochés se cumulent : la liste montre les notes
qui satisfont les deux.

**Le curseur du clavier est en `@State`, pas relu dans la sélection**
*(corrigé le 11 août 2026, après mesure)*. Un `j` maintenu n'avançait que d'un
cran. Deux hypothèses ont été fausses avant qu'une trace temporaire ne tranche :
les répétitions **arrivaient** bien — quarante-cinq `phase=.repeat`, focus
intact. Le défaut était en aval.

Le gestionnaire de touches est une fermeture construite à la dernière
évaluation du corps, et SwiftUI ne réévalue pas le corps entre les répétitions
d'une touche maintenue. `selection` est un `Binding` dont le getter capture
cette même copie figée : chaque répétition relisait donc la position d'avant le
premier mouvement et réécrivait la même destination. Une `@State` est une
référence vers un stockage vivant — lue là, elle donne toujours la ligne que le
curseur a réellement atteinte. La liste d'activités porte la même paire
(`cursor`, `cursorSelection`) depuis toujours, pour cette raison.

**Les pastilles de tags ne prennent jamais le clavier** *(corrigé le 11 août
2026)*. Elles sont cliquables mais `focusable(false)` : un contrôle focalisable
dans une ligne de `List` prend le clavier dès que cette ligne est sélectionnée.
Un `j` maintenu déplaçait donc la sélection une fois, la pastille de la ligne
d'arrivée captait le focus, et toutes les répétitions suivantes lui parvenaient
— elle qui ne fait rien d'une touche. La touche semblait n'agir qu'une fois. La
liste d'activités n'a aucun contrôle dans ses lignes, ce qui explique qu'elle
n'ait jamais eu le problème.

**La liste suit le curseur** *(corrigé le 11 août 2026)*. Un `j` maintenu
promenait la sélection hors de l'écran : les lignes défilaient bien, mais sous
le bord de la fenêtre, si bien que la touche semblait n'avoir agi qu'une fois.
La liste emprunte donc le `TableScroller` de la liste d'activités, qui atteint
le `NSTableView` sous la `List` et le fait défiler après chaque mouvement,
`gg` et `G` compris. Le pont ne fixe pas les hauteurs de ligne ici — un jour
portant des tags est plus haut qu'un autre, et une hauteur épinglée sur la
première ligne rognerait les suivantes.

**En arrivant dans la section, la note la plus récente est sélectionnée**
*(ajouté le 11 août 2026)*. Pas seulement pour ne pas ouvrir sur un volet vide :
sans sélection, `e`, `n`, `⏎` et `x` n'ont rien sur quoi agir et ne font rien du
tout, ce qui se lit comme des raccourcis cassés plutôt que comme une absence de
sélection. Seulement à l'apparition de la vue, donc à l'entrée dans la section —
aucun `.id(…)` ne la reconstruit pour une recherche ou un tag, si bien qu'échap
peut vider la sélection sans que la passe suivante la remette. Et seulement
quand rien n'est choisi : écraser une sélection faite, ou effacée exprès, serait
pire que le volet vide.

Quand une recherche est active, **l'extrait montre le passage qui correspond**
plutôt que le début de la note : une liste de résultats qui n'affiche nulle part
ce qu'elle a trouvé oblige à ouvrir chaque note pour le savoir.

**Les activités du jour** *(ajouté le 11 août 2026)* — entre les pastilles de
tags et le bandeau d'alerte, sous un titre « Activité(s) du jour », la ou les
sorties faites ce jour-là : l'heure, le symbole du sport, le nom, la distance,
la durée, le dénivelé — et **la note de l'activité**, rendue.

L'heure vient en tête et seule : les lignes sont dans l'ordre où la journée
s'est déroulée, et c'est elle qui y place chacune. Elle est prise sur
`startLocalDate`, comme partout où l'application affiche une heure — celle qui
était à la pendule là où la sortie a eu lieu. Le filtrage du jour, lui, porte
sur `startDate`, ce que fait déjà `ActivityFilter` : deux conventions, mais les
deux existantes, et elles ne divergent qu'en voyage.

Cette note est le sujet du bloc, pas sa garniture : on tient un journal pour
avoir sous les yeux, en écrivant sa journée, les sensations notées le soir même
de la sortie. Les chiffres sont le rappel qui les remet en situation. Les tailles se lisent contre les 15 points de la note du
jour : **14 pour la note rappelée, 13 pour la ligne qui la nomme**. Le premier
essai était à 11 et 12, et le bloc passait pour des mentions légales plutôt que
pour une voix secondaire — un cran en dessous suffit à les classer, deux rendent
le bloc pénible. Une note faite de blancs compte pour vide : une carte qui s'ouvre
sur une ligne blanche dit moins qu'une carte qui ne s'ouvre pas.

**Seul l'en-tête est le bouton**, pas la carte entière : une note d'activité peut
faire un paragraphe, et une cible de clic de cette hauteur est une cible dans
laquelle le pointeur tombe plutôt qu'une qu'il vise. Cela laisse aussi la note
sélectionnable, ce que le contenu d'un bouton n'est pas. Un chiffre qui serait un mensonge est omis plutôt que tiré : une
natation n'a pas de dénivelé, une séance en salle pas de distance, et une
rangée de tirets ne dit rien qu'une absence ne dise mieux. Un jour sans sortie
n'affiche rien du tout — un titre annonçant une liste vide est pire que pas de
titre, et la plupart des jours n'ont pas de sortie.

Un clic ouvre l'activité dans « Mes activités ». La section change forcément
avec : le volet du journal *est* la note, donc une activité sélectionnée pendant
qu'il s'affiche n'allumerait rien. La sélection est posée **avant** le
changement de section, pour que la sélection d'ouverture de la liste trouve le
volet déjà pris et n'y touche pas.

`JournalDayActivities` porte sa propre `@Query` plutôt que de recevoir une liste
filtrée : le volet de la note se reconstruit à chaque frappe — le brouillon y
vit — et refiltrer toute la bibliothèque par caractère voudrait dire construire
un `DateKey` pour chacune des centaines d'activités afin de le jeter aussitôt.
Les bornes du jour passent par `DateKey.advanced(by:)` et non par 86 400
secondes, sans quoi un changement d'heure les décalerait d'une heure — un jour
fait 23 ou 25 heures deux fois par an.

**Volet de droite** — un en-tête (la date, les pastilles de tags) puis, sur
toute la hauteur restante, la note rendue par `MarkdownText`, le composant qui
sert déjà les notes d'activité, ou le `TextEditor` quand on écrit.

Le texte y est à **15 points**, deux au-dessus du corps système : la note a le
volet pour elle et se lit par minutes entières, là où celle d'une activité est
un champ parmi des chiffres et garde la taille du système. `MarkdownText` prend
donc une taille de base optionnelle — nulle, il ne change rien, ce qui laisse
les notes d'activité exactement où elles étaient — et en dérive ses titres,
sans quoi un titre de niveau 3 passerait *sous* le texte qu'il introduit. Les
deux modes partagent cette taille : ils s'échangent sous le pointeur, et un
texte qui grandirait au clic ferait de l'échange la chose qu'on remarque.

Toute la surface du volet prend le clic, pas seulement le texte : une note vide
n'offre rien à viser, et une invite discrète — « Cliquez pour écrire » — le dit,
faute de quoi un volet blanc qui se transforme en éditeur ne s'annonce nulle
part. **Une exception, voulue** : un lien `[texte](url)` rendu reste un lien et
s'ouvre dans le navigateur. Quelqu'un qui clique un lien veut le suivre, pas
écrire à côté ; pour éditer la ligne, on clique à côté du lien.

Le mode — lecture ou écriture, et sur quelle note — est un `JournalEditing`,
sorti de la vue et testé à part : changer de note et demander l'éditeur peuvent
arriver dans la même passe de mise à jour, dans un ordre que SwiftUI ne promet
pas, et une règle qui retient *quelle* note est éditée survit aux deux ordres là
où un booléen s'annulait lui-même. Le volet est également refait à neuf quand on
change de dossier : une autre note du même jour n'est pas la même note.

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
| clic dans le volet | passer en édition ; le curseur ne se pose pas à l'endroit cliqué mais en fin de texte |
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
| `JournalEditing.swift` | lecture ou écriture, et sur quelle note |
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
- **Mode lecture/écriture** (`JournalEditing`) : les deux ordres d'arrivée de
  ⌘N finissent tous deux dans l'éditeur, revenir sur une note qu'on éditait
  l'ouvre en lecture, échap termine.
- **Bandeau de conflit** : la temporisation n'écrit rien tant qu'il est levé ;
  **Garder** écrit le tampon et le retire ; le bandeau annonce ce que coûte une
  question laissée sans réponse.
- **Révision du texte** : taper ne la fait jamais avancer — c'est ce qui tient
  le curseur en place —, une reprise du disque sur note propre la fait avancer
  une fois, un conflit ne la fait pas avancer.
- **Ligne tenue** : une note vidée, comme la note du jour ouverte par ⌘N,
  gardent leur ligne à travers une relecture du dossier.
- **Purges** : l'échec d'écriture disparaît à l'adoption externe, au changement
  de dossier, à la suppression et au rechargement — nulle part ailleurs, et un
  drapeau qui reste bloque la section entière.
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
