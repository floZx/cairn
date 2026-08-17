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

/// Les sports dans l'ordre où le Mac les propose — celui de `SportType`, qui
/// n'est ni alphabétique ni celui d'usage : les vélos d'abord, puis la course
/// à pied, puis le reste.
export const SPORTS = Object.keys(noms)

export function nomDuSport(brut: string): string {
  // Une valeur inconnue s'affiche telle quelle plutôt que de devenir « Autre » :
  // si le Mac se met un jour à écrire un sport que le web ne connaît pas, le
  // voir à l'écran vaut mieux que de le voir disparaître dans un fourre-tout.
  return noms[brut] ?? brut
}

/// Le facteur et l'unité de la cadence, selon le sport — porté de
/// `SportType.cadence`.
///
/// Strava compte les foulées d'une seule jambe : une course à 77 se lit
/// 154 pas par minute, et afficher le chiffre brut donnait une cadence deux
/// fois trop lente. Les autres sports n'ont rien à doubler — un pédalier fait
/// un tour entier.
export function cadenceDuSport(sportRaw: string): { facteur: number; unite: string } {
  switch (sportRaw) {
    case "run":
    case "trailRun":
    case "walk":
    case "hike":
      return { facteur: 2, unite: "ppm" }
    case "swim":
      return { facteur: 1, unite: "coups/min" }
    default:
      return { facteur: 1, unite: "rpm" }
  }
}
