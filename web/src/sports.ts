/// Les libellés de sport, repris mot pour mot de `SportType.displayName` côté
/// Swift. Deux applications qui nomment le même sport différemment n'ont l'air
/// que d'une seule à moitié finie.
///
/// Les clés sont les valeurs brutes stockées dans `activity.sport_type_raw` —
/// pas les valeurs de Strava, que le Mac a déjà traduites à l'import.
const noms: Record<string, string> = {
  ride: "Vélo",
  mountainBikeRide: "VTT",
  gravelRide: "Gravel",
  eBikeRide: "Vélo électrique",
  run: "Course",
  trailRun: "Trail",
  walk: "Marche",
  hike: "Randonnée",
  swim: "Natation",
  nordicSki: "Ski de fond",
  alpineSki: "Ski alpin",
  rowing: "Aviron",
  workout: "Renforcement",
  other: "Autre",
}

export function nomDuSport(brut: string): string {
  // Une valeur inconnue s'affiche telle quelle plutôt que de devenir « Autre » :
  // si le Mac se met un jour à écrire un sport que le web ne connaît pas, le
  // voir à l'écran vaut mieux que de le voir disparaître dans un fourre-tout.
  return noms[brut] ?? brut
}
