# Des photos dans les notes du journal

**Date** : 2026-08-13
**Statut** : validé

## Objectif

Poser une photo dans une note du journal — une glissée-déposée, un collage, un
bouton — et la voir : dans le volet de lecture de Cairn, dans Obsidian, et dans
le carnet PDF.

Le coffre reste ce qu'il est : un dossier de fichiers Markdown qu'une autre
application peut lire et écrire. Une photo ajoutée par Cairn est un fichier
image à côté des notes et une ligne de plus dans le texte, rien de plus caché.

## Décisions structurantes (validées avec l'utilisateur)

1. **Trois gestes, un seul chemin** : glissée-déposée sur le volet, collage
   depuis le presse-papiers, bouton « Ajouter une photo… ». Les trois copient
   le fichier au même endroit et écrivent la même ligne.

2. **Un sous-dossier et un lien Markdown standard.** Le fichier va dans
   `pieces-jointes/` à côté des notes, et la note porte
   `![](pieces-jointes/2026-08-13-1.jpg)`. Obsidian l'affiche, et le lien reste
   valable hors d'Obsidian — dans le carnet PDF, notamment, qui n'a aucune
   raison d'apprendre une syntaxe propriétaire.

3. **La photo s'ajoute à la fin de la note**, jamais au curseur. L'éditeur de ce
   journal a déjà payé cher les tentatives de suivre une position d'insertion
   (voir la spec du 11 août), et une photo qui atterrit toujours au même endroit
   est une photo qu'on retrouve.

4. **Le carnet PDF les embarque**, comme il embarque déjà les photos d'une
   sortie : un carnet à relire qui perdrait les images du journal ne serait pas
   le carnet.

## Ce qui se passe quand on pose une photo

1. Le fichier est copié dans `<coffre>/pieces-jointes/`, créé au besoin.
2. Il est renommé `AAAA-MM-JJ-N.ext` — le jour de la note, puis le premier
   numéro libre. Le nom d'origine est perdu volontairement : il vient d'un
   appareil photo ou d'une capture d'écran, il ne dit rien, et deux fichiers
   « IMG_4032.jpg » finiraient par se croiser.
3. `![](pieces-jointes/AAAA-MM-JJ-N.ext)` est ajouté à la fin de la note, sur sa
   propre ligne, précédé d'une ligne vide si la note n'en finissait pas déjà par
   une.
4. Plusieurs fichiers d'un coup donnent plusieurs lignes, dans l'ordre où ils
   ont été lâchés.

**Formats acceptés** : JPEG, PNG, HEIC. Tout autre fichier est refusé avec un
message qui le nomme — un fichier ignoré en silence est un fichier qu'on croit
avoir ajouté.

**Un collage sans nom** : le presse-papiers ne porte pas toujours de fichier
mais des octets d'image. Ils sont écrits en PNG sous le même schéma de nom.

**Ce qui peut rater** : le coffre absent ou en lecture seule, un fichier
illisible, un disque plein. Chaque échec passe par la bannière d'erreur du
journal, celle qui sert déjà quand une note ne s'écrit pas.

## L'affichage dans Cairn

Le parseur gagne un bloc **image** : une ligne qui n'est que `![alt](chemin)`,
rien d'autre autour. Une image au milieu d'un paragraphe reste du texte — c'est
la même retenue que le reste de ce parseur, qui ne reconnaît que ce que
quelqu'un tape sans penser à Markdown.

Le volet de lecture affiche l'image, l'éditeur affiche le lien : c'est déjà la
règle du journal, où l'on lit rendu et l'on écrit brut.

**Le chemin se résout contre un dossier**, passé au rendu. Deux endroits
partagent ce rendu — le volet du journal, qui a un coffre, et les notes
d'activité, qui n'en ont pas. Sans dossier, une ligne image reste sa ligne de
texte : une note d'activité n'a pas de pièces jointes, et prétendre le contraire
afficherait un carré vide.

**Une image introuvable affiche son nom**, pas un cadre vide. Dans un coffre
synchronisé par iCloud, un fichier pas encore descendu n'est pas un fichier
perdu, et le distinguer d'une erreur n'est pas possible depuis ici.

**Taille** : l'image occupe la largeur du volet, hauteur libre, coins arrondis
de 6 — la mesure des photos d'activité, pour que les deux se ressemblent.

## Le carnet PDF

`MarkdownHTML` gagne le même bloc, et une table de correspondance : le chemin
écrit dans la note vers une image déjà encodée. Un chemin sans correspondance
rend son texte de remplacement, jamais une balise vide.

`JournalBookAssets`, qui fabrique déjà les cartes, les courbes et les photos
d'une sortie, fabrique aussi celles-ci : il lit les fichiers du coffre, les
ramène à la largeur d'une page et les encode comme les autres. Elles comptent
dans la progression au même titre.

Le carnet reste autonome : les images y sont embarquées, pas liées.

## L'architecture

| Pièce | Ce qu'elle gagne |
|---|---|
| `JournalFolder` | copier une pièce jointe, nommer sans collision, créer le dossier |
| `MarkdownBlock` / `MarkdownParser` | le bloc image, et lui seul |
| `MarkdownText` | le dossier de résolution, et le rendu d'une image |
| `JournalDetailView` | les trois gestes, et la ligne ajoutée au texte |
| `MarkdownHTML` | le bloc image, avec sa table de correspondance |
| `JournalBookAssets` | les images des notes, encodées comme les photos |
| `JournalBookHTML` | passe la table au rendu des notes |

La règle qui décide du nom d'un fichier et de la ligne à écrire est une
fonction pure, à part du disque et de la vue — c'est elle qui se teste.

## Tests

- Le nom proposé prend le premier numéro libre du jour : sans pièce jointe,
  `2026-08-13-1.jpg` ; avec les deux premiers pris, `2026-08-13-3.jpg`.
- L'extension est conservée, en minuscules.
- La ligne ajoutée à une note vide n'ouvre pas sur une ligne blanche ; ajoutée à
  une note qui finit sans saut de ligne, elle en pose un ; ajoutée à une note
  qui en a déjà un, elle n'en pose pas deux.
- Deux fichiers d'un coup donnent deux lignes, dans l'ordre.
- Le parseur reconnaît `![](x.jpg)` seul sur sa ligne, et laisse
  `voir ![](x.jpg) ici` en paragraphe.
- Le rendu HTML d'une image connue porte sa source encodée ; d'une image
  inconnue, son texte de remplacement et aucune balise `img`.

## Hors périmètre

- Supprimer une photo, ou nettoyer une pièce jointe dont plus aucune note ne
  parle. Retirer la ligne suffit à la faire disparaître de la lecture ; le
  fichier reste dans le coffre, où le Finder et Obsidian savent le traiter.
- Insérer au curseur, redimensionner, légender.
- Les liens `![[…]]` d'Obsidian : Cairn n'en écrit pas et n'en affiche pas.
