-- Le chiffrement des notes du journal.
--
-- Les notes elles-mêmes ne changent pas de forme : leur texte chiffré va dans
-- la même colonne `text`, précédé de `cairn-chiffre:v1:`. Cette table ne garde
-- que de quoi refaire la clé à partir de la phrase secrète — le sel et le
-- nombre d'itérations — et un vérificateur qui reconnaît la bonne phrase.
-- Rien qui permette de lire une note.
--
-- Une ligne par compte, posée par le premier appareil qui chiffre ; jamais
-- remplacée, d'où l'absence de politique `update`.

create table journal_crypto (
  user_id     uuid primary key references auth.users on delete cascade,
  salt        text not null,
  iterations  integer not null,
  verifier    text not null,
  created_at  timestamptz not null default now()
);

alter table journal_crypto enable row level security;
create policy "propriétaire lit" on journal_crypto
  for select using (user_id = auth.uid());
create policy "propriétaire pose" on journal_crypto
  for insert with check (user_id = auth.uid());
