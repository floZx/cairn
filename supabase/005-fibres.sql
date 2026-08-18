-- Les fibres, sur les aliments déjà enregistrés et sur les objectifs.
--
-- `fiber100` est volontairement sans valeur par défaut et sans `not null` :
-- Open Food Facts ne connaît les fibres que de cinq produits sur six, et un
-- aliment muet n'en contient pas zéro — il n'a rien dit. Un défaut à zéro
-- ferait passer une somme incomplète pour une somme exacte, et la jauge ne
-- pourrait plus avouer ce qu'elle ignore.
--
-- Les lignes déjà en base restent donc à `null`, ce qui est la vérité : elles
-- ont été écrites par une version qui ne lisait pas cette colonne.
alter table food_entry add column if not exists fiber100 double precision;

-- L'objectif, lui, a bien une valeur pour tout le monde : trente grammes, le
-- repère de l'ANSES pour un adulte. Il se change dans les réglages du Mac.
alter table nutrition_target
  add column if not exists fiber_g double precision not null default 30;
