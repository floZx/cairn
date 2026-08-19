-- Le plan d'entraînement.
--
-- Il vivait dans un calendrier macOS, hors de portée du téléphone : un
-- événement d'EventKit ne traverse pas, et la version web n'y avait aucun
-- accès. Le porter dans le miroir lui donne les deux écrans.
--
-- Une ligne par séance et non par jour : une journée à double séance —
-- footing le matin, natation le midi — est le cas courant d'un plan.
--
-- Les trois objectifs chiffrés sont sans valeur par défaut, pour la raison
-- qui valait déjà pour les fibres : une séance sans distance visée n'en vise
-- pas zéro, elle n'en vise pas. Un zéro affiché mentirait sur l'intention.
create table if not exists planned_session (
  uuid              text primary key,
  user_id           uuid not null references auth.users on delete cascade,
  updated_at        timestamptz not null default now(),
  edited_at         timestamptz,
  deleted_at        timestamptz,

  date_key_raw      text not null default '',
  sport_type_raw    text not null default '',
  title             text not null default '',
  planned_distance  double precision,
  planned_duration  double precision,
  planned_elevation double precision,
  notes             text not null default '',
  -- Le type de journée nutrition que la séance appelle : planifier une sortie
  -- longue et le budget calorique qui va avec est le même geste.
  day_type_uuid     text,
  sort_order        bigint not null default 0
);

create trigger planned_session_touch before insert or update on planned_session
  for each row execute function touch_updated_at();
create index planned_session_sync on planned_session (user_id, updated_at);
-- L'écran d'entraînement lit un mois à la fois, jamais la table entière.
create index planned_session_date on planned_session (user_id, date_key_raw);

alter table planned_session enable row level security;
create policy "propriétaire seul" on planned_session
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
