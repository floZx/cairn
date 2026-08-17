import {
  NOMS as NOMS_ETIQUETTES,
  etiquettesDe,
  type Etiquette,
  type SourceEtiquettes,
} from "./etiquettes"
import { nomDuSport } from "./sports"

/// Le filtre des activités, porté d'`ActivityFilter`.
///
/// Le partage entre ce qui part en requête et ce qui se règle ici est le même
/// que sur le Mac, et pour les mêmes raisons : le dénivelé par kilomètre
/// demande une division, et les étiquettes se déduisent de trois colonnes par
/// une règle que SQL ne sait pas dire. Le reste rétrécit la liste avant
/// qu'elle voyage.
///
/// La zone géographique du Mac manque, faute de carte d'ensemble ici pour la
/// dessiner. Elle viendra avec elle.

export type Periode = "all" | "last30Days" | "last90Days" | "thisYear" | "lastYear"

export const PERIODES: { clef: Periode; nom: string }[] = [
  { clef: "all", nom: "Toutes les dates" },
  { clef: "last30Days", nom: "30 derniers jours" },
  { clef: "last90Days", nom: "90 derniers jours" },
  { clef: "thisYear", nom: "Cette année" },
  { clef: "lastYear", nom: "L'an dernier" },
]

export type Filtre = {
  recherche: string
  sports: string[]
  periode: Periode
  distanceMin: number | null
  distanceMax: number | null
  deniveleMin: number | null
  deniveleMax: number | null
  denivelleParKmMin: number | null
  etiquettes: Etiquette[]
  /// La zone dessinée sur la carte d'ensemble, en degrés.
  ///
  /// Le cadre englobant d'une sortie sert de pré-filtre — il est indexé, et
  /// SQL sait le comparer — mais un cadre peut chevaucher une zone qu'aucun
  /// point de la trace n'atteint. Le Mac tranche ensuite sur les points ; ici
  /// le pré-filtre suffit, faute d'avoir les traces sous la main au moment de
  /// filtrer la liste.
  zone: Zone | null
}

export type Zone = {
  minLat: number
  maxLat: number
  minLon: number
  maxLon: number
}

export const AUCUN: Filtre = {
  recherche: "",
  sports: [],
  periode: "all",
  distanceMin: null,
  distanceMax: null,
  deniveleMin: null,
  deniveleMax: null,
  denivelleParKmMin: null,
  etiquettes: [],
  zone: null,
}

export function estActif(f: Filtre): boolean {
  return criteres(f).length > 0
}

/// Chaque critère actif en une phrase courte, dans un ordre stable.
///
/// Une liste raccourcie sans raison visible déroute ; ce résumé s'affiche donc
/// à côté du compte. Au-delà de trois, on abrège : il s'agit de savoir qu'un
/// filtre est posé et lequel à peu près, pas de le relire en entier.
export function criteres(f: Filtre): string[] {
  const parts: string[] = []
  const texte = f.recherche.trim()
  if (texte) parts.push(`« ${texte} »`)
  if (f.sports.length) {
    const noms = f.sports.map(nomDuSport)
    parts.push(noms.length <= 2 ? noms.join(", ") : `${noms.length} sports`)
  }
  if (f.periode !== "all") {
    parts.push(PERIODES.find((p) => p.clef === f.periode)!.nom)
  }
  if (f.distanceMin != null) parts.push(`≥ ${f.distanceMin} km`)
  if (f.distanceMax != null) parts.push(`≤ ${f.distanceMax} km`)
  if (f.deniveleMin != null) parts.push(`D+ ≥ ${f.deniveleMin} m`)
  if (f.deniveleMax != null) parts.push(`D+ ≤ ${f.deniveleMax} m`)
  if (f.denivelleParKmMin != null) parts.push(`D+/km ≥ ${f.denivelleParKmMin} m`)
  parts.push(...f.etiquettes.map((e) => NOMS_ETIQUETTES[e]))
  if (f.zone) parts.push("zone sur la carte")
  return parts
}

export function resume(f: Filtre): string | null {
  const parts = criteres(f)
  if (!parts.length) return null
  if (parts.length <= 3) return parts.join(" · ")
  return `${parts.slice(0, 3).join(" · ")} · +${parts.length - 3}`
}

/// Les bornes de la période, en dates locales.
///
/// « L'an dernier » a une fin, les autres non — c'est la seule qui désigne un
/// intervalle fermé.
export function bornes(f: Filtre, maintenant = new Date()) {
  const debutAnnee = new Date(maintenant.getFullYear(), 0, 1)
  switch (f.periode) {
    case "last30Days":
      return { debut: new Date(maintenant.getTime() - 30 * 864e5), fin: null }
    case "last90Days":
      return { debut: new Date(maintenant.getTime() - 90 * 864e5), fin: null }
    case "thisYear":
      return { debut: debutAnnee, fin: null }
    case "lastYear":
      return {
        debut: new Date(maintenant.getFullYear() - 1, 0, 1),
        fin: debutAnnee,
      }
    default:
      return { debut: null, fin: null }
  }
}

type LigneFiltrable = SourceEtiquettes & {
  distance: number
  total_elevation_gain: number
}

/// Le second passage, celui que la requête ne sait pas faire.
///
/// Une activité doit porter **toutes** les étiquettes cochées, comme sur le
/// Mac — cocher « compétition » et « favori » demande les deux, pas l'une ou
/// l'autre.
export function passeLeSecondFiltre(f: Filtre, ligne: LigneFiltrable): boolean {
  if (f.etiquettes.length) {
    const siennes = new Set(etiquettesDe(ligne))
    if (!f.etiquettes.every((e) => siennes.has(e))) return false
  }
  if (f.denivelleParKmMin != null) {
    // Une activité sans distance ne peut pas être vallonnée : elle ne franchit
    // donc jamais un plancher de dénivelé par kilomètre.
    if (ligne.distance <= 0) return false
    if (ligne.total_elevation_gain / (ligne.distance / 1000) < f.denivelleParKmMin) {
      return false
    }
  }
  return true
}
