/// Les étiquettes d'une sortie, portées d'`ActivityLabel` et d'`Activity.labels`.
///
/// Portées et non redevinées : la correspondance entre le code de Strava et
/// l'étiquette est une table de valeurs que rien ne rend évidente — 2 vaut
/// « sortie longue », 1, 11 et 31 valent « compétition » — et deux versions
/// finiraient par se contredire sur une activité précise.

export type Etiquette =
  | "favorite"
  | "race"
  | "longRun"
  | "workout"
  | "commute"
  | "trainer"
  | "manual"

export const NOMS: Record<Etiquette, string> = {
  favorite: "Favori",
  race: "Compétition",
  longRun: "Sortie longue",
  workout: "Entraînement",
  commute: "Trajet",
  trainer: "Intérieur",
  manual: "Manuelle",
}

/// Le code que Strava envoie, quand un type a réellement été choisi.
///
/// Sinon il envoie le nombre rond de la famille — 0, 10, 30 — ou rien du tout ;
/// les deux veulent dire « pas de type particulier » et ne donnent aucune
/// étiquette. Les courses emploient 0-3, le vélo 10-12, la salle 30-32 : chaque
/// famille garde son nombre rond pour « rien de particulier », puis +1 pour une
/// compétition et +2 pour un entraînement.
export function depuisWorkoutType(code: number | null): Etiquette | null {
  switch (code) {
    case 1:
    case 11:
    case 31:
      return "race"
    case 2:
      return "longRun"
    case 3:
    case 12:
    case 32:
      return "workout"
    default:
      return null
  }
}

export type SourceEtiquettes = {
  source_raw: string
  workout_type: number | null
  workout_label_raw: string | null
  edited_fields: string[] | null
  is_favorite: boolean
  is_commute: boolean
  is_trainer: boolean
  is_manual: boolean
}

/// Le type retenu : celui de Cairn dès qu'il a été revendiqué, celui de Strava
/// sinon.
///
/// C'est tout l'enjeu de la règle : la valeur locale l'emporte dès que
/// `workoutLabel` figure dans les champs édités, et cette revendication est
/// aussi ce qui fait de « aucun type » un choix délibéré plutôt qu'une absence.
/// Sur une activité qui n'est jamais venue de Strava il n'y a rien pour
/// retomber, donc la valeur locale gagne toujours.
function typeRetenu(a: SourceEtiquettes): Etiquette | null {
  const synchronisee = a.source_raw === "strava"
  const revendique = (a.edited_fields ?? []).includes("workoutLabel")
  if (!synchronisee || revendique) {
    return (a.workout_label_raw as Etiquette | null) || null
  }
  return depuisWorkoutType(a.workout_type)
}

/// Les marqueurs posés sur une sortie, dans l'ordre stable d'affichage du Mac.
export function etiquettesDe(a: SourceEtiquettes): Etiquette[] {
  const trouvees: Etiquette[] = []
  if (a.is_favorite) trouvees.push("favorite")
  const type = typeRetenu(a)
  if (type) trouvees.push(type)
  if (a.is_commute) trouvees.push("commute")
  if (a.is_trainer) trouvees.push("trainer")
  // `is_manual`, colonne à part entière, et non une déduction de `source_raw` :
  // le Mac garde les deux, et une activité importée d'un GPX est manuelle sans
  // que sa source le dise.
  if (a.is_manual) trouvees.push("manual")
  return trouvees
}
