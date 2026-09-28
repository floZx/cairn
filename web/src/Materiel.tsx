import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { distance } from "./format"
import { Symbole } from "./IconeSport"
import { ciel, releve, rose } from "./meteo"

/// Le matériel et la météo d'une sortie, l'un sous l'autre — la paire
/// `ActivityGearRow` et `ActivityWeatherView` du Mac. Ce ne sont pas des
/// chiffres de la sortie, mais ce avec quoi et dans quoi elle s'est faite.

type Materiel = {
  name: string
  brand_name: string | null
  model_name: string | null
  is_bike: boolean
}

export function MaterielEtMeteo({
  gearID,
  depart,
  debut,
  homeTrainer,
}: {
  gearID: string | null
  depart: [latitude: number, longitude: number] | null
  debut: string
  homeTrainer: boolean
}) {
  const materiel = useQuery({
    queryKey: ["materiel", gearID],
    enabled: gearID != null,
    queryFn: () => chargerMateriel(gearID!),
  })

  // Seulement une fois la sortie passée, avec une heure de marge : l'archive
  // se remplit derrière l'horloge. Un échec ne montre rien.
  const date = new Date(debut)
  const meteo = useQuery({
    queryKey: ["meteo", depart, debut],
    enabled: depart != null && !homeTrainer && date.getTime() < Date.now() - 3_600_000,
    queryFn: () => releve(depart![0], depart![1], date),
    staleTime: Infinity,
    retry: 1,
  })

  if (!materiel.data && !meteo.data) return null

  return (
    <div className="materiel-meteo">
      {materiel.data && (
        <div className="ligne-contexte carte-groupe">
          <Symbole nom={materiel.data.materiel.is_bike ? "bicycle" : "shoe"} taille={26} couleur="var(--texte-2)" />
          <div>
            <div className="titre">{materiel.data.materiel.name}</div>
            <div className="detail">
              {detail(materiel.data.materiel) ??
                (materiel.data.materiel.is_bike ? "Vélo" : "Chaussures")}
              {" · "}
              {distance(materiel.data.total)}
            </div>
          </div>
        </div>
      )}
      {meteo.data && (() => {
        const r = meteo.data
        const { libelle, symbole } = ciel(r)
        const chiffres = [
          `${degres(r.temperature)}, ressenti ${degres(r.ressenti)}`,
          `humidité ${Math.round(r.humidite)} %`,
          `vent ${Math.round(r.vent)} km/h ${rose(r.directionVent)}`,
        ]
        if (r.precipitations >= 0.1) {
          chiffres.push(`${r.precipitations.toFixed(1).replace(".", ",")} mm/h`)
        }
        return (
          <div className="ligne-contexte carte-groupe">
            <Symbole nom={symbole} taille={26} couleur="var(--texte-2)" />
            <div>
              <div className="titre">{libelle}</div>
              <div className="detail">{chiffres.join(" · ")}</div>
            </div>
          </div>
        )
      })()}
    </div>
  )
}

/// Les kilomètres sont ceux des sorties de la bibliothèque, pas le
/// `total_distance` que Strava tient : il dérivait, 1 043 km pour une paire
/// qui en porte 1 405. Le même compte que le Mac et les statistiques.
async function chargerMateriel(gearID: string) {
  const [materiel, sorties] = await Promise.all([
    supabase
      .from("gear")
      .select("name, brand_name, model_name, is_bike")
      .eq("strava_id", gearID)
      .is("deleted_at", null)
      .maybeSingle(),
    supabase.from("activity").select("distance").eq("gear_id", gearID).is("deleted_at", null),
  ])
  if (materiel.error) throw materiel.error
  if (sorties.error) throw sorties.error
  if (!materiel.data) return null
  const total = (sorties.data as { distance: number }[]).reduce((s, a) => s + a.distance, 0)
  return { materiel: materiel.data as Materiel, total }
}

/// La marque et le modèle quand le nom ne les dit pas déjà.
function detail(m: Materiel): string | null {
  const nom = m.name.toLowerCase()
  const marque = [m.brand_name, m.model_name]
    .map((s) => s?.trim() ?? "")
    .filter((s) => s !== "" && !nom.includes(s.toLowerCase()))
    .join(" ")
  return marque === "" ? null : marque
}

function degres(celsius: number): string {
  return `${Math.round(celsius)} °C`
}
