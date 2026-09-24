-- La note privée n'a plus de colonne à elle.
--
-- 011 l'avait ajoutée pour la montrer à part. En local, deux notes n'ont pas
-- de sens : rien n'y est partagé. Le Mac la verse désormais dans la note
-- (`activity_description`), après une ligne vide, et ne pousse plus cette
-- colonne ; le web ne la lit plus.
--
-- À appliquer **après** avoir relancé le Mac et rechargé le web : l'ancienne
-- version de l'un comme de l'autre la réclame encore.
alter table activity drop column if exists private_note;
