-- Le profil Strava ne passe plus par le miroir.
--
-- Le Mac l'écrivait à chaque synchronisation, au prix d'une requête Strava, et
-- personne ne le lisait, ni sur le Mac ni sur le web. Le nom affiché dans les
-- réglages vient de la connexion elle-même.
--
-- À passer une fois le Mac mis à jour : une version plus ancienne pousserait
-- encore vers cette table, et échouerait.
drop table if exists athlete;
