# Les notes du journal rejoignent la base

**Date** : 2026-08-17
**Statut** : validé

Tranche 2 du chantier décrit dans `2026-08-16-cairn-web-design.md`.

## Objectif

Les notes du journal quittent le dossier Markdown pour la base SwiftData.
Purement local : aucun réseau, aucun front, rien du miroir Supabase.

## Pourquoi maintenant

Le dossier existait pour une raison précise, et l'en-tête de `JournalStore` la
dit encore :

> « The folder is the only source of truth — nothing is mirrored into SwiftData.
> A mirror would be a second copy that diverges the first time a note is written
> from Obsidian on the phone, which is precisely the compatibility this feature
> is for. »

Ce détour servait la saisie mobile. La PWA la reprendra en tranche 4, et le
détour n'a plus lieu d'être. Ce qui disparaît avec lui n'est pas un détail :
tout ce que le partage du dossier imposait s'en va aussi.

## Décisions structurantes (validées avec l'utilisateur)

1. **La reprise des notes existantes est automatique au premier lancement**, sur
   le patron de `StoreMaintenance` qui répare déjà les identités. Pas d'écran de
   confirmation, pas de comparaison côte à côte.

2. **Le dossier n'est jamais modifié ni supprimé.** Cairn le lit une fois et
   n'y écrit plus rien. Les fichiers restent où ils sont ; c'est ce qui rend la
   reprise automatique acceptable.

3. **Coupure nette : le dossier est lu une fois, puis oublié.** Aucun pont n'est
   maintenu vers Obsidian. Conséquence assumée et connue : **il n'y a plus de
   saisie mobile entre cette tranche et la tranche 4**, soit plusieurs mois.
   L'option d'une relecture du dossier à chaque lancement a été examinée et
   écartée — elle aurait fallu construire un pont pour le détruire ensuite.

4. **Le texte des notes ne change pas d'un caractère.** Les liens
   `![](pieces-jointes/2026-08-13-1.jpg)` restent tels quels : le nom de fichier
   daté est déjà unique, donc c'est lui la clé. Rien à réécrire, ni à la reprise
   ni à l'export.

5. **L'export Markdown est automatique, dans la sauvegarde**, et non un bouton.
   La promesse « vos notes ressortent en Markdown » ne vaut que si elles en
   ressortent sans qu'on y pense.

## Ce qui disparaît

C'est l'essentiel de la tranche, et c'est du retrait. Le journal compte
aujourd'hui 2 921 lignes ; la moitié n'existe que parce qu'un second écrivain
partage le dossier.

| Ce qui part | Pourquoi il n'a plus d'objet |
|---|---|
| `JournalReconciliation` et la bannière de conflit | plus de second écrivain, plus rien à réconcilier |
| Le surveillant FSEvents de `JournalStore` | plus rien à surveiller |
| `pendingWriteFailure`, `writeFailure`, et le refus de changer de note tant qu'une écriture a échoué | un `context.save()` ne rate pas comme un disque en lecture seule ou un dossier disparu |
| `JournalNote.isReadable` | un `String` en base est toujours décodable |
| `JournalFolder` (moitié écriture) et son signet à portée de sécurité | plus de dossier à autoriser ni à écrire |
| `JournalSettings.folderPathKey` | plus de dossier à désigner |

**`textRevision` survit, amaigri.** L'éditeur a toujours besoin qu'on lui dise
quand la copie du magasin doit l'emporter sur la sienne — au chargement d'une
autre note, à une suppression — mais plus jamais parce que le fichier a changé
sous ses doigts. La raison la plus subtile de son existence s'en va ; le
compteur reste.

**Ce qui ne bouge pas :** `JournalDetailView`, `JournalListView`, `JournalDay`,
`JournalDayActivities`, `JournalDayNutrition`, `JournalDaySources`,
`JournalTag`, `JournalNotice`, et le carnet PDF. Ils reçoivent du texte et des
étiquettes, et continueront d'en recevoir.

## Le modèle

`JournalNote` **devient** le `@Model`, plutôt que d'ajouter une couche de
correspondance sous une structure conservée :

```swift
@Model final class JournalNote {
    var uuid: String = UUID().uuidString
    var dateKeyRaw: String = ""
    var text: String = ""
    var tagsRaw: [String] = []
    var updatedAt: Date = Date.distantPast
}
```

`tags` est aujourd'hui dérivée à la construction, ce qu'un `@Model` ne permet
pas. Elle devient une colonne, tenue à jour à chaque écriture — et devient au
passage filtrable par la barre latérale sans avoir à scanner tous les textes.

Les propriétés calculées qui ne dépendent que du texte — `isEmpty`, le corps
sans son avant-propos YAML — restent calculées.

**Les pièces jointes prennent leur propre modèle**, avec leurs octets en
`@Attribute(.externalStorage)`, comme les photos de sorties. Le type actuel
`JournalAttachment` ne touche à aucun disque : il nomme les fichiers, compose le
lien Markdown et plafonne les images à 2 048 px. Il est renommé
`JournalAttachmentRules`, ce qui libère le bon nom pour le modèle au lieu d'en
inventer un tordu.

Le nom de fichier reste la clé : `AAAA-MM-JJ-N.ext`, produit par la règle
existante, porte la date et le premier numéro libre du jour, donc il est unique
globalement.

`AppModelContainer.schema` passe ainsi de dix-huit à **vingt** types. Deux
modèles nouveaux sont une migration légère, comme le commentaire du bloc
nutrition le note déjà. Ni l'un ni l'autre ne conforme `MirrorRow`, donc ni
`MirrorRecorder` ni le garde-fou `MirrorRowSchemaTests` n'en voient la couleur.

## La reprise

Elle vit dans `StoreMaintenance`, dont le rôle déclaré est déjà « tout ce qui
doit arriver une fois à un magasin existant ».

Elle a besoin du dossier, donc la moitié **lecture** de `JournalFolder`
lui est rattachée — nommage des fichiers, lecture d'un dossier de notes,
résolution du signet — tandis que la moitié écriture part immédiatement. Cette
moitié lecture **reste dans le code de façon permanente**, et non « le temps de
la reprise » : une installation neuve, ou un magasin restauré depuis une
sauvegarde ancienne, aura encore un premier lancement à faire. Elle devient le
seul endroit du projet qui sait lire un dossier de notes, et son unique
appelant est la reprise.

Ce qu'elle fait : résoudre le signet, lire les `.md`, lire `pieces-jointes/` en
entier, écrire en base, poser un marqueur. Puis plus personne ne lit le dossier.

**Toutes les images de `pieces-jointes/` sont reprises**, y compris celles
qu'aucune note ne cite. Une image orpheline ne coûte rien ; une image manquante
casse une note.

**Trois cas qui ne sont pas des détails :**

- **Dossier introuvable** — disque débranché, iCloud pas encore descendu. La
  reprise ne se marque **pas** faite et réessaie au lancement suivant. Marquer
  faite une reprise qui n'a rien lu perdrait tout.
- **Aucun dossier n'a jamais été désigné** — marqueur posé immédiatement, rien
  à faire.
- **Un fichier illisible** — repris quand même, ses octets conservés tels quels
  plutôt que perdus. La reprise se marque faite et signale la liste par
  `JournalNotice`, qui existe déjà. Boucler indéfiniment sur un fichier abîmé
  serait pire que le reprendre imparfait.

Le marqueur est **explicite**, jamais déduit de « la base est vide » : un
journal sans note est un état légitime.

La reprise est **idempotente** : relancée, elle ne duplique rien.

## L'export Markdown

Dans `BackupService`, à côté du `journal-AAAA-MM-JJ-HHMM.sqlite.gz` qu'il écrit
déjà : un dossier `journal-markdown-AAAA-MM-JJ-HHMM/`, un fichier
`AAAA-MM-JJ.md` par note, et son `pieces-jointes/`. Même politique de
conservation que les sauvegardes SQLite.

Le dossier produit est **identique en structure** à celui d'aujourd'hui.
Obsidian l'ouvre sans rien savoir de ce qui s'est passé entre-temps.

## Ce que ça ne touche pas

Aucun réseau, aucun front. `JournalNote` **ne conforme pas** `MirrorRow` dans
cette tranche, et aucune table `journal_note` n'est ajoutée au schéma Supabase.
C'est la tranche 3 qui l'ajoutera, quand la PWA aura besoin de lire les notes —
un `create table` de plus sur un projet déjà en service, donc additif.

## Vérification

Trois choses à prouver, dans cet ordre d'importance :

1. **L'aller-retour ne perd rien.** Partir d'un dossier, le reprendre,
   l'exporter, et comparer. « Équivalent » veut dire précisément : les mêmes
   noms de fichiers `.md`, chacun portant un texte **identique au caractère
   près**, et un `pieces-jointes/` contenant les mêmes noms avec des octets
   **identiques**. Ni reformatage, ni réencodage, ni réécriture de lien. C'est
   ce test qui porte toute la garantie de la tranche, et c'est celui à écrire
   en premier.

2. **La reprise se comporte bien dans ses trois cas** : idempotence, dossier
   absent qui ne marque pas, fichier illisible qui n'empêche pas les autres.

3. **Le journal fonctionne exactement comme avant, sans dossier.** C'est le
   critère de réussite de la tranche entière, et il se vérifie sur la suite
   complète : les tests qui ne savent pas d'où vient le texte doivent rester
   verts sans être touchés.

## Les tests

Des dix-sept fichiers actuels :

**Disparaît entièrement** — `JournalReconciliationTests`.

**Réduit à sa moitié lecture** — `JournalFolderTests` : ce qui portait sur
l'écriture et la suppression de fichiers s'en va, ce qui portait sur le nommage
et la lecture d'un dossier reste, puisque c'est ce dont la reprise dépend.

**Réécrit sur SwiftData** — `JournalStoreTests` (623 lignes de magasin
deviennent nettement moins). Ce qui portait sur le surveillant, les échecs
d'écriture et les fichiers illisibles disparaît avec eux.

**Renommé, sans changer de contenu** — `JournalAttachmentTests` devient
`JournalAttachmentRulesTests`, en suivant le type qu'il teste. Ses assertions ne
bougent pas : nommage, lien Markdown et plafond de 2 048 px sont exactement ce
qui reste vrai.

**Restent intacts, parce qu'ils ignorent d'où vient le texte** —
`JournalTagTests`, `JournalDayTests`, `JournalEditingTests`,
`JournalNoticeTests`, les cinq `JournalBook*Tests`, `JournalDaySourcesTests`,
`JournalDayNutritionTests`, `JournalDayActivitiesTests`,
`NutritionJournalTests`. Quatorze fichiers sur dix-sept : c'est la mesure de ce
que le changement de couche ne touche pas.

**Deux nouveaux** — `JournalImportTests` et `JournalMarkdownExportTests`.

Aucun test ne doit toucher au vrai dossier de l'utilisateur ni à ses
préférences réelles, pour la raison que le README expose déjà à propos du
magasin : un bundle de test macOS s'exécute dans l'application hôte.

## Le README

Trois passages à corriger :

- **« Emplacement des données »**, où les notes font aujourd'hui exception
  (« elles vivent dans le dossier que vous avez désigné, et nulle part
  ailleurs ; Cairn n'en garde aucune copie — ni ici, ni dans la sauvegarde »).
  L'exception disparaît, et avec elle une limite : les notes entrent enfin dans
  la sauvegarde.
- **« Journal »**, qui décrit le coffre et la compatibilité Obsidian.
- **« Sauvegarde »**, qui gagne l'export Markdown.
