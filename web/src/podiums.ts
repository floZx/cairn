/// Les meilleurs efforts, lus tels que le Mac les a calculés.
///
/// Le Mac tire de chaque sortie à pied ses meilleurs temps sur les distances
/// de Strava, depuis les séries seconde par seconde, et les range dans
/// `activity.best_efforts`. Le web ne refait pas ce calcul — il faudrait les
/// séries de toute la bibliothèque — : il classe seulement, ce qui ne coûte
/// qu'une requête de quelques centaines de lignes.
///
/// Les mêmes règles que `EffortStandings` côté Mac : trois places par
/// distance, du plus rapide au plus lent, et à égalité le plus ancien d'abord.

import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"

/// Dans l'ordre de `EffortDistance` sur le Mac, qui est celui des cases de
/// `best_efforts`. Il ne fait que s'allonger.
export const DISTANCES = [
  { label: "400 m", metres: 400 },
  { label: "1/2 mile", metres: 804.672 },
  { label: "1 km", metres: 1000 },
  { label: "1 mile", metres: 1609.344 },
  { label: "2 miles", metres: 3218.688 },
  { label: "5 km", metres: 5000 },
  { label: "10 km", metres: 10_000 },
  { label: "15 km", metres: 15_000 },
  { label: "10 miles", metres: 16_093.44 },
  { label: "20 km", metres: 20_000 },
  { label: "Semi-marathon", metres: 21_097.5 },
  { label: "30 km", metres: 30_000 },
  { label: "Marathon", metres: 42_195 },
] as const

export const PODIUM = 3

export type SortieClassee = {
  uuid: string
  name: string
  start_date: string
  start_local_date: string
  best_efforts: number[]
}

export type Place = { sortie: SortieClassee; secondes: number }

/// Une médaille d'une sortie : l'indice de la distance dans `DISTANCES`, la
/// place (1, 2 ou 3) et le temps.
export type Medaille = { distance: number; rang: number; secondes: number }

export type Podiums = {
  /// Pour chaque distance, ses trois meilleures places — vide si personne.
  parDistance: Place[][]
  medailles: Map<string, Medaille[]>
}

export function classer(sorties: SortieClassee[]): Podiums {
  const parDistance = DISTANCES.map((_, i) =>
    sorties
      .filter((s) => (s.best_efforts[i] ?? 0) > 0)
      .map((s) => ({ sortie: s, secondes: s.best_efforts[i] }))
      .sort(
        (a, b) =>
          a.secondes - b.secondes || a.sortie.start_date.localeCompare(b.sortie.start_date),
      )
      .slice(0, PODIUM),
  )
  const medailles = new Map<string, Medaille[]>()
  parDistance.forEach((places, distance) =>
    places.forEach((p, i) => {
      const liste = medailles.get(p.sortie.uuid) ?? []
      liste.push({ distance, rang: i + 1, secondes: p.secondes })
      medailles.set(p.sortie.uuid, liste)
    }),
  )
  return { parDistance, medailles }
}

const PAGE = 1000

async function sortiesClassees(): Promise<SortieClassee[]> {
  const toutes: SortieClassee[] = []
  for (let debut = 0; ; debut += PAGE) {
    const { data, error } = await supabase
      .from("activity")
      .select("uuid, name, start_date, start_local_date, best_efforts")
      .not("best_efforts", "is", null)
      .is("deleted_at", null)
      .order("uuid")
      .range(debut, debut + PAGE - 1)
    if (error) throw error
    toutes.push(...(data as unknown as SortieClassee[]))
    if (!data || data.length < PAGE) return toutes
  }
}

/// Les podiums de toute la bibliothèque, partagés par la liste, la fiche et
/// les statistiques : une seule requête pour les trois.
export function usePodiums() {
  return useQuery({
    queryKey: ["podiums"],
    queryFn: async () => classer(await sortiesClassees()),
    staleTime: 5 * 60_000,
  })
}

/// « 21:34 », « 1:42:07 » : un temps de course, comme sur le Mac.
export function tempsDeCourse(secondes: number): string {
  const total = Math.round(secondes)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const deux = (n: number) => String(n).padStart(2, "0")
  return h > 0 ? `${h}:${deux(m)}:${deux(s)}` : `${m}:${deux(s)}`
}

export function rangEnLettres(rang: number): string {
  return rang === 1 ? "1er" : `${rang}e`
}

/// Or, argent, bronze — les couleurs de `EffortMedal` sur le Mac.
export function couleurMedaille(rang: number): string {
  return rang === 1 ? "#edb821" : rang === 2 ? "#9ea6b3" : "#c27d45"
}
