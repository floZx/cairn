-- Les zones de fréquence cardiaque et de puissance de chaque sortie, telles
-- que Garmin les appliquait le jour même : la borne basse de chacune des cinq
-- zones (bpm, watts) et les secondes passées dedans, zone 1 d'abord. Les zones
-- changent au fil des mois ; relire une vieille sortie avec celles
-- d'aujourd'hui la lirait de travers, d'où la copie faite une fois.
--
-- `zones_checked_at` : quand Garmin a été interrogé, trouvé ou non.

alter table activity
  add column if not exists hr_zone_floors     double precision[],
  add column if not exists hr_zone_seconds    double precision[],
  add column if not exists power_zone_floors  double precision[],
  add column if not exists power_zone_seconds double precision[],
  add column if not exists zones_checked_at   timestamptz;
