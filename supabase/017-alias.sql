-- Les alias d'une personne : « Chris » et « Chérie » pour Christèle.
--
-- Tels qu'écrits, sur la fiche de la personne principale. Une mention
-- `@Chris` est ramenée à elle partout où l'on compte et où l'on ouvre, mais
-- le texte garde le mot écrit. Porter des alias suffit à faire exister la
-- fiche, note vide ou non.
--
-- À passer **avant** d'ouvrir un Mac ou un web à jour : ils envoient cette
-- colonne, et Postgres refuserait la ligne entière sans elle.
alter table person add column if not exists aliases text[] not null default '{}';
