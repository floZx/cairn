-- Les meilleurs efforts de chaque sortie à pied, calculés par le Mac depuis
-- ses séries distance et temps, et recopiés ici pour que le web classe les
-- podiums sans télécharger les séries de toute la bibliothèque.
--
-- Des secondes, dans l'ordre de `EffortDistance` côté Mac : 400 m, 1/2 mile,
-- 1 km, 1 mile, 2 miles, 5 km, 10 km, 15 km, 10 miles, 20 km, semi-marathon,
-- 30 km, marathon. 0 pour une distance que la sortie ne couvre pas ; null
-- hors course et trail, sur tapis, ou sans séries. L'ordre ne fait que
-- s'allonger.

alter table activity
  add column if not exists best_efforts double precision[];
