-- Une personne par pseudo replié… parmi les fiches **vivantes**.
--
-- L'index unique comptait aussi les fiches supprimées, qui restent en table
-- avec leur `deleted_at` pour que la suppression se propage. Recréer la fiche
-- de quelqu'un après l'avoir vidée — en lui donnant des alias, ou une note —
-- produisait donc une seconde ligne pour la même clé, avec un autre `uuid`,
-- et Postgres la refusait : l'envoi du Mac restait bloqué sur ce doublon, et
-- l'écriture du web échouait pareil. Constaté le 29 septembre 2026 sur
-- Christèle, supprimée le 31 août.
drop index if exists person_key;
create unique index person_key on person (user_id, key) where deleted_at is null;
