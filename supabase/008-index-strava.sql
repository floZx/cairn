-- De quoi retrouver une sortie par son identifiant Strava.
--
-- Le téléphone importera bientôt des sorties que le Mac n'a pas encore vues.
-- Pour qu'elles ne se dédoublent pas, chacun des deux demande à l'autre, avant
-- d'écrire : « as-tu déjà celle-ci ? » — et la seule clé que Strava et Cairn
-- partagent est `strava_id`.
--
-- Sans index, cette question coûte un parcours complet de la table à chaque
-- lot envoyé. Avec, elle est immédiate.
--
-- Un index et non une contrainte d'unicité : `strava_id` vaut 0 sur les
-- activités saisies à la main, et elles sont plusieurs.
create index if not exists activity_strava on activity (user_id, strava_id);

-- La même question pour ce qui a été écarté : le téléphone doit consulter
-- cette table avant d'importer, sans quoi il ressusciterait une sortie jetée
-- exprès.
create index if not exists discarded_activity_strava
  on discarded_activity (user_id, strava_id);
