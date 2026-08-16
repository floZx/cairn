# Cairn dans le navigateur

**Date** : 2026-08-16
**Statut** : validé

## Objectif

Consulter et alimenter son journal depuis un téléphone, sans rien retirer à
l'application macOS. Une application web installable (PWA) lit et écrit dans une
base Supabase ; l'application macOS synchronise la sienne avec cette base.

## La contrainte fondatrice

**L'application macOS reste autonome, définitivement, sans dépendance à aucune
société tierce.** Tout le reste de ce document en découle.

Cela veut dire, très concrètement : le Mac n'a jamais besoin du réseau ni de
Supabase pour démarrer, lire, écrire, chercher, exporter ou sauvegarder. La
synchronisation est une tâche de fond qui peut échouer indéfiniment sans autre
conséquence qu'un indicateur dans les réglages. Le jour où le projet Supabase
est fermé, on perd l'accès mobile et rien d'autre.

C'est une propriété vérifiable, pas une intention : la suite de tests doit
passer intégralement avec une URL Supabase pointée dans le vide.

## Décisions structurantes (validées avec l'utilisateur)

1. **SwiftData reste la vérité, Supabase est un miroir supprimable.** La
   synchronisation est bidirectionnelle, mais l'asymétrie est nette : la base
   locale est l'archive, la base distante est la copie de travail mobile.

2. **Supabase, notamment parce qu'il est auto-hébergeable.** Postgres,
   PostgREST, GoTrue et Storage sont libres. Le jour où l'offre ou les prix ne
   conviennent plus, la même pile se redéploie ailleurs et une URL change.
   CloudKit et Firebase n'offrent pas cette sortie — et l'API web de CloudKit
   est de toute façon une impasse.

3. **Le Mac fonctionne hors ligne intégralement ; la PWA exige le réseau.** Il y
   a donc deux écrivains, mais un seul peut diverger longtemps. La PWA garde un
   service worker pour sa coquille, pas pour ses données.

4. **La synchronisation Strava reste entièrement sur le Mac.** Le jeton, le
   quota de 200 requêtes par quart d'heure et la reprise d'import y sont déjà
   traités correctement. Conséquence assumée : quand le Mac dort, le miroir se
   fige et les sorties récentes n'apparaissent pas sur le téléphone. Rien dans
   le schéma ni dans le protocole n'interdit d'ajouter plus tard un
   synchroniseur côté serveur.

5. **Les notes du journal rentrent dans la base.** Le dossier Markdown existait
   pour permettre la saisie mobile via Obsidian ; la PWA rend ce détour inutile.
   Décision prise en connaissance de son coût, qui est le plus élevé du
   chantier : le journal est aujourd'hui une couche de fichiers autonome de
   2 921 lignes, hors SwiftData, avec dix-sept fichiers de tests. Elle a donc sa
   propre tranche. Voir « Ce que coûte le déplacement des notes ».

6. **Périmètre visé : tout Cairn dans le navigateur**, livré en tranches dont
   chacune est utilisable seule.

## Architecture

**Trois sources, un arbitre.** Strava, la saisie sur le Mac, la saisie sur le
web. L'arbitre existe déjà : `editedFields` a été écrit pour départager les deux
premières, en protégeant champ par champ ce que l'utilisateur a corrigé. Le web
s'y range comme troisième source.

**Le Mac écrit toujours en local d'abord.** Une file d'attente — l'*outbox* —
capture chaque changement pour le rejouer quand le réseau revient. L'interface
n'attend jamais rien.

**Le web écrit directement dans Postgres** via PostgREST, sous RLS.

**Répartition des données.** Postgres ne porte que du scalaire et les traces
simplifiées. Les traces détaillées et les photos vont dans Supabase Storage,
écrites une fois et jamais modifiées — donc structurellement hors de tout
conflit. C'est la transposition exacte du découpage déjà en place localement,
où la trace simplifiée est dupliquée dans `Activity` précisément pour que la
carte globale n'ait jamais à charger un stream complet.

## Le protocole de synchronisation

### Ce que chaque table gagne

- `uuid` — identité stable, indépendante de Strava. `Activity` et
  `ActivityPhoto` en ont déjà une ; douze modèles sur seize doivent la recevoir.
- `updated_at` — l'heure du **serveur**, posée par un trigger Postgres.
- `deleted_at` — suppression douce.
- `edited_at` — l'heure de **l'auteur** du changement.

Le Mac tient en plus, purement localement, un curseur de pull par table et
l'outbox. `SyncState`, qui décrit la relation du Mac avec Strava, reste local
lui aussi : il ne regarde pas Supabase.

### Deux horodatages, et pourquoi

C'est le point à ne pas rater.

`updated_at` ne sert **qu'au curseur de pull**. Il doit venir d'une horloge
unique pour être monotone et comparable, donc du serveur.

`edited_at` ne sert **qu'à l'arbitrage**. Il doit porter l'heure à laquelle
l'humain a fait le geste.

Les confondre casse le hors-ligne. Si le Mac pousse au retour du réseau une
correction faite il y a trois jours, un `updated_at = now()` la ferait gagner
contre une saisie faite sur le téléphone hier — l'inverse de ce qu'on veut. Le
curseur et l'arbitrage répondent à deux questions différentes et ont besoin de
deux horloges différentes.

### Le cycle

Déclenché au lancement, au retour du réseau, et périodiquement.

1. **Pull** — pour chaque table,
   `select * from t where updated_at > curseur order by updated_at`.
2. **Fusion** — ligne inconnue localement : création. Ligne connue sans entrée
   d'outbox : application directe. Ligne connue avec entrée d'outbox :
   arbitrage.
3. **Push** — rejeu de l'outbox en upsert.
4. **Curseur** — avancé à la plus grande `updated_at` reçue, **moins une minute
   de marge**.

Cette marge n'est pas de la prudence décorative : un curseur fondé sur un
horodatage peut sauter une ligne dont la transaction a été validée dans le
désordre par rapport à son `updated_at`. Reculer le curseur fait relire quelques
lignes déjà vues, ce qui est sans effet puisque l'application est idempotente —
et elle doit l'être de toute façon, un push interrompu pouvant être rejoué.

### Les règles d'arbitrage

**Nutrition, pesées, notes de repas, notes du journal, laps, photos, streams** —
dernier écrivain gagne, sur la ligne entière. Ces données sont en ajout quasi
exclusif ; deux appareils ne se disputent pas le petit-déjeuner de mardi.

**Activité** — champ par champ. Strava ne peut écraser aucun champ réclamé,
comme aujourd'hui. Entre le Mac et le web, le champ dont l'`edited_at` est le
plus récent gagne.

**Suppressions** — une suppression gagne toujours sur une édition. Sans cette
règle, une activité effacée sur le téléphone reviendrait à la synchronisation
suivante : précisément le défaut que `DiscardedActivity` existe pour empêcher
côté Strava.

### La migration SwiftData, additive et rien d'autre

L'arbitrage champ par champ demande une date par champ, alors qu'`editedAt` est
unique pour toute l'activité.

La tentation serait de changer `editedFieldsRaw` de `[String]` en
`[String: Date]`. C'est exactement le genre de modification qui transforme une
migration légère en base qui refuse de s'ouvrir, contre quoi `Activity` porte
déjà un avertissement en tête de fichier. On n'y touche pas.

`editedFieldsRaw` reste donc l'autorité sur « ce champ est-il réclamé », et une
**nouvelle** propriété `fieldEditedAt: [String: Date] = [:]` porte les dates,
avec repli sur `editedAt` quand elle est vide — ce qui sera le cas de toutes les
activités existantes, et c'est correct : leur date d'édition globale est la
meilleure information disponible.

Même règle pour les trois colonnes de synchronisation ajoutées aux seize
modèles : propriétés optionnelles ou à valeur par défaut, aucune contrainte
ajoutée, aucun type modifié.

## Le schéma Postgres

**Un schéma plat, une table par `@Model`, `uuid text primary key`.** Les
relations passent par l'uuid du parent — `activity_uuid` — et non par des clés
étrangères reconstruites. C'est déjà le choix fait localement sur
`ActivityPhoto`, et pour la même raison : ça survit à l'ordre d'arrivée des
lignes, qu'aucun protocole de synchronisation ne garantit.

Les énumérations restent des chaînes brutes, comme `sportTypeRaw`. Les types
énumérés Postgres sont pénibles à faire évoluer et n'apporteraient rien.

`user_id uuid references auth.users` sur chaque table, avec une politique RLS
unique et identique partout : `user_id = auth.uid()`. L'utilisateur est seul
aujourd'hui, mais sans cette politique l'API est ouverte à quiconque détient la
clé publique — qui est publique par construction, puisqu'elle est dans le
JavaScript de la page.

La trace simplifiée reste en `bytea` dans la ligne `activity` : 852 lignes de
quelques kilo-octets, et c'est ce qui permet à la carte globale du web de
s'afficher en une seule requête.

La table `activity` porte en outre `field_edited_at jsonb`, pendant exact de la
propriété `fieldEditedAt` côté Swift : la correspondance champ → date sur
laquelle repose l'arbitrage champ par champ. C'est la seule table qui en a une,
puisque c'est la seule dont la fusion n'est pas à la ligne entière.

`TrackBlob` traverse sans conversion. C'est du binaire sans en-tête, en
petit-boutiste : des paires de `Float64` pour les coordonnées, des `Float32`
pour les scalaires, des `Int32` pour les temps. Le décodeur TypeScript tient en
une dizaine de lignes autour de `DataView`.

## Les blobs

`activity_streams`, `activity_photo` et les images de notes gardent leurs
métadonnées en ligne et un chemin de Storage à la place du contenu. Le contenu
est écrit une fois et n'est jamais modifié.

Storage est toujours une **copie**, jamais l'original. Tout blob que le Mac
affiche existe d'abord dans son stockage externe local ; ce que Supabase en
détient sert à la PWA et à rien d'autre. C'est la règle qui rend la contrainte
fondatrice tenable jusque dans les octets.

Le Mac téléverse au fil de sa synchronisation Strava. Le web ne téléversera qu'à
partir de la tranche 6, sur import GPX.

Les photos restent des octets, jamais des liens : les URL de Strava sont signées
et expirent, et un journal de liens morts est exactement ce que cette
application existe pour éviter.

## Ce que coûte le déplacement des notes

Les notes du journal vivent aujourd'hui dans un dossier Markdown désigné par
l'utilisateur, et le README promet qu'aucune copie n'est gardée ailleurs. Elles
rejoignent la base : une table `journal_note`, une ligne par jour, le Markdown
en `text`.

Deux pertes, et leurs contreparties :

**L'édition via Obsidian disparaît.** C'était la raison d'être du dossier ; la
PWA la remplace.

**Les notes ne sont plus lisibles sans Cairn.** La contrepartie est un export
Markdown ajouté à la sauvegarde, qui reconstitue un dossier de notes lisible par
n'importe quoi. La promesse passe de « vos notes vivent dans un dossier à vous »
à « vos notes ressortent en Markdown quand vous voulez ».

**Les pièces jointes des notes suivent, et restent sur le disque.** La
spécification du 13 août range les images des notes dans
`<coffre>/pieces-jointes/` et écrit un lien Markdown relatif.

Sans coffre, elles se comportent exactement comme les photos d'activité : un
modèle SwiftData dont les octets sont en `@Attribute(.externalStorage)`, donc
dans `.Cairn_SUPPORT/` à côté d'elles, et Supabase Storage n'en reçoit qu'une
**copie**. Les faire vivre uniquement chez Supabase reviendrait à ce que le Mac
ait besoin du réseau pour afficher l'image d'une note, ce que la contrainte
fondatrice interdit. Le Mac ne lit que le local ; seule la PWA lit Storage.

L'actuel `JournalAttachment` reste ce qu'il est — un type de valeurs pures :
nommage, syntaxe du lien, plafond de 2 048 px. Le nouveau modèle porte donc un
autre nom.

**Le texte des notes ne change pas d'un caractère.** `fileName(for:extension:
taken:)` produit `AAAA-MM-JJ-N.ext`, où la date et le premier numéro libre du
jour font un identifiant unique : c'est une clé naturelle valable, et le lien
`![](pieces-jointes/2026-08-13-1.jpg)` se résout contre elle. Aucune réécriture
de lien, ni à la migration, ni à l'export — lequel se réduit à déverser les
octets dans un dossier `pieces-jointes/` et à écrire les notes telles quelles.
Le dossier exporté est alors identique à celui d'aujourd'hui, et Obsidian
l'ouvre sans rien savoir de ce qui s'est passé entre-temps.

Les fichiers déjà présents dans le coffre sont ingérés à la migration, en même
temps que les notes qui les citent.

Le carnet PDF, qui embarque déjà ces images, lit la nouvelle source locale.

### Ce que ça coûte en code

C'est le plus gros remaniement local du chantier, plus lourd que la couche de
synchronisation elle-même, et il faut le dire franchement : le journal ne passe
pas du tout par SwiftData aujourd'hui. `JournalNote` n'est pas un `@Model`, et
tout le sous-système est une couche de fichiers autonome — 2 921 lignes,
couvertes par dix-sept fichiers de tests.

Ce qui est à reprendre :

- `JournalStore` (623 lignes) passe des fichiers à SwiftData.
- `JournalFolder` (199 lignes) et son signet à portée de sécurité disparaissent,
  ainsi que `JournalReconciliation` — ou plutôt, ils se réincarnent dans l'export
  Markdown, qui a besoin d'écrire un dossier au même format.
- `JournalThumbnails` lit le stockage externe de SwiftData au lieu du coffre.
  `JournalAttachment`, qui ne touche à aucun disque, ne bouge pas.
- Les dix-sept fichiers de tests suivent le changement de couche.

Les vues, elles, ne bougent pas : `JournalDetailView` et `JournalListView`
reçoivent du texte et continueront d'en recevoir.

Rien dans les tranches 1 et 2 n'en dépend, d'où la tranche dédiée : ce travail
est purement local et se vérifie entièrement sur le Mac, sans réseau et sans
front. Son critère de réussite est simple à énoncer — **le journal fonctionne
exactement comme avant, sans dossier**.

## La pile web

Vite, React, TypeScript. `supabase-js` pour l'accès, TanStack Query pour le
cache de requêtes.

**MapLibre GL JS** pour les cartes : vectoriel, et il consomme directement les
fonds tiers déjà gérés par l'application.

**uPlot** pour les graphes. Sur des streams de plusieurs milliers de points,
les bibliothèques à base de SVG s'effondrent et uPlot non.

**`vite-plugin-pwa`** pour l'installabilité, avec un service worker limité à la
coquille de l'application, puisque l'écriture hors ligne n'est pas au programme.

Hébergement statique gratuit — Cloudflare Pages ou Netlify. Authentification par
lien magique.

**Open Food Facts est interrogé directement par son API.** Les 96 Mo de `off.db`
ne bougent pas : ce catalogue se retélécharge, il n'a aucune raison de traverser.

## Ce que la PWA ne fera pas

- **Parler à Strava.** Décision 4.
- **Exporter le carnet PDF.** Il n'a rien à faire dans un navigateur.
- **Fonctionner hors ligne au-delà de sa coquille.** Décision 3.

## Découpage en tranches

Chaque tranche est utilisable seule, et aucune ne construit une infrastructure
qu'une suivante jetterait. Chacune fera l'objet de son propre plan
d'implémentation : cette spécification décrit la cible, pas l'ordre des gestes.

**Tranche 1 — le socle, sans PWA.** Schéma, RLS, migration SwiftData des seize
modèles, amorçage, et push seul (Mac → Supabase). Vérifiable en regardant la
base, sans une ligne de front. Utile en soi : c'est une sauvegarde en ligne du
journal, en plus de l'iCloud.

**Tranche 2 — les notes rejoignent la base.** Purement locale : aucun réseau,
aucun front, aucune ligne de PWA. `JournalStore` bascule sur SwiftData, le
dossier et son signet disparaissent, l'export Markdown les remplace dans la
sauvegarde. Voir « Ce que ça coûte en code ». Isolée dans sa propre tranche
parce que c'est le remaniement le plus lourd et le seul qui puisse abîmer
quelque chose qui marche déjà bien.

**Tranche 3 — la PWA en lecture.** Liste, fiche d'activité, carte globale,
statistiques, journal. Aucun pull côté Mac, donc toujours aucune fusion à
écrire. C'est déjà l'essentiel de ce qui manque loin du Mac.

**Tranche 4 — la saisie mobile.** Alimentation, poids, notes du journal, favoris
et marqueurs. Le pull s'active sur le Mac, la fusion s'écrit — mais sur des
données en ajout quasi exclusif, terrain d'essai clément pour le protocole. Les
notes s'écrivent en texte seul : joindre une image depuis le navigateur est un
téléversement, et les téléversements web attendent la tranche 6.

**Tranche 5 — l'édition d'activité depuis le web.** Le bidirectionnel champ par
champ, avec `fieldEditedAt`. À faire une fois que la tranche 4 a éprouvé le
protocole.

**Tranche 6 — le reste.** Import GPX depuis le navigateur, export, parcours
similaires.

## L'amorçage

852 activités, 852 traces détaillées, 342 photos, 5 672 laps, 828 lignes
d'alimentation, 56 pesées. Environ 290 Mo, dont l'essentiel en blobs.

À lancer une fois, depuis les réglages, et **reprenable** : la mécanique de
`SyncProgress`, écrite pour un import Strava qui s'étale sur plusieurs sessions,
s'applique telle quelle. Parents d'abord (`gear`, `activity`), enfants ensuite.
Compter une demi-heure à une heure sur une connexion domestique, et prévoir que
ça se coupe — c'est le seul moment où le volume est un sujet.

## Volumes et coûts

| | volume | destination |
|---|---|---|
| Scalaires (activités, laps, alimentation, pesées, notes) | ~10 Mo | Postgres |
| Traces simplifiées | ~3 Mo | Postgres, `bytea` |
| Traces détaillées (852) | ~110 Mo | Storage |
| Photos (342) | ~178 Mo | Storage |
| `off.db` | 96 Mo | ne traverse pas |

Le palier gratuit de Supabase — 500 Mo de base, 1 Go de stockage — passe avec de
la marge, pour une croissance de l'ordre de 50 à 100 Mo par an.

Deux réserves. L'egress gratuit est de 5 Go par mois : recharger des photos en
boucle depuis le mobile peut l'entamer, et un cache HTTP correct suffit à
l'éviter. Un projet gratuit est mis en pause après sept jours sans requête, ce
qui est sans objet pour un usage quotidien mais mérite d'être su.

## Risques identifiés

**La divergence longue.** Un Mac éteint plusieurs semaines pendant que le
téléphone écrit produit un pull volumineux au réveil. Le protocole le gère —
c'est un pull ordinaire, simplement plus long — mais il doit être interruptible
et reprenable, comme l'amorçage.

**Les horloges désynchronisées.** L'arbitrage repose sur `edited_at`, donc sur
l'horloge de chaque appareil. Un Mac dont l'heure a dérivé arbitrerait mal. Le
risque est faible (les deux appareils sont synchronisés par NTP) et la
conséquence est bornée à un champ perdu, jamais une ligne.

**Le miroir figé.** Décision 4, assumée : le téléphone ne verra une sortie
Strava qu'après le prochain réveil du Mac.

## Vérification

Trois choses à prouver, dans cet ordre d'importance :

1. **L'autonomie du Mac.** La suite de tests passe intégralement avec une URL
   Supabase inexistante. C'est la traduction exécutable de la contrainte
   fondatrice, et elle doit être vérifiée en continu, pas une fois.

2. **L'idempotence.** Rejouer deux fois un pull ou un push donne le même état.
   Testable sans réseau, sur un client de synchronisation simulé.

3. **La fusion.** Des scénarios de divergence écrits à la main : même champ des
   deux côtés, suppression contre édition, création simultanée, champ réclamé
   contre proposition de Strava. Ce sont des tests de la couche de fusion, pas
   du réseau.
