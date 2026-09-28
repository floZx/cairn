/// La météo au départ d'une sortie, d'après Open-Meteo — `WeatherHistory` du
/// Mac, la même requête et le même mélange des deux heures.
///
/// Le Mac la garde une fois lue ; ici rien ne la garde au-delà de la session :
/// elle ne vit pas dans Supabase, et le service est gratuit et sans clé.

export type Releve = {
  temperature: number
  ressenti: number
  humidite: number
  vent: number
  directionVent: number
  code: number
  nuages: number
  precipitations: number
  jour: boolean
}

const CHAMPS = [
  "temperature_2m", "apparent_temperature", "relative_humidity_2m",
  "wind_speed_10m", "wind_direction_10m", "weather_code", "cloud_cover",
  "precipitation", "is_day",
]

/// Deux services derrière une même API : les prévisions telles qu'émises,
/// heure par heure depuis 2022 ; avant, la réanalyse ERA5.
function url(latitude: number, longitude: number, date: Date): string {
  const recent = date.getTime() >= Date.UTC(2022, 0, 1)
  const base = recent
    ? "https://historical-forecast-api.open-meteo.com/v1/forecast"
    : "https://archive-api.open-meteo.com/v1/archive"
  const jour = (decalage: number) =>
    new Date(date.getTime() + decalage).toISOString().slice(0, 10)
  // La veille et le lendemain aussi : un départ à 00 h 30 UTC se mélange avec
  // l'heure d'avant.
  const params = new URLSearchParams({
    latitude: latitude.toFixed(3),
    longitude: longitude.toFixed(3),
    start_date: jour(-86_400_000),
    end_date: jour(86_400_000),
    hourly: CHAMPS.join(","),
    timezone: "GMT",
    timeformat: "unixtime",
    wind_speed_unit: "kmh",
  })
  return `${base}?${params}`
}

export async function releve(latitude: number, longitude: number, date: Date): Promise<Releve | null> {
  const reponse = await fetch(url(latitude, longitude, date))
  if (!reponse.ok) throw new Error(`Open-Meteo a répondu ${reponse.status}.`)
  return lire(await reponse.json(), date)
}

/// Les deux heures autour du départ : les chiffres mélangés linéairement,
/// l'heure la plus proche pour ce qui ne se moyenne pas — le code, le jour ou
/// la nuit, la direction du vent, et la couverture nuageuse.
function lire(json: { hourly?: Record<string, (number | null)[]> }, date: Date): Releve | null {
  const heures = json.hourly
  const temps = heures?.time as number[] | undefined
  if (!heures || !temps || temps.length === 0) return null

  const t = date.getTime() / 1000
  let apres = temps.findIndex((x) => x >= t)
  if (apres < 0) apres = temps.length - 1
  const avant = temps[apres] > t && apres > 0 ? apres - 1 : apres
  const ecart = temps[apres] - temps[avant]
  const f = ecart > 0 ? (t - temps[avant]) / ecart : 0
  const proche = f < 0.5 ? avant : apres

  const melange = (cle: string): number | null => {
    const a = heures[cle]?.[avant], b = heures[cle]?.[apres]
    return a == null || b == null ? null : a + (b - a) * f
  }
  const prend = (cle: string): number | null => heures[cle]?.[proche] ?? null

  const temperature = melange("temperature_2m")
  if (temperature == null) return null
  return {
    temperature,
    ressenti: melange("apparent_temperature") ?? temperature,
    humidite: melange("relative_humidity_2m") ?? 0,
    vent: melange("wind_speed_10m") ?? 0,
    directionVent: prend("wind_direction_10m") ?? 0,
    code: prend("weather_code") ?? 0,
    nuages: prend("cloud_cover") ?? 0,
    precipitations: prend("precipitation") ?? 0,
    jour: (prend("is_day") ?? 1) !== 0,
  }
}

/// Le ciel dit et dessiné — `WeatherSky`. La pluie, la neige, le brouillard et
/// l'orage d'après le code OMM ; le ciel lui-même d'après la couverture, plus
/// fine.
export function ciel(r: Releve): { libelle: string; symbole: string } {
  const c = r.code
  const d = (jour: string, nuit: string) => (r.jour ? jour : nuit)
  if (c === 45 || c === 48) return { libelle: "Brouillard", symbole: "cloud.fog" }
  if (c >= 51 && c <= 57) return { libelle: "Bruine", symbole: "cloud.drizzle" }
  if (c === 61 || c === 63 || c === 66) return { libelle: "Pluie", symbole: "cloud.rain" }
  if (c === 65 || c === 67) return { libelle: "Forte pluie", symbole: "cloud.heavyrain" }
  if (c >= 71 && c <= 77) return { libelle: "Neige", symbole: "cloud.snow" }
  if (c >= 80 && c <= 82) return { libelle: "Averses", symbole: d("cloud.sun.rain", "cloud.moon.rain") }
  if (c === 85 || c === 86) return { libelle: "Averses de neige", symbole: "cloud.snow" }
  if (c >= 95 && c <= 99) return { libelle: "Orage", symbole: "cloud.bolt.rain" }
  if (r.nuages < 20) return { libelle: "Ciel dégagé", symbole: d("sun.max", "moon.stars") }
  if (r.nuages < 50) return { libelle: "Quelques nuages", symbole: d("cloud.sun", "cloud.moon") }
  if (r.nuages < 85) return { libelle: "Nuageux", symbole: d("cloud.sun", "cloud.moon") }
  return { libelle: "Couvert", symbole: "cloud" }
}

/// D'où vient le vent, sur la rose française à seize aires : « SSO ».
export function rose(degres: number): string {
  const aires = [
    "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
    "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO",
  ]
  return aires[Math.round((((degres % 360) + 360) % 360) / 22.5) % 16]
}
