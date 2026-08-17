-- Les notes du journal rejoignent le miroir.
--
-- À exécuter une fois, dans l'éditeur SQL du projet, sur une base déjà
-- provisionnée par `schema.sql`. Le contenu est identique aux deux blocs
-- ajoutés à `schema.sql` : celui-ci sert aux projets existants, l'autre aux
-- projets neufs.
--
-- Les octets des images ne traversent pas la ligne : ils vont dans le bucket
-- `photos`, comme les photos de sorties, et la ligne n'en garde qu'un chemin.

create table journal_note (
  uuid          text primary key,
  user_id       uuid not null references auth.users on delete cascade,
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz,

  date_key_raw  text not null default '',
  text          text not null default '',
  tags_raw      text[] not null default '{}',
  note_updated_at timestamptz not null default now()
);

create trigger journal_note_touch before insert or update on journal_note
  for each row execute function touch_updated_at();
create index journal_note_sync on journal_note (user_id, updated_at);

alter table journal_note enable row level security;
create policy "propriétaire seul" on journal_note
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create table journal_attachment (
  uuid          text primary key,
  user_id       uuid not null references auth.users on delete cascade,
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz,

  file_name     text not null default '',
  added_at      timestamptz not null default now(),
  storage_path  text
);

create trigger journal_attachment_touch before insert or update on journal_attachment
  for each row execute function touch_updated_at();
create index journal_attachment_sync on journal_attachment (user_id, updated_at);

alter table journal_attachment enable row level security;
create policy "propriétaire seul" on journal_attachment
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
