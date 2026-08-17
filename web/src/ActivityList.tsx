import { useEffect, useRef } from "react"
import { useInfiniteQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { nomDuSport } from "./sports"
import { dateCourte, denivele, distance, duree } from "./format"

/// Une page de cinquante : assez pour remplir plus d'un écran de téléphone
/// d'un coup, assez peu pour que la première s'affiche tout de suite. Les 852
/// activités en une seule requête feraient attendre plusieurs secondes pour
/// montrer les six premières.
const PAR_PAGE = 50

type Activite = {
  uuid: string
  name: string
  sport_type_raw: string
  start_local_date: string
  distance: number
  moving_time: number
  total_elevation_gain: number
}

async function chargerPage(depuis: number) {
  const { data, error } = await supabase
    .from("activity")
    .select(
      "uuid, name, sport_type_raw, start_local_date, distance, moving_time, total_elevation_gain",
    )
    // Les lignes effacées en douceur portent une date ici ; elles n'ont pas
    // disparu de la table, c'est au lecteur de les écarter.
    .is("deleted_at", null)
    // `start_local_date`, pas `start_date` : l'heure du lieu où la sortie a eu
    // lieu, qui est celle sous laquelle on s'en souvient.
    .order("start_local_date", { ascending: false })
    .range(depuis, depuis + PAR_PAGE - 1)
  if (error) throw error
  return data as Activite[]
}

export function ActivityList({ onOuvrir }: { onOuvrir: (uuid: string) => void }) {
  const { data, error, isPending, fetchNextPage, hasNextPage, isFetchingNextPage } =
    useInfiniteQuery({
      queryKey: ["activites"],
      queryFn: ({ pageParam }) => chargerPage(pageParam),
      initialPageParam: 0,
      getNextPageParam: (derniere, toutes) =>
        derniere.length < PAR_PAGE ? undefined : toutes.length * PAR_PAGE,
    })

  // Charge la suite quand la sentinelle entre dans le champ, plutôt qu'à un
  // bouton : sur un téléphone, on fait défiler, on ne vise pas.
  const sentinelle = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const cible = sentinelle.current
    if (!cible || !hasNextPage) return
    const observateur = new IntersectionObserver((entrees) => {
      if (entrees[0].isIntersecting) fetchNextPage()
    })
    observateur.observe(cible)
    return () => observateur.disconnect()
  }, [hasNextPage, fetchNextPage])

  if (isPending) return <p className="attenue">Chargement…</p>
  if (error) return <p className="erreur">{(error as Error).message}</p>

  const activites = data.pages.flat()
  if (activites.length === 0) {
    return <p className="attenue">Aucune activité — le Mac n'a peut-être rien encore poussé.</p>
  }

  return (
    <>
      <ul className="liste">
        {activites.map((a) => (
          <li key={a.uuid} className="ligne" onClick={() => onOuvrir(a.uuid)}>
            <div className="ligne-tete">
              <span className="titre">{a.name}</span>
              <span className="attenue petit">{dateCourte(a.start_local_date)}</span>
            </div>
            <div className="attenue petit">
              {nomDuSport(a.sport_type_raw)} · {distance(a.distance)} ·{" "}
              {duree(a.moving_time)} · {denivele(a.total_elevation_gain)}
            </div>
          </li>
        ))}
      </ul>
      <div ref={sentinelle} />
      {isFetchingNextPage && <p className="attenue">Chargement…</p>}
    </>
  )
}
