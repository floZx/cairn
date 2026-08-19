/// Le rapprochement séance ↔ sortie, porté de `TrainingMatch.swift`.
///
/// Porté mot pour mot, et pas seulement dans l'esprit : les deux écrans
/// montrent le même plan, et une séance cochée sur le Mac mais pas sur le
/// téléphone ferait douter des deux. Toute retouche ici doit se faire là-bas,
/// où des tests la tiennent.

/// Les sports qui s'accomplissent l'un l'autre. Un trail prévu et couru sur
/// route est fait ; une natation ne remplace pas un footing.
const FAMILLES: string[][] = [
  ["ride", "mountainBikeRide", "gravelRide", "eBikeRide"],
  ["run", "trailRun"],
  ["walk", "hike"],
  ["nordicSki", "alpineSki"],
]

function memeFamille(un: string, autre: string): boolean {
  return un === autre || FAMILLES.some((f) => f.includes(un) && f.includes(autre))
}

export type Paire<S, A> = { seance: S; sortie: A | null }
export type Rapprochement<S, A> = { paires: Paire<S, A>[]; enPlus: A[] }

/// Apparie les séances d'**un** jour avec les sorties de ce jour.
///
/// Deux passes : le sport exact d'abord, la famille ensuite. Sans la première,
/// un plan « footing puis vélo » un jour où l'on a fait les deux pourrait
/// donner le vélo au footing.
export function apparie<S, A>(
  seances: S[],
  sorties: A[],
  sportSeance: (s: S) => string,
  sportSortie: (a: A) => string,
): Rapprochement<S, A> {
  let libres = sorties.map((_, i) => i)
  const attribuee: (number | null)[] = seances.map(() => null)

  for (const exact of [true, false]) {
    seances.forEach((seance, rang) => {
      if (attribuee[rang] !== null) return
      const vise = sportSeance(seance)
      const place = libres.findIndex((index) => {
        const fait = sportSortie(sorties[index])
        return exact ? fait === vise : memeFamille(vise, fait)
      })
      if (place === -1) return
      attribuee[rang] = libres[place]
      libres = libres.filter((_, i) => i !== place)
    })
  }

  return {
    paires: seances.map((seance, rang) => {
      const index = attribuee[rang]
      return { seance, sortie: index === null ? null : sorties[index] }
    }),
    enPlus: libres.map((index) => sorties[index]),
  }
}

/// Les semaines d'un mois, lundi en tête, complétées de vides aux deux bouts —
/// la même grille que `MiniCalendarModel.weeks` côté Mac.
export function semainesDuMois(annee: number, mois: number): (string | null)[][] {
  const premier = new Date(annee, mois, 1)
  const jours = new Date(annee, mois + 1, 0).getDate()
  // `getDay()` compte à partir du dimanche ; le décalage remet lundi en tête.
  const avant = (premier.getDay() + 6) % 7
  const deux = (n: number) => String(n).padStart(2, "0")
  const cases: (string | null)[] = Array(avant).fill(null)
  for (let jour = 1; jour <= jours; jour++) {
    cases.push(`${annee}-${deux(mois + 1)}-${deux(jour)}`)
  }
  while (cases.length % 7 !== 0) cases.push(null)
  const semaines: (string | null)[][] = []
  for (let debut = 0; debut < cases.length; debut += 7) {
    semaines.push(cases.slice(debut, debut + 7))
  }
  return semaines
}

/// « 18 km · 1 h 30 · 400 m », en ne disant que ce qui est visé.
export function objectifResume(
  distance: number | null,
  duree: number | null,
  denivele: number | null,
): string | null {
  const morceaux: string[] = []
  if (distance !== null) {
    const km = distance / 1000
    morceaux.push(`${km % 1 === 0 ? km : km.toFixed(1).replace(".", ",")} km`)
  }
  if (duree !== null) {
    const minutes = Math.round(duree / 60)
    const heures = Math.floor(minutes / 60)
    const reste = minutes % 60
    morceaux.push(heures > 0 ? (reste > 0 ? `${heures} h ${reste}` : `${heures} h`) : `${minutes} min`)
  }
  if (denivele !== null) morceaux.push(`${Math.round(denivele)} m D+`)
  return morceaux.length > 0 ? morceaux.join(" · ") : null
}
