-- Le jeton Strava du navigateur.
--
-- Le Mac garde le sien dans le trousseau et n'a besoin de rien d'autre : cette
-- table ne le concerne pas, et l'effacer ne lui ferait rien. Elle existe pour
-- que le téléphone puisse, lui aussi, demander à Strava les sorties du jour
-- quand le Mac est fermé.
--
-- Une ligne par personne, dont l'`user_id` est la clé primaire : c'est une
-- relation, pas une collection.
--
-- La politique RLS est la seule chose qui protège ce jeton : personne d'autre
-- que son propriétaire ne peut le lire, et les fonctions Cloudflare y accèdent
-- sous l'identité du navigateur — elles n'ont pas de clé de service.
create table if not exists strava_token (
  user_id       uuid primary key references auth.users on delete cascade,
  updated_at    timestamptz not null default now(),

  access_token  text not null,
  refresh_token text not null,
  -- L'instant d'expiration tel que Strava le rend : un temps Unix en secondes.
  expires_at    bigint not null default 0
);

create trigger strava_token_touch before insert or update on strava_token
  for each row execute function touch_updated_at();

alter table strava_token enable row level security;
create policy "propriétaire seul" on strava_token
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
