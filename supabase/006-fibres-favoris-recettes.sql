-- Les fibres sur les favoris et les ingrédients de recette.
--
-- La migration 005 ne les avait ajoutées qu'à `food_entry`, alors que le Mac
-- les porte aussi sur `FavoriteFood` et `RecipeItem` : un favori créé depuis
-- une entrée renseignée gardait ses fibres localement et les perdait en
-- chemin.
--
-- Et surtout, la version web les demandait déjà dans ses requêtes. Une colonne
-- absente fait échouer la requête **entière** : favoris, récents et recettes
-- disparaissaient d'un coup, et la feuille d'ajout affichait « Rien trouvé ».
-- Signalé le 19 août 2026.
--
-- Sans valeur par défaut, pour la même raison qu'en 005 : un aliment muet n'a
-- pas zéro gramme de fibres, il n'a rien annoncé.
alter table favorite_food add column if not exists fiber100 double precision;
alter table recipe_item  add column if not exists fiber100 double precision;
