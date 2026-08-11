# Alimentation & Poids — Cairn avale suivinut

**Date** : 2026-08-08
**Statut** : validé

## Objectif

Intégrer dans Cairn un équivalent complet et moderne de suivinut (la TUI Textual
de suivi nutritionnel, `/Users/florian/dev/suivinut`) : journal de repas, saisie
avec recherche dans le catalogue Open Food Facts hors ligne, recettes, favoris,
jours-types, et suivi du poids. Cairn devient le seul endroit du suivi ; la TUI
et l'app iOS suivinut deviennent obsolètes après un import unique des données.

Deux nouvelles entrées de sidebar sous « Statistiques » : **Alimentation** et
**Poids**.

## Décisions structurantes (validées avec l'utilisateur)

1. **Équivalent complet**, pas une simple consultation : saisie de repas,
   téléchargement/mise à jour du catalogue, recettes, favoris. Le modèle
   fonctionnel de référence est la TUI Textual, pas le port iOS.
2. **SwiftData natif, import unique** : les données vivent dans le store Cairn.
   `journal.db` (iCloud) n'est lu qu'une fois, par l'importeur. Pas de sync
   retour, pas d'architecture hybride.
3. **Catalogue via l'export CSV OFF, en Swift pur** : pas de dépendance Python
   ni DuckDB. Premier démarrage accéléré en copiant le `off.db` existant.

## 1. Navigation

- `SidebarItem` gagne `.nutrition` et `.weight`, affichés sous « Statistiques » :
  - `Label("Alimentation", systemImage: "fork.knife")`
  - `Label("Poids", systemImage: "scalemass")`
- Le `NavigationSplitView` unique à 3 colonnes est conservé (contrainte
  documentée dans `RootView.swift`). Routage dans la colonne *content* comme
  pour `.statistics` :
  - `.nutrition` → `NutritionDayView`
  - `.weight` → `WeightView`
- La colonne *détail* reprend le rôle du panneau latéral de suivinut quand la
  sélection est `.nutrition` : mini-calendrier + panneau de stats (voir §5).
  Pour `.weight`, la colonne détail reprend elle aussi ce panneau du journal
  (mini-calendrier + panneau de stats) — décidé en phase 6 pour supprimer le
  panneau d'activité résiduel qui y restait affiché.

  *Révision du 11 août 2026.* Le mini-calendrier a quitté ce panneau pour la
  **barre latérale**, où celui du journal de notes venait d'arriver. On navigue
  depuis le volet de gauche et on lit les résultats à droite ; avoir les deux
  calendriers de part et d'autre de la fenêtre selon la section ne se
  justifiait par rien. Le panneau garde ce pour quoi il existait : les chiffres
  que le jour choisi produit.
- Navigation vim (`VimCommand`) : `gn` → Alimentation, `gp` → Poids.

## 2. Modèle de données (SwiftData)

Nouveaux `@Model` dans le schéma existant (`ModelContainer+App.schema`),
fichiers sous `Cairn/Model/`. Reprise du principe central de suivinut : les
macros sont **dénormalisées au moment de la saisie** (valeurs /100 g copiées
dans l'entrée), l'historique reste juste même si le catalogue change.

| Modèle | Champs | Équivalent suivinut |
|---|---|---|
| `DayType` | `name`, `kcalTarget: Int`, `sortOrder: Int` | `day_types` |
| `MealSlot` | `name`, `sortOrder: Int`, `targetPct: Int` | `meal_slots` |
| `NutritionDay` | `dateKey: String` (unique), `dayType: DayType?` | `days` |
| `FoodEntry` | `dateKey`, `mealSlot: MealSlot`, `productCode: String?`, `foodName`, `kcal100`, `protein100`, `carbs100`, `fat100`, `grams`, `sortOrder` | `log_entries` |
| `MealNote` | `dateKey`, `mealSlot`, `note` | `meal_notes` |
| `Recipe` | `name`, `mealSlot: MealSlot?`, `items: [RecipeItem]` (cascade) | `recipes` |
| `RecipeItem` | `foodName`, `productCode?`, macros /100 g, `grams` | `recipe_items` |
| `FavoriteFood` | `foodName`, `productCode?`, macros /100 g, `grams` | `favorites` |
| `WeightEntry` | `dateKey: String` (unique), `weightKg: Double`, `note: String?` | `weights` |

- **`dateKey: String` au format `yyyy-MM-dd`**, comme suivinut : l'identité
  d'une journée de repas est un jour calendaire local, pas un instant. Évite
  les pièges DST/fuseaux d'un `Date` normalisé. Une propriété calculée fournit
  le `Date` local quand l'UI en a besoin (calendrier, graphes). Index sur
  `dateKey` pour `FoodEntry`.
- **Réglages simples en `@AppStorage`** (convention Cairn, `storageKey` porté
  par le type) : `proteinTargetG`, `fatTargetG`, `weightGoalKg`, période du
  graphe de poids.
- Semis par défaut si le store est vide et qu'aucun import n'est fait : mêmes
  valeurs que le `_seed()` de suivinut (repas standard, un jour-type).

## 3. Import unique depuis suivinut

`SuivinutImporter` (sous `Cairn/Features/Nutrition/`) :

- Lit `journal.db` via **libsqlite3 système** (aucune dépendance ; petit
  wrapper `SQLiteDatabase` réutilisé aussi par le catalogue, §4).
- Mappe toutes les tables : `day_types`, `meal_slots`, `days`, `log_entries`,
  `meal_notes`, `recipes` + `recipe_items`, `favorites`, `weights`, et les
  clés `settings` pertinentes (`protein_target_g`, `fat_target_g`,
  `weight_goal_kg`) vers les `@AppStorage`.
- Idempotence simple : l'import est proposé uniquement si le store nutrition
  est vide (aucun `FoodEntry`). Pas de fusion incrémentale — c'est un import
  *unique*, conforme à la décision 2.
- Déclenchement : bouton dans Réglages → Nutrition (`NSOpenPanel` pré-rempli
  sur `~/Library/Mobile Documents/com~apple~CloudDocs/suivinut/journal.db`),
  et bannière de premier lancement dans Alimentation quand le store est vide.
- Dans la foulée, si un `off.db` suivinut est trouvé à côté du journal (ou
  dans `~/.local/share/suivinut/`), il est **copié** vers le catalogue Cairn :
  recherche utilisable immédiatement, sans télécharger 1 Go.

## 4. Catalogue Open Food Facts

Le catalogue reste un **SQLite FTS5 séparé**, hors SwiftData (180 k+ produits,
recherche plein-texte préfixée, diacritiques ignorés — le terrain de FTS5, pas
de SwiftData).

- Emplacement : `~/Library/Application Support/Cairn/off.db`. Schéma identique
  à `schema_off.sql` de suivinut (`products`, `products_fts` en
  `unicode61 remove_diacritics 2`, `catalog_meta`).
- `FoodCatalog` : ouverture lecture seule, `search(query:)` en requête FTS
  préfixée (portage de `db/catalog.py:search`), `productCount`, `importedAt`.
- `CatalogBuilder` : pipeline de construction natif —
  1. Téléchargement de l'export CSV officiel
     (`https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz`)
     avec **reprise validée** ETag/If-Range, portage du contrat de
     `data/download.py` (`.part` + `.part.etag`, 416 géré, taille vérifiée).
  2. Décompression gzip **en flux** et parsing ligne à ligne du TSV (les
     champs OFF sont débarrassés des tabulations, pas de quoting).
  3. Mêmes filtres que `FILTER_SQL` : `countries_tags` contient `en:france`,
     nom non vide, kcal et protéines présents, `completeness ≥ 0.5`, bornes de
     vraisemblance (kcal 0–900, macros 0–100 g/100 g).
  4. Écriture dans `off.db.tmp` (insertions par lots, FTS reconstruit à la
     fin), puis **bascule atomique** ; `catalog_meta` reçoit `imported_at` et
     `threshold`.
- UI : dans Réglages → Nutrition, statut (« N produits, importé le … »),
  bouton « Mettre à jour le catalogue » avec progression (téléchargement puis
  construction), annulable. Le fichier CSV téléchargé est conservé en cache
  pour reprise, supprimé après succès.

## 5. Écran Alimentation (`NutritionDayView`)

Colonne *content* :

- **Bandeau du jour** : `‹` / date (format long fr) / `›`, bouton
  « Aujourd'hui », puce du jour-type cliquable (menu de sélection).
- **Récap macros** : quatre indicateurs kcal / Protéines / Glucides / Lipides
  en « consommé / cible » avec jauge de progression. Composants dans l'esprit
  de `StatTile`, couleurs système uniquement, `monospacedDigit()`.
- **Repas** : une section par `MealSlot` (ordre `sortOrder`) avec :
  - en-tête : nom, total kcal du repas et **cible adaptative** (§7) ;
  - table des aliments : Aliment · g · kcal · P · G · L ; édition des grammes
    et du libellé, suppression, réordonnancement (boutons monter/descendre et
    drag), étoile favori sur chaque ligne ;
  - note de repas (affichée sous la table, éditable en popover) ;
  - bouton « Ajouter » ouvrant la sheet d'ajout.
- **Sheet d'ajout d'aliment** : champ de recherche FTS5 instantanée (résultats
  avec marque et macros), sélection → saisie des grammes ; onglets ou
  segments : Recherche / Favoris / Manuel (libellé + macros /100 g + grammes).
  Depuis l'en-tête de repas : « Charger une recette » (picker) et « Enregistrer
  ce repas comme recette ».
- **Gestion des recettes** : sheet dédiée (liste, composition, totaux,
  ajout/suppression d'items) accessible depuis l'écran Alimentation. Pas
  d'entrée sidebar propre — la sidebar reste courte.

Barre latérale (sélection `.nutrition`, depuis le 11 août 2026) :

- **Mini-calendrier** mensuel : jours avec repas marqués, clic = navigation,
  flèches mois précédent/suivant. Porté par `NutritionCalendarSection`, une vue
  à part : la barre latérale est à l'écran dans toutes les sections, et une
  `@Query` posée dessus irait chercher tous les repas jamais saisis pendant
  qu'on parcourt les activités.

Colonne *détail* (sélection `.nutrition`) :

- **Panneau stats** (portage de `tui/stats_panel.py`) : moyennes 7 j (kcal/j,
  protéines g/j), régularité du mois (« X/Y jours »), série de jours
  consécutifs, et rappel poids (actuel vs objectif).

Cas vide : `ContentUnavailableView` avec invite d'import suivinut ou de
création du premier repas.

**Raccourcis finaux du journal** (ajout post-spec, demande utilisateur :
parité clavier avec suivinut) :

| | |
|---|---|
| `j` `k` | ligne ou repas suivant / précédent |
| `a` | ajouter un aliment au repas sélectionné (pesée sur Poids) |
| `e` `⏎` | éditer l'aliment sélectionné |
| `x` | supprimer l'aliment sélectionné |
| `f` | étoile favori |
| `K` `J` | remonter / descendre l'aliment |
| `n` | note du repas sélectionné |
| `c` `s` | charger une recette / enregistrer le repas en recette |
| `t` | cycler le jour-type |
| `w` | nouvelle pesée |
| `←` `→` | jour précédent / suivant — échap : aujourd'hui |

## 6. Écran Poids (`WeightView`)

- **Graphe Swift Charts** : `LineMark` + `PointMark` des pesées, `RuleMark`
  pour l'objectif et pour le minimum de la période affichée ; fenêtres 30 j /
  90 j / 1 an / tout (picker persisté en `@AppStorage`).
- **Tuiles** : poids actuel, Δ 7 j, rythme kg/semaine (régression linéaire sur
  30 j), « ~N semaines → objectif » (masquée si le rythme ne converge pas).
- **Liste des pesées** : date, poids, note ; ajout (date par défaut
  aujourd'hui), édition, suppression. Une pesée par jour (`dateKey` unique),
  la saisie d'un jour existant remplace.

## 7. Logique métier pure (`NutritionMath`, `WeightStats`)

Types purs sans dépendance UI, sous `Cairn/Features/Nutrition/`, portés
fidèlement de `domain/nutrition.py` et `domain/stats.py` :

- `entryMacros` : macros d'une entrée = valeurs /100 g × grammes / 100.
- `dailyTargets` : kcal du jour-type, protéines et lipides globaux, **glucides
  déduits** `(kcal − 4·P − 9·L) / 4`.
- `adaptiveMealTargets` : chaque repas a un `targetPct` ; un repas terminé
  garde sa part consommée, le repas courant et les suivants se répartissent au
  prorata le budget réellement restant de la journée. Mêmes règles de bord que
  la version Python (pourcentages nuls, dépassements).
- `WeightStats` : Δ 7 j, régression linéaire kg/semaine sur 30 j, estimation
  du nombre de semaines jusqu'à l'objectif, minimum de période.

Dates injectables (`now: Date = Date()`), calendrier grégorien lundi-first,
comme `ActivityStatistics`.

## 8. Réglages

Nouvel onglet « Nutrition » dans la scène Settings existante :

- cibles protéines (g) et lipides (g), objectif de poids (kg) ;
- éditeur de **jours-types** (nom + kcal, ajout/suppression — le réordonnancement
  a été retiré : l'ordre n'a d'effet visible nulle part, les menus trient par
  kcal) ;
- **répartition % par repas** avec total affiché, coloré en vert si = 100 ;
- statut du catalogue + « Mettre à jour le catalogue » (progression) ;
- « Importer depuis suivinut… » (visible tant que le store nutrition est vide).

## 9. Gestion d'erreurs

- Import suivinut : base introuvable/corrompue → alerte explicite, rien n'est
  écrit (l'import est transactionnel : tout ou rien).
- Téléchargement catalogue : coupure réseau → `.part` conservé, message
  « Relancer pour reprendre » ; CSV inattendu (colonnes manquantes) → échec
  propre sans toucher au `off.db` courant (bascule atomique uniquement en fin).
- Catalogue absent : la recherche affiche une invite vers Réglages ; la saisie
  manuelle et les favoris restent utilisables.
- Recherche : `off.db` ouvert en lecture seule ; toute erreur SQLite dégrade
  en liste vide + message, jamais de crash.

## 10. Tests (Swift Testing, conventions Cairn)

- `NutritionMathTests` : mêmes cas que les tests Python de suivinut (cibles
  journalières, glucides déduits, cibles adaptatives — repas vides, % ≠ 100,
  dépassements).
- `WeightStatsTests` : régression sur données connues, Δ 7 j, estimation.
- `CatalogBuilderTests` : parsing/filtrage sur fixture TSV (lignes valides,
  hors France, kcal aberrantes, complétude insuffisante) ; construction d'un
  `off.db` en mémoire et recherche FTS dessus.
- `SuivinutImporterTests` : fixture `journal.db` minimale construite dans le
  test, vérification du mapping complet (y compris notes et réglages).
- `FoodCatalogTests` : recherche préfixée, diacritiques.

## 11. Phasage

1. **Modèles + import** : `@Model`, wrapper SQLite, `SuivinutImporter`,
   journal en lecture seule (bandeau, récap, repas) + entrées sidebar.
2. **Saisie complète** : sheet d'ajout (recherche via `off.db` copié, manuel,
   grammes), édition, suppression, réordonnancement, cibles adaptatives.
3. **Recettes, favoris, notes, jours-types** + onglet Réglages Nutrition.
4. **Poids** : écran complet, `WeightStats`, entrée sidebar.
5. **Pipeline catalogue** : téléchargement CSV avec reprise, construction,
   progression dans les Réglages.
6. **Clavier + finitions** : `gn`/`gp`, raccourcis de l'écran Alimentation
   dans l'esprit suivinut (`a` ajouter, `w` pesée…), états vides, polish.

## Hors périmètre v1

- Undo/redo spécifique (le Cmd+Z standard SwiftData pourra venir ensuite).
- Sync retour vers `journal.db` / cohabitation avec la TUI ou l'app iOS.
- Import incrémental ou fusion après le premier import.
- Code-barres, portions/`serving_size`, micro-nutriments.
