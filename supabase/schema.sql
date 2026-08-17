-- Miroir Supabase de la bibliothèque Cairn.
--
-- Un schéma plat, une table par `@Model` SwiftData, `uuid text primary key`.
-- Les relations passent par l'uuid du parent — `activity_uuid`,
-- `meal_slot_uuid`, etc. — et non par des clés étrangères Postgres
-- reconstruites : ça survit à l'ordre d'arrivée des lignes, qu'aucun
-- protocole de synchronisation ne garantit. Les énumérations restent des
-- chaînes brutes, comme `sport_type_raw` : les types énumérés Postgres sont
-- pénibles à faire évoluer et n'apporteraient rien.
--
-- Aucune contrainte d'unicité en dehors de la clé primaire, même là où le
-- modèle SwiftData en porte une (`Gear.stravaID`, `WeightEntry.dateKeyRaw`,
-- `NutritionDay.dateKeyRaw`) : l'unicité y est déjà assurée par le
-- fetch-or-create côté Mac, et une contrainte en plus ici n'apporterait
-- qu'un risque de rejet en cas de conflit de synchronisation.

-- Toute table du miroir porte ces cinq colonnes. `updated_at` vient du serveur
-- et ne sert qu'au curseur de pull ; `edited_at` vient de l'appareil qui a fait
-- le geste et ne sert qu'à l'arbitrage. Les confondre casserait le hors-ligne.
create or replace function touch_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql set search_path = pg_catalog;

-- =============================================================================
-- Activités
-- =============================================================================

create table activity (
  uuid            text primary key,
  user_id         uuid not null references auth.users on delete cascade,
  updated_at      timestamptz not null default now(),
  edited_at       timestamptz,
  deleted_at      timestamptz,

  strava_id       bigint not null default 0,
  source_raw      text not null default 'strava',
  -- Seule colonne `...Raw` de ce schéma dont le suffixe disparaît (elle vient
  -- de `editedFieldsRaw`) : l'encodeur devra traiter ce nom à part des autres.
  edited_fields   text[] not null default '{}',
  field_edited_at jsonb not null default '{}',
  name            text not null default '',
  sport_type_raw  text not null default 'other',
  start_date      timestamptz not null,
  start_local_date timestamptz not null,
  timezone_identifier text,

  distance        double precision not null default 0,
  moving_time     integer not null default 0,
  elapsed_time    integer not null default 0,
  total_elevation_gain double precision not null default 0,
  average_speed   double precision not null default 0,
  max_speed       double precision not null default 0,
  average_heartrate double precision,
  max_heartrate   double precision,
  average_watts   double precision,
  weighted_average_watts double precision,
  kilojoules      double precision,
  average_cadence double precision,
  calories        double precision,

  is_favorite     boolean not null default false,
  is_commute      boolean not null default false,
  is_trainer      boolean not null default false,
  is_manual       boolean not null default false,
  is_private      boolean not null default false,
  workout_type    integer,
  workout_label_raw text,

  kudos_count     integer not null default 0,
  achievement_count integer not null default 0,
  pr_count        integer not null default 0,
  athlete_count   integer not null default 1,

  start_latitude  double precision,
  start_longitude double precision,
  end_latitude    double precision,
  end_longitude   double precision,

  min_lat         double precision not null default -90,
  max_lat         double precision not null default 90,
  min_lon         double precision not null default -180,
  max_lon         double precision not null default 180,
  has_track       boolean not null default false,

  -- La trace simplifiée reste dans la ligne : quelques kilo-octets, et c'est ce
  -- qui permettra à la carte globale du web de s'afficher en une requête.
  simplified_track bytea,
  summary_polyline text,
  activity_description text,
  device_name     text,
  detail_fetched_at timestamptz,
  photos_fetched_at timestamptz,
  photo_count     integer,
  -- Seule relation de ce schéma qui ne passe pas par l'uuid du parent : le
  -- résumé Strava donne l'identifiant du matériel bien avant que le matériel
  -- lui-même ne soit récupéré, donc `gear_id` pointe vers `gear.strava_id`,
  -- pas vers `gear.uuid`.
  gear_id         text
);

create trigger activity_touch before insert or update on activity
  for each row execute function touch_updated_at();

-- Le curseur de pull lit dans cet ordre ; sans index, il fera un balayage
-- complet à chaque passage.
create index activity_sync on activity (user_id, updated_at);
create index activity_start on activity (user_id, start_date);

-- `ActivityStreams` : un flux détaillé par activité, en relation un-à-un
-- portée par l'enfant (`activity_uuid`), comme toute relation de ce schéma.
--
-- Les onze propriétés `Data?` du modèle (latlng, distance, altitude, time,
-- heartrate, cadence, watts, velocitySmooth, temp, grade, moving) ne
-- deviennent pas onze colonnes : la spécification dit que ActivityStreams
-- « garde ses métadonnées en ligne et un chemin de Storage à la place du
-- contenu » — un chemin, singulier. Elles sont donc regroupées dans un seul
-- objet du bucket `streams`, à l'image de la façon dont `TrackBlob` empaquette
-- déjà les coordonnées simplifiées dans la ligne `activity`. `point_count`
-- reste une colonne à part : c'est ce qui permet d'afficher la taille du flux
-- sans télécharger l'objet.
create table activity_streams (
  uuid          text primary key,
  user_id       uuid not null references auth.users on delete cascade,
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz,

  activity_uuid text,
  point_count   integer not null default 0,
  storage_path  text
);

create trigger activity_streams_touch before insert or update on activity_streams
  for each row execute function touch_updated_at();
create index activity_streams_sync on activity_streams (user_id, updated_at);

-- `ActivityPhoto`. Le modèle porte à la fois une relation `activity: Activity?`
-- et une propriété à plat `activityUUID: String` qui duplique la même
-- information pour la fraîcheur des requêtes côté Mac (voir le commentaire du
-- modèle) : côté Postgres il n'existe qu'une seule représentation d'un lien,
-- donc les deux convergent vers une unique colonne `activity_uuid`, non nulle
-- comme l'est `activityUUID`.
create table activity_photo (
  uuid          text primary key,
  user_id       uuid not null references auth.users on delete cascade,
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz,

  activity_uuid text not null default '',
  unique_id     text not null default '',
  source_url    text,
  caption       text,
  taken_at      timestamptz,
  sort_index    integer not null default 0,
  storage_path  text
);

create trigger activity_photo_touch before insert or update on activity_photo
  for each row execute function touch_updated_at();
create index activity_photo_sync on activity_photo (user_id, updated_at);

create table lap (
  uuid              text primary key,
  user_id           uuid not null references auth.users on delete cascade,
  updated_at        timestamptz not null default now(),
  edited_at         timestamptz,
  deleted_at        timestamptz,

  activity_uuid     text,
  strava_id         bigint not null default 0,
  lap_index         bigint not null default 0,
  name              text not null default '',
  distance          double precision not null default 0,
  moving_time       bigint not null default 0,
  elapsed_time      bigint not null default 0,
  total_elevation_gain double precision not null default 0,
  average_speed     double precision not null default 0,
  max_speed         double precision not null default 0,
  average_heartrate double precision,
  average_cadence   double precision,
  start_index       bigint not null default 0,
  end_index         bigint not null default 0
);

create trigger lap_touch before insert or update on lap
  for each row execute function touch_updated_at();
create index lap_sync on lap (user_id, updated_at);

create table gear (
  uuid           text primary key,
  user_id        uuid not null references auth.users on delete cascade,
  updated_at     timestamptz not null default now(),
  edited_at      timestamptz,
  deleted_at     timestamptz,

  strava_id      text not null default '',
  name           text not null default '',
  brand_name     text,
  model_name     text,
  is_bike        boolean not null default true,
  total_distance double precision not null default 0
);

create trigger gear_touch before insert or update on gear
  for each row execute function touch_updated_at();
create index gear_sync on gear (user_id, updated_at);

-- `Athlete.updatedAt` est un `Date` non optionnel venu de Strava — le moment
-- où le profil a été rafraîchi là-bas — sans rapport avec la colonne standard
-- `updated_at` de ce miroir, qui appartient au serveur Postgres et sert au
-- curseur de pull. Les deux ne peuvent pas porter le même nom : la propriété
-- du modèle devient `profile_updated_at`.
create table athlete (
  uuid               text primary key,
  user_id            uuid not null references auth.users on delete cascade,
  updated_at         timestamptz not null default now(),
  edited_at          timestamptz,
  deleted_at         timestamptz,

  strava_id          bigint not null default 0,
  first_name         text not null default '',
  last_name          text not null default '',
  city               text,
  country            text,
  profile_image_url  text,
  weight             double precision,
  profile_updated_at timestamptz not null
);

create trigger athlete_touch before insert or update on athlete
  for each row execute function touch_updated_at();
create index athlete_sync on athlete (user_id, updated_at);

create table discarded_activity (
  uuid          text primary key,
  user_id       uuid not null references auth.users on delete cascade,
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz,

  strava_id     bigint not null default 0,
  name          text not null default '',
  discarded_at  timestamptz not null,
  start_date    timestamptz not null
);

create trigger discarded_activity_touch before insert or update on discarded_activity
  for each row execute function touch_updated_at();
create index discarded_activity_sync on discarded_activity (user_id, updated_at);

-- =============================================================================
-- Alimentation
-- =============================================================================

create table day_type (
  uuid        text primary key,
  user_id     uuid not null references auth.users on delete cascade,
  updated_at  timestamptz not null default now(),
  edited_at   timestamptz,
  deleted_at  timestamptz,

  name        text not null default '',
  kcal_target bigint not null default 0,
  sort_order  bigint not null default 0
);

create trigger day_type_touch before insert or update on day_type
  for each row execute function touch_updated_at();
create index day_type_sync on day_type (user_id, updated_at);

create table meal_slot (
  uuid        text primary key,
  user_id     uuid not null references auth.users on delete cascade,
  updated_at  timestamptz not null default now(),
  edited_at   timestamptz,
  deleted_at  timestamptz,

  name        text not null default '',
  sort_order  bigint not null default 0,
  target_pct  bigint not null default 0
);

create trigger meal_slot_touch before insert or update on meal_slot
  for each row execute function touch_updated_at();
create index meal_slot_sync on meal_slot (user_id, updated_at);

create table nutrition_day (
  uuid          text primary key,
  user_id       uuid not null references auth.users on delete cascade,
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz,

  date_key_raw  text not null default '',
  day_type_uuid text
);

create trigger nutrition_day_touch before insert or update on nutrition_day
  for each row execute function touch_updated_at();
create index nutrition_day_sync on nutrition_day (user_id, updated_at);

create table food_entry (
  uuid           text primary key,
  user_id        uuid not null references auth.users on delete cascade,
  updated_at     timestamptz not null default now(),
  edited_at      timestamptz,
  deleted_at     timestamptz,

  date_key_raw   text not null default '',
  meal_slot_uuid text,
  product_code   text,
  food_name      text not null default '',
  kcal100        double precision not null default 0,
  protein100     double precision not null default 0,
  carbs100       double precision not null default 0,
  fat100         double precision not null default 0,
  grams          double precision not null default 0,
  sort_order     bigint not null default 0
);

create trigger food_entry_touch before insert or update on food_entry
  for each row execute function touch_updated_at();
create index food_entry_sync on food_entry (user_id, updated_at);

create table meal_note (
  uuid           text primary key,
  user_id        uuid not null references auth.users on delete cascade,
  updated_at     timestamptz not null default now(),
  edited_at      timestamptz,
  deleted_at     timestamptz,

  date_key_raw   text not null default '',
  meal_slot_uuid text,
  note           text not null default ''
);

create trigger meal_note_touch before insert or update on meal_note
  for each row execute function touch_updated_at();
create index meal_note_sync on meal_note (user_id, updated_at);

create table recipe (
  uuid           text primary key,
  user_id        uuid not null references auth.users on delete cascade,
  updated_at     timestamptz not null default now(),
  edited_at      timestamptz,
  deleted_at     timestamptz,

  name           text not null default '',
  meal_slot_uuid text
);

create trigger recipe_touch before insert or update on recipe
  for each row execute function touch_updated_at();
create index recipe_sync on recipe (user_id, updated_at);

-- `RecipeItem` est déclaré dans `Cairn/Model/Recipe.swift`, mais devient sa
-- propre table : SwiftData en fait un `@Model` distinct, relié par
-- `recipe_uuid` comme toute relation à-un de ce schéma.
create table recipe_item (
  uuid         text primary key,
  user_id      uuid not null references auth.users on delete cascade,
  updated_at   timestamptz not null default now(),
  edited_at    timestamptz,
  deleted_at   timestamptz,

  recipe_uuid  text,
  food_name    text not null default '',
  product_code text,
  kcal100      double precision not null default 0,
  protein100   double precision not null default 0,
  carbs100     double precision not null default 0,
  fat100       double precision not null default 0,
  grams        double precision not null default 0,
  sort_order   bigint not null default 0
);

create trigger recipe_item_touch before insert or update on recipe_item
  for each row execute function touch_updated_at();
create index recipe_item_sync on recipe_item (user_id, updated_at);

create table favorite_food (
  uuid         text primary key,
  user_id      uuid not null references auth.users on delete cascade,
  updated_at   timestamptz not null default now(),
  edited_at    timestamptz,
  deleted_at   timestamptz,

  food_name    text not null default '',
  product_code text,
  kcal100      double precision not null default 0,
  protein100   double precision not null default 0,
  carbs100     double precision not null default 0,
  fat100       double precision not null default 0,
  grams        double precision not null default 0
);

create trigger favorite_food_touch before insert or update on favorite_food
  for each row execute function touch_updated_at();
create index favorite_food_sync on favorite_food (user_id, updated_at);

-- =============================================================================
-- Poids
-- =============================================================================

-- Le gabarit du plan portait `day date` / `kilograms` : des noms qui n'ont
-- jamais existé dans le modèle Swift. `WeightEntry` réel porte
-- `dateKeyRaw: String`, `weightKg: Double`, `note: String?` — c'est lui qui
-- fait foi, pas le gabarit. `date_key_raw` reste `text`, comme sur les trois
-- autres tables clées par `DateKey` (`nutrition_day`, `food_entry`,
-- `meal_note`) : `DateKey.raw` est une chaîne validée, délibérément pas un
-- `Date`, pour éviter les pièges de fuseau horaire (voir `DateKey.swift`).
create table weight_entry (
  uuid          text primary key,
  user_id       uuid not null references auth.users on delete cascade,
  updated_at    timestamptz not null default now(),
  edited_at     timestamptz,
  deleted_at    timestamptz,
  date_key_raw  text not null default '',
  weight_kg     double precision not null default 0,
  note          text
);

create trigger weight_entry_touch before insert or update on weight_entry
  for each row execute function touch_updated_at();
create index weight_entry_sync on weight_entry (user_id, updated_at);

-- =============================================================================
-- Politique d'accès : chaque table n'est visible et modifiable que par son
-- propriétaire. La clé anon publiée dans le JavaScript du web n'a aucun autre
-- garde-fou — c'est RLS, et seulement RLS, qui protège les données.
-- =============================================================================

alter table activity enable row level security;
create policy "propriétaire seul" on activity
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table activity_streams enable row level security;
create policy "propriétaire seul" on activity_streams
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table activity_photo enable row level security;
create policy "propriétaire seul" on activity_photo
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table lap enable row level security;
create policy "propriétaire seul" on lap
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table gear enable row level security;
create policy "propriétaire seul" on gear
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table athlete enable row level security;
create policy "propriétaire seul" on athlete
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table discarded_activity enable row level security;
create policy "propriétaire seul" on discarded_activity
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table day_type enable row level security;
create policy "propriétaire seul" on day_type
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table meal_slot enable row level security;
create policy "propriétaire seul" on meal_slot
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table nutrition_day enable row level security;
create policy "propriétaire seul" on nutrition_day
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table food_entry enable row level security;
create policy "propriétaire seul" on food_entry
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table meal_note enable row level security;
create policy "propriétaire seul" on meal_note
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table recipe enable row level security;
create policy "propriétaire seul" on recipe
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table recipe_item enable row level security;
create policy "propriétaire seul" on recipe_item
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table favorite_food enable row level security;
create policy "propriétaire seul" on favorite_food
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter table weight_entry enable row level security;
create policy "propriétaire seul" on weight_entry
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- =============================================================================
-- Storage : les blobs d'`activity_streams` et `activity_photo`, en copie
-- seulement — l'original reste toujours le stockage externe local du Mac.
-- =============================================================================

insert into storage.buckets (id, name, public) values
  ('streams', 'streams', false),
  ('photos', 'photos', false);

create policy "propriétaire seul, streams" on storage.objects
  for all
  using (bucket_id = 'streams' and owner = auth.uid())
  with check (bucket_id = 'streams' and owner = auth.uid());

create policy "propriétaire seul, photos" on storage.objects
  for all
  using (bucket_id = 'photos' and owner = auth.uid())
  with check (bucket_id = 'photos' and owner = auth.uid());

-- =============================================================================
-- Journal
-- =============================================================================

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
-- Les objectifs de macros, pour l'application web.
--
-- Une seule ligne par personne, dont l'`uuid` est son propre identifiant : ce
-- ne sont pas des données à plusieurs exemplaires, et une clé fixe comme
-- « targets » se heurterait d'un compte à l'autre, la clé primaire étant
-- globale là où la politique RLS ne l'est pas.
--
-- À part du reste du miroir sur un point : rien ne l'alimente par l'outbox.
-- Ces trois nombres vivent dans les préférences du Mac, qu'aucune écriture
-- SwiftData ne touche, donc `MirrorEngine.push()` les réécrit à chaque
-- passage. Trois scalaires par synchronisation, c'est moins cher que de leur
-- inventer un modèle.
create table nutrition_target (
  uuid           text primary key,
  user_id        uuid not null references auth.users on delete cascade,
  updated_at     timestamptz not null default now(),
  edited_at      timestamptz,
  deleted_at     timestamptz,

  protein_g      double precision not null default 0,
  fat_g          double precision not null default 0,
  weight_goal_kg double precision not null default 0
);

create trigger nutrition_target_touch before insert or update on nutrition_target
  for each row execute function touch_updated_at();
create index nutrition_target_sync on nutrition_target (user_id, updated_at);

alter table nutrition_target enable row level security;
create policy "propriétaire seul" on nutrition_target
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
