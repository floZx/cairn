-- Purge des activités que le Mac ne connaît plus.
--
-- Le 17 août 2026, `activity` contenait 1452 lignes pour 852 activités sur le
-- Mac : 600 orphelines, apparaissant en double dans l'application web. Aucune
-- activité du Mac ne manquait à Supabase — le miroir avait trop, jamais trop
-- peu.
--
-- Ce qui s'est passé, lisible dans les horodatages : la poussée de 7 h 25 a
-- envoyé les activités sous un premier jeu d'identifiants, puis
-- `StoreMaintenance` a réparé les identités du magasin — la réparation qui ne
-- touchait alors qu'`Activity` — et la poussée de 7 h 51 les a renvoyées sous
-- leurs nouveaux `uuid`. Supabase a gardé les deux jeux, n'ayant aucun moyen
-- de savoir que les premiers étaient morts. C'est aussi pourquoi aucune autre
-- table n'est touchée : elles n'ont jamais changé d'identifiant.
--
-- Le critère de sélection a été mesuré dans les deux sens avant d'être écrit :
--
--   * aucune des 852 activités du Mac n'est dépourvue à la fois de tours et de
--     trace détaillée — pas même les activités manuelles ;
--   * les 600 orphelines le sont toutes.
--
-- « Ni tour ni trace » désigne donc exactement ces 600 lignes. C'est ce qui
-- permet de les nommer sans coller ici une liste de 852 identifiants, qui
-- serait illisible et périmée demain.
--
-- À exécuter dans l'éditeur SQL de Supabase. Le `select` d'abord : il doit
-- rendre 600. Si un autre nombre apparaît, ne pas continuer — le magasin a
-- changé depuis, et il faut refaire la mesure.

select count(*) as a_supprimer
from activity a
where not exists (select 1 from lap l where l.activity_uuid = a.uuid)
  and not exists (select 1 from activity_streams s where s.activity_uuid = a.uuid);

-- Puis, seulement si le compte ci-dessus vaut 600 :

delete from activity a
where not exists (select 1 from lap l where l.activity_uuid = a.uuid)
  and not exists (select 1 from activity_streams s where s.activity_uuid = a.uuid);

-- Et le contrôle d'après : 852, le compte du Mac.
select count(*) as restant from activity;
