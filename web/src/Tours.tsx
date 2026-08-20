import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { allureOuVitesse, denivele, distance, dureePrecise } from "./format"

/// Les tours d'une sortie — les « intervalles » du Mac.
///
/// Ils étaient dans le miroir depuis toujours et personne ne les lisait ici :
/// une sortie à fractionné montrait ses courbes et taisait ses répétitions,
/// qui sont précisément ce qu'on vient voir. Signalé le 20 août 2026.
///
/// Un tableau sur le Mac, une ligne par tour ici : six colonnes ne tiennent
/// pas dans 375 points, et une ligne se lit d'un coup — le numéro, ce qu'il a
/// duré, et l'allure qu'on y tenait, qui est la seule chose qu'on compare
/// vraiment d'un tour à l'autre.
type Tour = {
  uuid: string
  lap_index: number
  distance: number
  moving_time: number
  total_elevation_gain: number
  average_heartrate: number | null
}

export function Tours({ uuid, sport }: { uuid: string; sport: string }) {
  const { data } = useQuery({
    queryKey: ["tours", uuid],
    // La même règle que les courbes, et pour la même raison : un tour ne
    // change plus une fois écrit, mais son **absence** change — le téléphone
    // peut avoir importé la sortie avant que le Mac ne pose ses tours.
    staleTime: (requete) => (requete.state.data?.length ? Infinity : 0),
    queryFn: async () => {
      const { data, error } = await supabase
        .from("lap")
        .select(
          "uuid, lap_index, distance, moving_time, total_elevation_gain, average_heartrate",
        )
        .eq("activity_uuid", uuid)
        .is("deleted_at", null)
        .order("lap_index")
      if (error) throw error
      return data as Tour[]
    },
  })

  // Un tour unique n'en est pas un : Strava en pose toujours au moins un, qui
  // recouvre la sortie entière et ne dit rien de plus que la fiche au-dessus.
  if (!data || data.length < 2) return null

  const meilleur = Math.min(
    ...data.filter((t) => t.distance > 0 && t.moving_time > 0).map((t) => t.moving_time / t.distance),
  )

  return (
    <div className="tours carte-groupe">
      <div className="tete-description">
        <span className="attenue petit">Tours</span>
        <span className="attenue petit">{data.length}</span>
      </div>
      {data.map((tour) => {
        const rythme = allureOuVitesse(sport, tour.distance, tour.moving_time)
        // Le plus rapide se marque, comme le record d'un parcours : dans une
        // série de six côtes, savoir laquelle on a tenue le mieux est la
        // question qu'on se pose.
        const leMeilleur =
          tour.distance > 0 &&
          tour.moving_time > 0 &&
          tour.moving_time / tour.distance === meilleur
        return (
          <div className={leMeilleur ? "tour meilleur" : "tour"} key={tour.uuid}>
            <span className="numero">{tour.lap_index}</span>
            <span className="mesure">{distance(tour.distance)}</span>
            <span className="mesure">{dureePrecise(tour.moving_time)}</span>
            <span className="mesure rythme">{rythme?.valeur ?? "—"}</span>
            <span className="mesure attenue">
              {tour.average_heartrate
                ? `${Math.round(tour.average_heartrate)} bpm`
                : denivele(tour.total_elevation_gain)}
            </span>
          </div>
        )
      })}
    </div>
  )
}
