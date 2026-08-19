-- Les fiches des personnes citées dans les notes.
--
-- La liste des gens ne se range pas ici : elle se déduit des textes, comme les
-- tags. Une citation est un fait sur la note, et une copie en base est une
-- copie qui se périme — effacer « @sam » de la dernière note où il figurait
-- doit le faire disparaître de la liste, sans qu'aucune ligne n'ait à être
-- supprimée.
--
-- Cette table ne porte donc qu'une chose : ce qu'on a écrit **sur** la
-- personne. Une ligne naît quand on écrit sa note, jamais quand on la cite.
create table if not exists person (
  uuid       text primary key,
  user_id    uuid not null references auth.users on delete cascade,
  updated_at timestamptz not null default now(),
  edited_at  timestamptz,
  deleted_at timestamptz,

  -- Le pseudo replié — sans casse ni accents. C'est lui qui identifie :
  -- « @Hélène » et « @helene » sont la même personne.
  key        text not null default '',
  -- Le pseudo tel qu'il a été écrit la première fois, pour l'affichage.
  name       text not null default '',
  note       text not null default ''
);

create trigger person_touch before insert or update on person
  for each row execute function touch_updated_at();
create index person_sync on person (user_id, updated_at);
-- Une personne par pseudo replié : c'est la clé que les deux écrans emploient
-- pour retrouver une fiche depuis une citation.
create unique index person_key on person (user_id, key);

alter table person enable row level security;
create policy "propriétaire seul" on person
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
