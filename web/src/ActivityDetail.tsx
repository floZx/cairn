import { Suspense, lazy, useMemo, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { cadenceDuSport, nomDuSport } from "./sports"
import { IconeSport, couleurDuSport } from "./IconeSport"
import { allureOuVitesse, dateEtHeure, denivele, distance, duree } from "./format"
import { traceDepuisBytea } from "./track"
// Chargée à la demande : MapLibre pèse à lui seul les quatre cinquièmes du
// paquet, et le journal — l'écran qu'on ouvre le plus depuis un téléphone —
// ne s'en sert jamais. Sans ce découpage, lire une note coûtait le
// téléchargement d'un moteur de cartographie.
const Carte = lazy(() => import("./Carte").then((m) => ({ default: m.Carte })))
import { Markdown } from "./markdown"
import { Courbes } from "./Courbes"
import { NoteActivite } from "./NoteActivite"
import { Feuille } from "./Chrome"
import { NOMS, etiquettesDe, type SourceEtiquettes } from "./etiquettes"

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
  average_cadence: number | null
  calories: number | null
  activity_description: string | null
  edited_fields: string[] | null
  source_raw: string
  workout_type: number | null
  workout_label_raw: string | null
  is_favorite: boolean
  is_commute: boolean
  is_trainer: boolean
  is_manual: boolean
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

export function ActivityDetail({ uuid }: { uuid: string }) {
  const [enEdition, setEnEdition] = useState(false)
  const { data, error, isPending } = useQuery({
    queryKey: ["activite", uuid],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("activity")
        .select(
          "uuid, name, sport_type_raw, start_local_date, distance, moving_time, " +
            "total_elevation_gain, average_heartrate, max_heartrate, average_watts, " +
            "average_cadence, calories, activity_description, edited_fields, " +
            "source_raw, workout_type, workout_label_raw, is_favorite, is_commute, " +
            "is_trainer, is_manual, simplified_track",
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
      {/* Le halo du sport, la date entière et les pastilles. Le dégradé
          s'éteint à 45 % de la hauteur, comme `SportWash`. */}
      <div
        className="entete-fiche"
        style={
          {
            "--teinte-sport": couleurDuSport(data.sport_type_raw),
          } as React.CSSProperties
        }
      >
        <h2>{data.name}</h2>
        <div className="attenue petit">{dateEtHeure(data.start_local_date)}</div>
        <div className="etiquettes">
          <span className="etiquette-tag sport">
            <IconeSport sport={data.sport_type_raw} taille={14} />
            {nomDuSport(data.sport_type_raw)}
          </span>
          {etiquettesDe(data as unknown as SourceEtiquettes).map((m) => (
            <span className="etiquette-tag" key={m}>
              {NOMS[m]}
            </span>
          ))}
          {/* D'où vient cette sortie : le Mac le dit aussi, et cela distingue
              une activité importée d'une saisie à la main. */}
          <span className="etiquette-tag attenue">
            {data.source_raw === "strava" ? "Strava" : "Manuelle"}
          </span>
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
        {data.average_cadence != null && data.average_cadence > 0 && (
          <Chiffre
            valeur={(() => {
              const { facteur, unite } = cadenceDuSport(data.sport_type_raw)
              return `${Math.round(data.average_cadence * facteur)} ${unite}`
            })()}
            etiquette="Cadence"
          />
        )}
        {data.calories != null && (
          <Chiffre valeur={`${Math.round(data.calories)} kcal`} etiquette="Calories" />
        )}
      </div>

      <Suspense fallback={<div className="carte-trace" />}>
        <Carte trace={trace} />
      </Suspense>

      <div className="description carte-groupe">
        <div className="tete-description">
          <span className="attenue petit">Note</span>
          <button className="lien petit" onClick={() => setEnEdition(true)}>
            {data.activity_description ? "Modifier" : "Écrire"}
          </button>
        </div>
        {data.activity_description ? (
          <Markdown texte={data.activity_description} />
        ) : (
          <p className="attenue">Rien de noté sur cette sortie.</p>
        )}
      </div>

      <Courbes activiteUUID={uuid} />

      {enEdition && (
        <Feuille titre="Note de sortie" onFerme={() => setEnEdition(false)}>
          <NoteActivite
            uuid={uuid}
            texte={data.activity_description ?? ""}
            champsEdites={data.edited_fields ?? []}
            onFerme={() => setEnEdition(false)}
          />
        </Feuille>
      )}
    </>
  )
}
