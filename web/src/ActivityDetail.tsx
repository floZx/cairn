import { Suspense, lazy, useMemo } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { nomDuSport } from "./sports"
import { dateCourte, denivele, distance, duree } from "./format"
import { traceDepuisBytea } from "./track"
// Chargée à la demande : MapLibre pèse à lui seul les quatre cinquièmes du
// paquet, et le journal — l'écran qu'on ouvre le plus depuis un téléphone —
// ne s'en sert jamais. Sans ce découpage, lire une note coûtait le
// téléchargement d'un moteur de cartographie.
const Carte = lazy(() => import("./Carte").then((m) => ({ default: m.Carte })))
import { Markdown } from "./markdown"

type Fiche = {
  uuid: string
  name: string
  sport_type_raw: string
  start_local_date: string
  distance: number
  moving_time: number
  total_elevation_gain: number
  average_heartrate: number | null
  max_heartrate: number | null
  average_watts: number | null
  calories: number | null
  activity_description: string | null
  simplified_track: string | null
}

function Chiffre({ valeur, etiquette }: { valeur: string; etiquette: string }) {
  return (
    <div className="chiffre">
      <div className="valeur">{valeur}</div>
      <div className="etiquette">{etiquette}</div>
    </div>
  )
}

/// L'allure a du sens à pied, la vitesse à vélo. Afficher les deux serait
/// afficher une fois de trop, et afficher la mauvaise rend la fiche illisible
/// pour le sport qu'on regarde.
function allureOuVitesse(sport: string, metres: number, secondes: number) {
  if (metres <= 0 || secondes <= 0) return null
  const aPied = ["run", "trailRun", "walk", "hike"].includes(sport)
  if (aPied) {
    const secondesParKm = secondes / (metres / 1000)
    const minutes = Math.floor(secondesParKm / 60)
    const reste = Math.round(secondesParKm % 60)
    return {
      valeur: `${minutes}′${String(reste).padStart(2, "0")}″`,
      etiquette: "Allure / km",
    }
  }
  const kmh = metres / 1000 / (secondes / 3600)
  return {
    valeur: `${kmh.toLocaleString("fr-FR", { maximumFractionDigits: 1 })} km/h`,
    etiquette: "Vitesse",
  }
}

export function ActivityDetail({ uuid, onRetour }: { uuid: string; onRetour: () => void }) {
  const { data, error, isPending } = useQuery({
    queryKey: ["activite", uuid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("activity")
        .select(
          "uuid, name, sport_type_raw, start_local_date, distance, moving_time, " +
            "total_elevation_gain, average_heartrate, max_heartrate, average_watts, " +
            "calories, activity_description, simplified_track",
        )
        .eq("uuid", uuid)
        .single()
      if (error) throw error
      return data as unknown as Fiche
    },
  })

  // Au-dessus des retours anticipés, obligatoirement : un hook doit s'exécuter
  // à chaque rendu, et le placer plus bas en faisait apparaître un de plus une
  // fois les données arrivées — ce que React refuse net.
  //
  // Mémoïsée, et ce n'est pas une optimisation : `Carte` recrée sa carte quand
  // cette référence change, et un tableau fabriqué dans le JSX en est un
  // nouveau à chaque rendu.
  const trace = useMemo(
    () => traceDepuisBytea(data?.simplified_track ?? null),
    [data?.simplified_track],
  )

  if (isPending) return <p className="attenue">Chargement…</p>
  if (error) return <p className="erreur">{(error as Error).message}</p>

  const rythme = allureOuVitesse(data.sport_type_raw, data.distance, data.moving_time)

  return (
    <>
      <button className="retour" onClick={onRetour}>
        ‹ Activités
      </button>
      <div className="entete-fiche">
        <h2>{data.name}</h2>
        <div className="attenue petit">
          {nomDuSport(data.sport_type_raw)} · {dateCourte(data.start_local_date)}
        </div>
      </div>

      <div className="chiffres carte-groupe">
        <Chiffre valeur={distance(data.distance)} etiquette="Distance" />
        <Chiffre valeur={duree(data.moving_time)} etiquette="Temps" />
        <Chiffre valeur={denivele(data.total_elevation_gain)} etiquette="D+" />
        {rythme && <Chiffre valeur={rythme.valeur} etiquette={rythme.etiquette} />}
        {data.average_heartrate != null && (
          <Chiffre
            valeur={`${Math.round(data.average_heartrate)} bpm`}
            etiquette="Cardio moyen"
          />
        )}
        {data.average_watts != null && (
          <Chiffre valeur={`${Math.round(data.average_watts)} W`} etiquette="Puissance" />
        )}
        {data.calories != null && (
          <Chiffre valeur={`${Math.round(data.calories)} kcal`} etiquette="Calories" />
        )}
      </div>

      <Suspense fallback={<div className="carte-trace" />}>
        <Carte trace={trace} />
      </Suspense>

      {data.activity_description && (
        <div className="description carte-groupe">
          <Markdown texte={data.activity_description} />
        </div>
      )}
    </>
  )
}
