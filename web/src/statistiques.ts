/// Le calcul des statistiques, porté du Mac : `ActivityStatistics`,
/// `StatsPeriod`, `TrainingLoad`, `Regularity`, `Intensity` et
/// `SportProgress`. Les mêmes règles, appliquées aux mêmes endroits, pour que
/// les deux écrans disent les mêmes chiffres — voir les commentaires du Mac
/// pour le pourquoi de chacune.
///
/// **Les jours** sont des entiers : le nombre de jours depuis le 1er janvier
/// 1970, lus sur la date de `start_local_date`. Cette colonne porte l'heure
/// murale de la sortie encodée comme de l'UTC ; sa date est donc le jour où la
/// sortie a eu lieu *là où elle a eu lieu*, ce que fait `day(of:)` sur le Mac.
/// Aujourd'hui, lui, est le jour qu'on vit ici.

export type Sortie = {
  uuid: string
  name: string
  sport_type_raw: string
  start_date: string
  start_local_date: string
  distance: number
  moving_time: number
  total_elevation_gain: number
  average_speed: number
  average_heartrate: number | null
  hr_zone_floors: number[] | null
  hr_zone_seconds: number[] | null
  gear_id: string | null
}

// MARK: - Jours, semaines, mois

const JOUR_MS = 86_400_000

export function jourDe(sortie: Sortie): number {
  return jourDeCle(sortie.start_local_date.slice(0, 10))
}

export function jourDeCle(cle: string): number {
  const [a, m, j] = cle.split("-").map(Number)
  return Math.floor(Date.UTC(a, m - 1, j) / JOUR_MS)
}

export function aujourdhui(maintenant = new Date()): number {
  return Math.floor(
    Date.UTC(maintenant.getFullYear(), maintenant.getMonth(), maintenant.getDate()) / JOUR_MS,
  )
}

export function dateDuJour(jour: number): Date {
  return new Date(jour * JOUR_MS)
}

/// 0 pour lundi : les semaines commencent le lundi, comme sur le Mac.
export function jourDeSemaine(jour: number): number {
  // Le 1er janvier 1970 était un jeudi.
  return (jour + 3) % 7
}

export function debutDeSemaine(jour: number): number {
  return jour - jourDeSemaine(jour)
}

export function debutDeMois(jour: number): number {
  const d = dateDuJour(jour)
  return Math.floor(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) / JOUR_MS)
}

/// Des mois ajoutés comme `Calendar` : le 31 mars moins un mois tombe le
/// 28 février, pas le 3 mars.
export function ajouterMois(jour: number, mois: number): number {
  const d = dateDuJour(jour)
  const cible = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + mois, 1))
  const dernier = new Date(Date.UTC(cible.getUTCFullYear(), cible.getUTCMonth() + 1, 0)).getUTCDate()
  cible.setUTCDate(Math.min(d.getUTCDate(), dernier))
  return Math.floor(cible.getTime() / JOUR_MS)
}

// MARK: - Période

export type Periode = "3mois" | "6mois" | "12mois" | "annee"
export type Granularite = "semaine" | "mois"

export const PERIODES: { clef: Periode; nom: string }[] = [
  { clef: "3mois", nom: "3 mois" },
  { clef: "6mois", nom: "6 mois" },
  { clef: "12mois", nom: "12 mois" },
  { clef: "annee", nom: "Année" },
]

export function granularite(p: Periode): Granularite {
  return p === "3mois" || p === "6mois" ? "semaine" : "mois"
}

function debutDeCreneau(jour: number, g: Granularite): number {
  return g === "semaine" ? debutDeSemaine(jour) : debutDeMois(jour)
}

function decaler(jour: number, g: Granularite, n: number): number {
  return g === "semaine" ? jour + 7 * n : ajouterMois(jour, n)
}

function nombreDeCreneaux(p: Periode, auj: number): number {
  switch (p) {
    case "3mois": return 13
    case "6mois": return 26
    case "12mois": return 12
    case "annee": return dateDuJour(auj).getUTCMonth() + 1
  }
}

/// De combien de créneaux la comparaison recule : l'année entière pour
/// l'année en cours, sinon la tranche juste avant.
function decalage(p: Periode, auj: number): number {
  return p === "annee" ? 12 : nombreDeCreneaux(p, auj)
}

// MARK: - Cumuls, créneaux, sports, records

export type Totaux = { nombre: number; temps: number; denivele: number }

export type Creneau = {
  debut: number
  distance: number
  denivele: number
  temps: number
  distanceAvant: number
  deniveleAvant: number
  tempsAvant: number
}

export type ParSport = {
  sport: string
  nombre: number
  distance: number
  temps: number
  denivele: number
}

export type TypeRecord = "distance" | "denivele" | "duree" | "vitesse"

export type Record_ = {
  type: TypeRecord
  valeur: number
  sortie: Sortie
}

export type Statistiques = {
  totaux: Totaux
  comparaison: Totaux
  creneaux: Creneau[]
  sports: ParSport[]
  records: Record_[]
  debutPeriode: number
  granularite: Granularite
}

function totaliser(sorties: Sortie[]): Totaux {
  return {
    nombre: sorties.length,
    temps: sorties.reduce((s, a) => s + a.moving_time, 0),
    denivele: sorties.reduce((s, a) => s + a.total_elevation_gain, 0),
  }
}

export function calculer(sorties: Sortie[], periode: Periode, maintenant = new Date()): Statistiques {
  const auj = aujourdhui(maintenant)
  const g = granularite(periode)
  const nombre = nombreDeCreneaux(periode, auj)
  const recul = decalage(periode, auj)
  // L'année se décale en mois, même quand ses créneaux sont des mois.
  const gRecul: Granularite = periode === "annee" ? "mois" : g
  const courant = debutDeCreneau(auj, g)
  const debuts = Array.from({ length: nombre }, (_, i) => decaler(courant, g, i - nombre + 1))
  const premier = debuts[0]

  const parCreneau = new Map<number, { distance: number; denivele: number; temps: number }>()
  for (const a of sorties) {
    const c = debutDeCreneau(jourDe(a), g)
    const t = parCreneau.get(c) ?? { distance: 0, denivele: 0, temps: 0 }
    t.distance += a.distance
    t.denivele += a.total_elevation_gain
    t.temps += a.moving_time
    parCreneau.set(c, t)
  }

  const dansLaPeriode = sorties.filter((a) => {
    const c = debutDeCreneau(jourDe(a), g)
    return c >= premier && c <= courant
  })

  // La période précédente, arrêtée au même point que celle-ci.
  const premierAvant = decaler(premier, gRecul, -recul)
  const aujAvant = decaler(auj, gRecul, -recul)
  const avant = sorties.filter((a) => {
    const j = jourDe(a)
    return j >= premierAvant && j <= aujAvant
  })

  const creneaux = debuts.map((debut) => {
    const cur = parCreneau.get(debut)
    const prec = parCreneau.get(debutDeCreneau(decaler(debut, gRecul, -recul), g))
    return {
      debut,
      distance: cur?.distance ?? 0,
      denivele: cur?.denivele ?? 0,
      temps: cur?.temps ?? 0,
      distanceAvant: prec?.distance ?? 0,
      deniveleAvant: prec?.denivele ?? 0,
      tempsAvant: prec?.temps ?? 0,
    }
  })

  return {
    totaux: totaliser(dansLaPeriode),
    comparaison: totaliser(avant),
    creneaux,
    sports: parSport(dansLaPeriode),
    records: recordsGlobaux(dansLaPeriode),
    debutPeriode: premier,
    granularite: g,
  }
}

function parSport(sorties: Sortie[]): ParSport[] {
  const m = new Map<string, ParSport>()
  for (const a of sorties) {
    const t = m.get(a.sport_type_raw) ?? {
      sport: a.sport_type_raw, nombre: 0, distance: 0, temps: 0, denivele: 0,
    }
    t.nombre += 1
    t.distance += a.distance
    t.temps += a.moving_time
    t.denivele += a.total_elevation_gain
    m.set(a.sport_type_raw, t)
  }
  // Par temps : la seule mesure qui se compare entre sports.
  return [...m.values()].sort((x, y) => y.temps - x.temps || x.sport.localeCompare(y.sport))
}

function meilleure(sorties: Sortie[], valeur: (a: Sortie) => number): Sortie | undefined {
  let best: Sortie | undefined
  for (const a of sorties) if (!best || valeur(a) > valeur(best)) best = a
  return best && valeur(best) > 0 ? best : undefined
}

function recordsGlobaux(sorties: Sortie[]): Record_[] {
  const types: [TypeRecord, (a: Sortie) => number][] = [
    ["distance", (a) => a.distance],
    ["denivele", (a) => a.total_elevation_gain],
    ["duree", (a) => a.moving_time],
  ]
  return types.flatMap(([type, v]) => {
    const s = meilleure(sorties, v)
    return s ? [{ type, valeur: v(s), sortie: s }] : []
  })
}

// MARK: - Cette semaine

export type PointSemaine = { jour: number; distance: number; denivele: number; temps: number }

/// Les cumuls jour par jour de cette semaine, jusqu'à aujourd'hui, et de la
/// précédente entière.
export function semaines(sorties: Sortie[], maintenant = new Date()) {
  const auj = aujourdhui(maintenant)
  const lundi = debutDeSemaine(auj)
  const cumul = (depuis: number, jours: number): PointSemaine[] => {
    let distance = 0, denivele = 0, temps = 0
    const points: PointSemaine[] = []
    for (let i = 0; i < jours; i++) {
      for (const a of sorties) {
        if (jourDe(a) !== depuis + i) continue
        distance += a.distance
        denivele += a.total_elevation_gain
        temps += a.moving_time
      }
      points.push({ jour: i, distance, denivele, temps })
    }
    return points
  }
  return {
    celleCi: cumul(lundi, Math.min(auj - lundi + 1, 7)),
    derniere: cumul(lundi - 7, 7),
  }
}

// MARK: - Charge, forme, fatigue

export const JOURS_FORME = 42
export const JOURS_FATIGUE = 7

/// Le poids d'une FC moyenne dans les zones, continu : 2,5 est le milieu de
/// la zone 2.
export function poidsDeZone(fc: number, planchers: number[]): number {
  if (planchers.length === 0) return 1
  if (fc < planchers[0]) return planchers[0] > 0 ? Math.max(0, fc / planchers[0]) : 1
  for (let i = planchers.length - 1; i >= 0; i--) {
    if (fc < planchers[i]) continue
    if (i + 1 >= planchers.length) return i + 1
    const ecart = planchers[i + 1] - planchers[i]
    return i + 1 + (ecart > 0 ? (fc - planchers[i]) / ecart : 0)
  }
  return 1
}

/// Le TRIMP d'Edwards sur les zones Garmin ; sinon la FC moyenne placée dans
/// les zones de référence ; sinon une heure facile.
export function charge(a: Sortie, reference: number[] | null): { valeur: number; estimee: boolean } {
  const secondes = a.hr_zone_seconds
  if (secondes && secondes.reduce((s, v) => s + v, 0) > 0) {
    return { valeur: secondes.reduce((s, v, i) => s + (v / 60) * (i + 1), 0), estimee: false }
  }
  const minutes = a.moving_time / 60
  if (a.average_heartrate && a.average_heartrate > 0 && reference && reference.length > 0) {
    return { valeur: minutes * poidsDeZone(a.average_heartrate, reference), estimee: true }
  }
  return { valeur: minutes, estimee: true }
}

export type Quotidien = {
  charge: Map<number, number>
  temps: Map<number, number>
  estimees: number
  nombre: number
}

export function quotidien(sorties: Sortie[]): Quotidien {
  // Les zones bougent au fil des mois : une sortie sans les siennes prend
  // celles de la sortie la plus proche dans le temps.
  const avecZones = sorties
    .filter((a) => a.hr_zone_floors && a.hr_zone_floors.length > 0)
    .map((a) => ({ t: Date.parse(a.start_date), planchers: a.hr_zone_floors! }))
    .sort((x, y) => x.t - y.t)

  const plusProches = (t: number): number[] | null => {
    if (avecZones.length === 0) return null
    let bas = 0, haut = avecZones.length
    while (bas < haut) {
      const mil = (bas + haut) >> 1
      if (avecZones[mil].t < t) bas = mil + 1
      else haut = mil
    }
    const candidats = [bas - 1, bas].filter((i) => i >= 0 && i < avecZones.length)
    const i = candidats.reduce((m, c) =>
      Math.abs(avecZones[c].t - t) < Math.abs(avecZones[m].t - t) ? c : m,
    )
    return avecZones[i].planchers
  }

  const q: Quotidien = { charge: new Map(), temps: new Map(), estimees: 0, nombre: 0 }
  for (const a of sorties) {
    const j = jourDe(a)
    const c = charge(a, plusProches(Date.parse(a.start_date)))
    q.charge.set(j, (q.charge.get(j) ?? 0) + c.valeur)
    q.temps.set(j, (q.temps.get(j) ?? 0) + a.moving_time)
    q.nombre += 1
    if (c.estimee) q.estimees += 1
  }
  return q
}

export type PointForme = {
  jour: number
  charge: number
  forme: number
  fatigue: number
  /// La forme de la veille moins sa fatigue.
  fraicheur: number
}

/// Un point par jour, de la première sortie à aujourd'hui.
export function serie(q: Quotidien, maintenant = new Date()): PointForme[] {
  const jours = [...q.charge.keys()]
  if (jours.length === 0) return []
  const auj = aujourdhui(maintenant)
  let forme = 0, fatigue = 0
  const points: PointForme[] = []
  for (let j = Math.min(...jours); j <= auj; j++) {
    const c = q.charge.get(j) ?? 0
    const fraicheur = forme - fatigue
    forme += (c - forme) / JOURS_FORME
    fatigue += (c - fatigue) / JOURS_FATIGUE
    points.push({ jour: j, charge: c, forme, fatigue, fraicheur })
  }
  return points
}

export type Etat = { nom: string; conseil: string; couleur: string }

export function etat(p: PointForme): Etat {
  const r = p.fraicheur / Math.max(p.forme, 1)
  if (r < -0.3)
    return { nom: "Surcharge", conseil: "La fatigue dépasse de loin la forme : du repos s'impose.", couleur: "var(--orange)" }
  if (r < -0.1)
    return { nom: "En charge — productif", conseil: "La fatigue dépasse la forme d'assez pour la faire monter.", couleur: "var(--accent)" }
  if (r < 0.05)
    return { nom: "Équilibré", conseil: "Ni fatigué ni reposé : la charge suit la forme.", couleur: "var(--texte-2)" }
  if (r < 0.25)
    return { nom: "Frais", conseil: "Reposé : un bon moment pour une sortie clé ou une course.", couleur: "var(--vert)" }
  return { nom: "Au repos prolongé", conseil: "Très reposé, trop longtemps : la forme redescend.", couleur: "var(--or)" }
}

export function rampe(points: PointForme[]): number | null {
  if (points.length <= 7) return null
  return points[points.length - 1].forme - points[points.length - 8].forme
}

// MARK: - Régularité

export const SEMAINES_AFFICHEES = 53

export type CaseJour = { jour: number; semaine: number; jourSemaine: number; charge: number; temps: number }

export type Projection = {
  annee: number
  tempsADate: number
  tempsProjete: number
  sportPrincipal: string | null
  distanceProjetee: number
}

export type Regularite = {
  jours: CaseJour[]
  joursActifs: number
  joursPeriode: number
  serieEnCours: number
  meilleureSerie: number
  heuresParSemaine: number
  projection: Projection | null
}

export function regularite(
  sorties: Sortie[],
  q: Quotidien,
  debutPeriode: number,
  maintenant = new Date(),
): Regularite {
  const auj = aujourdhui(maintenant)
  const cetteSemaine = debutDeSemaine(auj)
  const premiere = cetteSemaine - 7 * (SEMAINES_AFFICHEES - 1)

  const jours: CaseJour[] = []
  for (let s = 0; s < SEMAINES_AFFICHEES; s++) {
    for (let d = 0; d < 7; d++) {
      const jour = premiere + s * 7 + d
      if (jour > auj) continue
      jours.push({ jour, semaine: s, jourSemaine: d, charge: q.charge.get(jour) ?? 0, temps: q.temps.get(jour) ?? 0 })
    }
  }

  const joursPeriode = Math.max(1, auj - debutPeriode + 1)
  let joursActifs = 0, secondes = 0
  for (const [jour, t] of q.temps) {
    if (jour < debutPeriode || jour > auj) continue
    secondes += t
    if (t > 0) joursActifs += 1
  }

  const semainesActives = new Set([...q.charge.keys()].map(debutDeSemaine))
  let meilleure = 0, courante = 0
  if (semainesActives.size > 0) {
    for (let s = Math.min(...semainesActives); s <= cetteSemaine; s += 7) {
      courante = semainesActives.has(s) ? courante + 1 : 0
      meilleure = Math.max(meilleure, courante)
    }
  }
  // Un lundi matin sans sortie ne casse pas la série.
  let serieEnCours = 0
  for (
    let s = semainesActives.has(cetteSemaine) ? cetteSemaine : cetteSemaine - 7;
    semainesActives.has(s);
    s -= 7
  ) serieEnCours += 1

  return {
    jours,
    joursActifs,
    joursPeriode,
    serieEnCours,
    meilleureSerie: meilleure,
    heuresParSemaine: secondes / 3600 / (joursPeriode / 7),
    projection: projection(sorties, maintenant),
  }
}

function projection(sorties: Sortie[], maintenant: Date): Projection | null {
  const annee = maintenant.getFullYear()
  const debut = jourDeCle(`${annee}-01-01`)
  const suivante = jourDeCle(`${annee + 1}-01-01`)
  const cetteAnnee = sorties.filter((a) => {
    const j = jourDe(a)
    return j >= debut && j < suivante
  })
  if (cetteAnnee.length === 0) return null
  // Aujourd'hui compté entier.
  const ecoules = aujourdhui(maintenant) - debut + 1
  const facteur = (suivante - debut) / Math.max(ecoules, 1)
  const temps = cetteAnnee.reduce((s, a) => s + a.moving_time, 0)
  const parSport = new Map<string, { temps: number; distance: number }>()
  for (const a of cetteAnnee) {
    const t = parSport.get(a.sport_type_raw) ?? { temps: 0, distance: 0 }
    t.temps += a.moving_time
    t.distance += a.distance
    parSport.set(a.sport_type_raw, t)
  }
  const principal = [...parSport.entries()]
    .filter(([, t]) => t.distance > 0)
    .sort((x, y) => y[1].temps - x[1].temps)[0]
  return {
    annee,
    tempsADate: temps,
    tempsProjete: temps * facteur,
    sportPrincipal: principal?.[0] ?? null,
    distanceProjetee: (principal?.[1].distance ?? 0) * facteur,
  }
}

/// Cinq niveaux : rien, puis les quartiles des jours actifs affichés.
export function niveaux(jours: CaseJour[]): Map<number, number> {
  const charges = jours.map((j) => j.charge).filter((c) => c > 0).sort((a, b) => a - b)
  const m = new Map<number, number>()
  if (charges.length === 0) return m
  const q = (x: number) => charges[Math.min(charges.length - 1, Math.floor(charges.length * x))]
  const bornes = [q(0.25), q(0.5), q(0.75)]
  for (const j of jours) if (j.charge > 0) m.set(j.jour, 1 + bornes.filter((b) => j.charge > b).length)
  return m
}

// MARK: - Intensité

export type Intensite = {
  secondes: number[]
  creneaux: { debut: number; secondes: number[] }[]
  couvertes: number
  nombre: number
}

export function intensite(sorties: Sortie[], debuts: number[], g: Granularite): Intensite {
  const totaux = [0, 0, 0, 0, 0]
  const parCreneau = new Map<number, number[]>()
  let couvertes = 0, nombre = 0
  const premier = debuts[0] ?? Infinity
  for (const a of sorties) {
    const c = debutDeCreneau(jourDe(a), g)
    if (c < premier) continue
    nombre += 1
    const s = a.hr_zone_seconds
    if (!s || s.reduce((x, v) => x + v, 0) <= 0) continue
    couvertes += 1
    const t = parCreneau.get(c) ?? [0, 0, 0, 0, 0]
    s.slice(0, 5).forEach((v, i) => {
      totaux[i] += v
      t[i] += v
    })
    parCreneau.set(c, t)
  }
  return {
    secondes: totaux,
    creneaux: debuts.map((debut) => ({ debut, secondes: parCreneau.get(debut) ?? [0, 0, 0, 0, 0] })),
    couvertes,
    nombre,
  }
}

export function part(i: Intensite, de: number, a: number): number {
  const total = i.secondes.reduce((s, v) => s + v, 0)
  if (total <= 0) return 0
  return i.secondes.slice(de - 1, a).reduce((s, v) => s + v, 0) / total
}

export function profil(i: Intensite): { nom: string; explication: string } | null {
  const total = i.secondes.reduce((s, v) => s + v, 0)
  if (total <= 0) return null
  const modere = part(i, 3, 3), dur = part(i, 4, 5)
  if (modere > 0.25)
    return { nom: "Orienté seuil", explication: "Une grosse part en zone 3 : la « zone grise », fatigante sans être très productive." }
  if (dur < 0.05)
    return { nom: "Presque tout en facile", explication: "L'intensité manque : quelques séances dures feraient progresser." }
  return dur > modere
    ? { nom: "Polarisé", explication: "Beaucoup de facile, du dur, peu d'entre-deux : le modèle des sports d'endurance." }
    : { nom: "Pyramidal", explication: "Surtout du facile, puis de moins en moins à mesure que l'intensité monte." }
}

// MARK: - Progression d'un sport

export type Mesure = "vitesse" | "fc" | "efficacite"

export function enKmEffort(sport: string): boolean {
  return sport === "trailRun" || sport === "hike"
}

export function distanceEffort(a: Sortie): number {
  return enKmEffort(a.sport_type_raw) ? a.distance + a.total_elevation_gain * 10 : a.distance
}

export type PointProgression = {
  sortie: Sortie
  jour: number
  vitesse: number
  fc: number | null
}

export function valeur(p: PointProgression, m: Mesure): number | null {
  if (m === "vitesse") return p.vitesse
  if (m === "fc") return p.fc
  return p.fc && p.fc > 0 ? (p.vitesse * 60) / p.fc : null
}

export type Materiel = { id: string; nom: string; distance: number; nombre: number }

export type Progression = {
  sport: string
  points: PointProgression[]
  records: Record_[]
  materiel: Materiel[]
}

export function sportsSuivis(sorties: Sortie[], debut: number): string[] {
  const m = new Map<string, { n: number; t: number }>()
  for (const a of sorties) {
    if (a.distance <= 0 || jourDe(a) < debut) continue
    const t = m.get(a.sport_type_raw) ?? { n: 0, t: 0 }
    t.n += 1
    t.t += a.moving_time
    m.set(a.sport_type_raw, t)
  }
  return [...m.entries()].filter(([, t]) => t.n >= 3).sort((x, y) => y[1].t - x[1].t).map(([s]) => s)
}

export function progression(
  sorties: Sortie[],
  sport: string,
  debut: number,
  nomsMateriel: Map<string, string>,
): Progression {
  const duSport = sorties.filter((a) => a.sport_type_raw === sport)
  const dansLaPeriode = duSport.filter((a) => jourDe(a) >= debut)
  const points = dansLaPeriode
    .filter((a) => a.moving_time >= 600 && a.distance >= 1000)
    .map((a) => ({ sortie: a, jour: jourDe(a), vitesse: distanceEffort(a) / a.moving_time, fc: a.average_heartrate }))
    .sort((x, y) => x.jour - y.jour)

  // Les km d'un matériel : toutes ses sorties, recalculées ici, jamais le
  // total de Strava qui dérive.
  const km = new Map<string, number>()
  for (const a of sorties) if (a.gear_id) km.set(a.gear_id, (km.get(a.gear_id) ?? 0) + a.distance)
  const usage = new Map<string, number>()
  for (const a of dansLaPeriode) if (a.gear_id) usage.set(a.gear_id, (usage.get(a.gear_id) ?? 0) + 1)
  const materiel = [...usage.entries()]
    .filter(([id]) => nomsMateriel.has(id))
    .map(([id, nombre]) => ({ id, nom: nomsMateriel.get(id)!, distance: km.get(id) ?? 0, nombre }))
    .sort((x, y) => y.nombre - x.nombre)

  return { sport, points, records: recordsDuSport(duSport), materiel }
}

function recordsDuSport(sorties: Sortie[]): Record_[] {
  const vitesseEffort = (a: Sortie) => distanceEffort(a) / a.moving_time
  const distances = sorties.map(distanceEffort).filter((d) => d > 0).sort((a, b) => a - b)
  const mediane = distances.length ? distances[Math.floor(distances.length / 2)] : 0
  const candidates = sorties.filter((a) => distanceEffort(a) >= mediane / 2 && a.moving_time > 0)
  const out: Record_[] = []
  const longue = meilleure(sorties, (a) => a.distance)
  if (longue) out.push({ type: "distance", valeur: longue.distance, sortie: longue })
  const grimpante = meilleure(sorties, (a) => a.total_elevation_gain)
  if (grimpante) out.push({ type: "denivele", valeur: grimpante.total_elevation_gain, sortie: grimpante })
  const rapide = meilleure(candidates, vitesseEffort)
  if (rapide) out.push({ type: "vitesse", valeur: vitesseEffort(rapide), sortie: rapide })
  return out
}

/// La droite des moindres carrés : sa valeur au premier et au dernier jour.
export function tendance(
  points: PointProgression[],
  m: Mesure,
): { debut: number; fin: number; jourDebut: number; jourFin: number; ecart: number } | null {
  const e = points.flatMap((p) => {
    const v = valeur(p, m)
    return v === null ? [] : [{ x: p.jour, y: v }]
  })
  if (e.length < 3 || e[e.length - 1].x <= e[0].x) return null
  const n = e.length
  const mx = e.reduce((s, p) => s + p.x, 0) / n
  const my = e.reduce((s, p) => s + p.y, 0) / n
  const cov = e.reduce((s, p) => s + (p.x - mx) * (p.y - my), 0)
  const vari = e.reduce((s, p) => s + (p.x - mx) ** 2, 0)
  if (vari <= 0) return null
  const pente = cov / vari
  const a = (x: number) => my + pente * (x - mx)
  const debut = a(e[0].x), fin = a(e[n - 1].x)
  return {
    debut, fin, jourDebut: e[0].x, jourFin: e[n - 1].x,
    ecart: debut !== 0 ? ((fin - debut) / Math.abs(debut)) * 100 : 0,
  }
}
