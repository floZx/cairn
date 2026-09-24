-- La note privée de Strava, celle que seul son auteur voit.
--
-- Le Mac la lit dans la fiche détaillée de chaque sortie et la pousse ici avec
-- le reste de la ligne ; le navigateur peut la réécrire, comme la description.
-- Rien ne repart jamais vers Strava : Cairn ne fait que lire son API.
--
-- À appliquer **avant** de lancer un Mac qui la connaît : il l'envoie dans
-- chaque ligne d'`activity`, et une colonne inconnue ferait refuser le lot.
alter table activity add column if not exists private_note text;
