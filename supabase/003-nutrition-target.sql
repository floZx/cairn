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
