# Journal — les notes de repas et de pesée y entrent aussi

**Date** : 2026-08-12
**Statut** : validé

## Objectif

Le journal lit déjà deux sources : les fichiers du coffre Obsidian, et la note
qu'une activité porte. Il en ignore deux autres, écrites dans la même
application et le même jour — la **note d'un repas** (`MealNote.note`, une par
jour et par repas) et le **commentaire d'une pesée** (`WeightEntry.note`, une
par jour).

Elles entrent à leur tour, sous la règle qui vaut déjà pour les activités :
**le journal les lit, il ne les écrit jamais.** Le coffre reste la seule chose
que Cairn écrit ; ces notes se modifient là où elles vivent, dans le journal
alimentaire.

## Décisions structurantes (validées avec l'utilisateur)

1. **Le texte seul fait exister un jour.** Une note de repas ou le commentaire
   d'une pesée fait apparaître le jour dans la liste, comme la note d'une
   sortie. Une pesée muette, non : on se pèse presque tous les jours, et la
   liste du journal deviendrait un calendrier où les vraies notes se noient.
   Même règle pour les aliments consignés — consigner n'est pas écrire.

2. **Une seule liste de textes écrits ailleurs.** `JournalDay` porte
   aujourd'hui `note` (le fichier) et `activityNotes: [String]`. Ajouter deux
   tableaux, ce serait propager quatre listes à travers `tags`, `summary`,
   `matches`, `excerpt` et `merge`. Pour la liste, la recherche et les tags,
   seule compte la **chaîne** : d'où vient le texte ne change rien à ce qu'on
   en fait. `activityNotes` devient donc `elsewhereNotes` — ce qui a été écrit
   ailleurs que dans le coffre, quelle qu'en soit la source.

   Conséquence gratuite : un `#Sam` dans une note de repas donne une puce dans
   la rangée et une ligne dans la barre latérale, sans une ligne de code de
   plus.

3. **Le volet garde un bloc par domaine.** Un frère de `JournalDayActivities`,
   même règle de silence : rien à dire, rien à l'écran. Les notes de repas y
   sont préfixées du repas, la pesée y porte son poids et son commentaire.

4. **Pas de total de kcal dans le volet.** Les chiffres d'une activité y sont
   parce qu'on écrit *sur* la sortie. Un total calorique en ferait un tableau
   de bord, et l'écran Alimentation est à un clic.

## Ce qui change

### `JournalDay`

`activityNotes: [String]` → `elsewhereNotes: [String]`. Le type ne bouge pas,
le sens s'élargit, et `summary`, `tags`, `matches`, `excerpt` et `merge` sont
inchangés au nom de la propriété près.

**L'ordre de la liste porte du sens** : c'est lui qui décide de la ligne
résumant un jour sans fichier. Les activités d'abord, dans l'ordre des sorties ;
puis les repas, dans l'ordre des repas de la journée (`MealSlot.sortOrder`) ;
la pesée en dernier — c'est le geste du matin, mais la phrase la moins
susceptible de raconter la journée.

### `RootView.journalDays`

La collecte gagne deux sources, groupées par `DateKey` comme les activités. Les
deux nouvelles sont plus simples que les sorties : `MealNote` et `WeightEntry`
portent déjà un `dateKeyRaw`, donc aucune conversion d'instant vers jour, et
aucune question de fuseau.

Les textes vides sont écartés à la source, comme `JournalDay.spoken` le fait
déjà : une note de repas ouverte puis refermée sans rien écrire ne doit pas
faire apparaître un jour.

### Le nouveau bloc du volet

Une vue `JournalDayNutrition`, sœur de `JournalDayActivities`, placée sous elle
dans `JournalDetailView`.

Sa requête filtre sur `dateKeyRaw == date.raw` — une égalité de chaîne, là où
les activités demandaient un intervalle d'instants et une gymnastique de
minuits locaux.

Contenu, silencieux si tout est vide :

- une ligne par note de repas, préfixée du nom du repas — « Déjeuner · Amie
  Sushi, pétage de bide… » — dans l'ordre des repas ;
- la pesée du jour, poids et commentaire — « 70,2 kg — jambes lourdes » — et
  **seulement si elle porte un commentaire**, par la même règle que la liste :
  le poids seul est un chiffre, pas une note, et le volet de droite d'Alimentation
  le dit déjà.

Les tailles de texte sont celles du bloc des activités (`noteSize` 14,
`headingSize` 13), lues contre la note à 15 : le rappel est secondaire et doit
en avoir l'air.

## Tests

- Une note de repas fait apparaître un jour qui n'a pas de fichier ; une pesée
  muette, non.
- Le `#Sam` d'une note de repas se retrouve dans `JournalDay.tags`.
- La recherche trouve un jour par le texte d'une note de repas, et l'extrait
  affiché est celui de ce texte.
- L'ordre : le résumé d'un jour sans fichier prend la note de la sortie quand
  il y en a une, celle du repas sinon.
- Le bloc du volet reste muet un jour sans note de repas ni commentaire de
  pesée.

## Hors périmètre

- Éditer une note de repas ou de pesée depuis le journal.
- Le total de kcal, les macros ou le poids dans la rangée de la liste.
- Faire de la pesée muette une entrée de journal, sous quelque forme que ce
  soit.
