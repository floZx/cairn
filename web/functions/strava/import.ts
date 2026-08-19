import { identifier, jetonStrava, json, supabase, type Env } from "./_commun"

/// Importer les sorties récentes que Cairn n'a pas encore.
///
/// Le Mac reste la source de vérité : il télécharge tout lui-même depuis
/// Strava — flux, tours, photos — et cette fonction ne pose qu'une ligne
/// sommaire, de quoi voir la sortie sur le fil du téléphone le soir même. Le
/// Mac la complétera à son passage **sans la dédoubler**, parce qu'il demande
/// au miroir, avant d'envoyer, quel `uuid` porte déjà cet identifiant Strava.
///
/// Deux garde-fous avant d'écrire, et ils comptent autant l'un que l'autre :
///
/// - une sortie déjà dans `activity` n'est pas réimportée, sinon le doublon
///   serait créé ici même ;
/// - une sortie rangée dans `discarded_activity` ne l'est pas non plus. C'est
///   la liste de ce que tu as **écarté exprès** sur le Mac, et la ressusciter
///   depuis le téléphone serait défaire un geste délibéré.

/// Le vocabulaire de Strava vers celui de Cairn — porté de
/// `SportType.init(stravaValue:)`. Deux applications qui rangent le même sport
/// ailleurs n'ont l'air que d'une seule à moitié finie.
const SPORTS: Record<string, string> = {
  Ride: "ride",
  MountainBikeRide: "mountainBikeRide",
  GravelRide: "gravelRide",
  EBikeRide: "eBikeRide",
  EMountainBikeRide: "eBikeRide",
  Run: "run",
  TrailRun: "trailRun",
  Walk: "walk",
  Hike: "hike",
  Swim: "swim",
  NordicSki: "nordicSki",
  BackcountrySki: "nordicSki",
  AlpineSki: "alpineSki",
  Snowboard: "alpineSki",
  Rowing: "rowing",
  Kayaking: "rowing",
  Canoeing: "rowing",
  Workout: "workout",
  WeightTraining: "workout",
  Crossfit: "workout",
  Yoga: "workout",
}

type SortieStrava = {
  id: number
  name: string
  sport_type?: string
  type?: string
  start_date: string
  start_date_local: string
  timezone?: string
  distance: number
  moving_time: number
  elapsed_time: number
  total_elevation_gain: number
  average_speed: number
  max_speed: number
  average_heartrate?: number
  max_heartrate?: number
  average_watts?: number
  average_cadence?: number
  calories?: number
  trainer?: boolean
  commute?: boolean
  manual?: boolean
  map?: { summary_polyline?: string }
}

/// Le décodage du tracé résumé de Strava — l'algorithme de Google, celui que
/// tout le monde emploie.
function décodePolyline(encode: string): [number, number][] {
  const points: [number, number][] = []
  let index = 0
  let lat = 0
  let lon = 0
  while (index < encode.length) {
    for (const axe of [0, 1]) {
      let resultat = 0
      let decalage = 0
      let octet: number
      do {
        octet = encode.charCodeAt(index++) - 63
        resultat |= (octet & 0x1f) << decalage
        decalage += 5
      } while (octet >= 0x20)
      const delta = resultat & 1 ? ~(resultat >> 1) : resultat >> 1
      if (axe === 0) lat += delta
      else lon += delta
    }
    points.push([lat / 1e5, lon / 1e5])
  }
  return points
}

/// Les coordonnées au format que Postgres attend pour un `bytea`, et que le
/// Mac écrit : des `Float64` bruts, en petit-boutiste, par paires
/// latitude/longitude, préfixés de `\x` en hexadécimal.
///
/// L'inverse exact de `traceDepuisBytea` côté page — c'est ce qui rend
/// l'aller-retour symétrique.
function enBytea(points: [number, number][]): string {
  const tampon = new ArrayBuffer(points.length * 16)
  const vue = new DataView(tampon)
  points.forEach(([lat, lon], i) => {
    vue.setFloat64(i * 16, lat, true)
    vue.setFloat64(i * 16 + 8, lon, true)
  })
  const octets = new Uint8Array(tampon)
  let hex = "\\x"
  for (const octet of octets) hex += octet.toString(16).padStart(2, "0")
  return hex
}

/// L'heure murale estampillée `+00:00`, comme le Mac l'écrit.
///
/// `start_local_date` porte l'heure qu'il était sur place, et rien d'autre :
/// c'est ce que son nom dit, et ce dont tous les affichages dépendent. Strava
/// rend `start_date_local` déjà en heure locale mais suffixé `Z` — la même
/// convention, par chance.
function heureMurale(local: string): string {
  return local.endsWith("Z") ? local.replace("Z", "+00:00") : local
}

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const qui = await identifier(request, env)
  if (!qui) return json({ erreur: "Session expirée, reconnecte-toi." }, 401)

  const acces = await jetonStrava(env, qui.token, qui.userID)
  if (!acces) return json({ erreur: "Cairn n'est pas connecté à Strava." }, 428)

  // Les trente derniers jours : au-delà, c'est le travail du Mac, et les
  // quotas de Strava — cent requêtes par quart d'heure — ne sont pas faits
  // pour rejouer une bibliothèque depuis un téléphone.
  const depuis = Math.floor(Date.now() / 1000) - 30 * 24 * 3600
  const chezStrava = await fetch(
    `https://www.strava.com/api/v3/athlete/activities?after=${depuis}&per_page=30`,
    { headers: { Authorization: `Bearer ${acces}` } },
  )
  if (!chezStrava.ok) {
    return json({ erreur: `Strava a répondu ${chezStrava.status}.` }, 502)
  }
  const sorties = (await chezStrava.json()) as SortieStrava[]
  if (sorties.length === 0) return json({ importees: 0, vues: 0 })

  const identifiants = sorties.map((s) => s.id)
  const liste = `(${identifiants.join(",")})`

  const [connues, ecartees] = await Promise.all([
    supabase(env, qui.token, `activity?select=strava_id&strava_id=in.${liste}`),
    supabase(
      env, qui.token, `discarded_activity?select=strava_id&strava_id=in.${liste}`
    ),
  ])
  if (!connues.ok || !ecartees.ok) {
    return json({ erreur: "Le miroir n'a pas répondu." }, 502)
  }
  const dejaLa = new Set<number>([
    ...((await connues.json()) as { strava_id: number }[]).map((l) => l.strava_id),
    ...((await ecartees.json()) as { strava_id: number }[]).map((l) => l.strava_id),
  ])

  const lignes = sorties
    .filter((sortie) => !dejaLa.has(sortie.id))
    .map((sortie) => {
      const trace = sortie.map?.summary_polyline
        ? décodePolyline(sortie.map.summary_polyline)
        : []
      return {
        uuid: crypto.randomUUID(),
        user_id: qui.userID,
        strava_id: sortie.id,
        source_raw: "strava",
        name: sortie.name,
        sport_type_raw: SPORTS[sortie.sport_type ?? sortie.type ?? ""] ?? "other",
        start_date: sortie.start_date,
        start_local_date: heureMurale(sortie.start_date_local),
        timezone_identifier: sortie.timezone?.split(" ").pop() ?? null,
        distance: sortie.distance,
        moving_time: Math.round(sortie.moving_time),
        elapsed_time: Math.round(sortie.elapsed_time),
        total_elevation_gain: sortie.total_elevation_gain,
        average_speed: sortie.average_speed,
        max_speed: sortie.max_speed,
        average_heartrate: sortie.average_heartrate ?? null,
        max_heartrate: sortie.max_heartrate ?? null,
        average_watts: sortie.average_watts ?? null,
        average_cadence: sortie.average_cadence ?? null,
        calories: sortie.calories ?? null,
        is_trainer: sortie.trainer ?? false,
        is_commute: sortie.commute ?? false,
        is_manual: sortie.manual ?? false,
        has_track: trace.length > 1,
        simplified_track: trace.length > 1 ? enBytea(trace) : null,
        edited_at: new Date().toISOString(),
      }
    })

  if (lignes.length === 0) return json({ importees: 0, vues: sorties.length })

  const ecriture = await supabase(env, qui.token, "activity", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify(lignes),
  })
  if (!ecriture.ok) {
    return json({ erreur: await ecriture.text() }, 502)
  }
  return json({ importees: lignes.length, vues: sorties.length })
}
