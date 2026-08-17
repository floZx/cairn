import { useEffect, useRef, useState } from "react"
import { useInfiniteQuery, useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { nomDuSport } from "./sports"
import { dateCourte, denivele, distance, duree } from "./format"
import { Feuille } from "./Chrome"
import { Filtres } from "./Filtres"
import { AUCUN, bornes, estActif, passeLeSecondFiltre, resume, type Filtre } from "./criteres"
import type { SourceEtiquettes } from "./etiquettes"

/// Une page de cinquante : assez pour remplir plus d'un écran de téléphone
/// d'un coup, assez peu pour que la première s'affiche tout de suite. Les 852
/// activités en une seule requête feraient attendre plusieurs secondes pour
/// montrer les six premières.
const PAR_PAGE = 50

/// Les colonnes du second filtre voyagent avec les autres : les étiquettes se
/// déduisent de quatre d'entre elles, et les redemander ligne par ligne ferait
/// une requête par activité affichée.
type Activite = SourceEtiquettes & {
  uuid: string
  name: string
  sport_type_raw: string
  start_local_date: string
  distance: number
  moving_time: number
  total_elevation_gain: number
}

const COLONNES =
  "uuid, name, sport_type_raw, start_local_date, distance, moving_time, " +
  "total_elevation_gain, source_raw, workout_type, workout_label_raw, " +
  "edited_fields, is_favorite, is_commute, is_trainer, is_manual"

/// Applique à une requête tout ce que le filtre sait dire en SQL.
///
/// Le reste — étiquettes et dénivelé par kilomètre — se règle sur les lignes
/// reçues, exactement comme le Mac le fait : une division et une règle à trois
/// colonnes ne s'expriment pas ici.
function restreindre<T>(requete: T, f: Filtre, maintenant = new Date()): T {
  // Le typage de PostgREST se perd à travers une fonction ; les appels
  // s'enchaînent sur le même objet, ce que ce `any` local dit sans le
  // propager.
  let q = requete as any
  const texte = f.recherche.trim()
  // `ilike` avec des jokers : `localizedStandardContains` du Mac ignore la
  // casse et les accents, et c'est le plus proche que Postgres offre sans
  // extension.
  if (texte) q = q.ilike("name", `%${texte}%`)
  if (f.sports.length) q = q.in("sport_type_raw", f.sports)
  const { debut, fin } = bornes(f, maintenant)
  if (debut) q = q.gte("start_local_date", debut.toISOString())
  if (fin) q = q.lt("start_local_date", fin.toISOString())
  if (f.distanceMin != null) q = q.gte("distance", f.distanceMin * 1000)
  if (f.distanceMax != null) q = q.lte("distance", f.distanceMax * 1000)
  if (f.deniveleMin != null) q = q.gte("total_elevation_gain", f.deniveleMin)
  if (f.deniveleMax != null) q = q.lte("total_elevation_gain", f.deniveleMax)
  return q as T
}

async function chargerPage(depuis: number, filtre: Filtre) {
  const { data, error } = await restreindre(
    supabase
      .from("activity")
      .select(COLONNES)
      // Les lignes effacées en douceur portent une date ici ; elles n'ont pas
      // disparu de la table, c'est au lecteur de les écarter.
      .is("deleted_at", null),
    filtre,
  )
    // `start_local_date`, pas `start_date` : l'heure du lieu où la sortie a eu
    // lieu, qui est celle sous laquelle on s'en souvient.
    .order("start_local_date", { ascending: false })
    .range(depuis, depuis + PAR_PAGE - 1)
  if (error) throw error
  return data as unknown as Activite[]
}

export function ActivityList({ onOuvrir }: { onOuvrir: (uuid: string) => void }) {
  const [filtre, setFiltre] = useState<Filtre>(AUCUN)
  const [feuilleOuverte, setFeuilleOuverte] = useState(false)
  // Le texte tapé et le filtre appliqué sont deux choses : sans ce délai,
  // chaque lettre relancerait une requête et referait toutes les pages.
  const [saisie, setSaisie] = useState("")
  useEffect(() => {
    const t = setTimeout(() => setFiltre((f) => ({ ...f, recherche: saisie })), 300)
    return () => clearTimeout(t)
  }, [saisie])

  const { data, error, isPending, fetchNextPage, hasNextPage, isFetchingNextPage } =
    useInfiniteQuery({
      // Le filtre entre dans la clé : deux filtres différents sont deux listes
      // différentes, et TanStack garde la précédente pendant que la suivante
      // arrive plutôt que de vider l'écran.
      queryKey: ["activites", filtre],
      queryFn: ({ pageParam }) => chargerPage(pageParam, filtre),
      initialPageParam: 0,
      getNextPageParam: (derniere, toutes) =>
        derniere.length < PAR_PAGE ? undefined : toutes.length * PAR_PAGE,
    })

  /// Combien d'activités le filtre laisse passer — le compte que la feuille
  /// affiche pendant qu'on tâtonne.
  ///
  /// Une requête à part, `head` et `count` seulement : demander le compte à la
  /// liste paginée voudrait dire la parcourir en entier. Le second filtre lui
  /// échappe, comme il échappe à SQL — le compte est donc un majorant, ce que
  /// la feuille ne prétend pas cacher.
  const compte = useQuery({
    queryKey: ["compte-activites", filtre],
    enabled: feuilleOuverte,
    queryFn: async () => {
      const { count, error } = await restreindre(
        supabase
          .from("activity")
          .select("uuid", { count: "exact", head: true })
          .is("deleted_at", null),
        filtre,
      )
      if (error) throw error
      return count ?? 0
    },
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

  const entete = (
    <>
      {feuilleOuverte && (
        <Feuille titre="Filtres" onFerme={() => setFeuilleOuverte(false)}>
          <Filtres
            filtre={filtre}
            onChange={setFiltre}
            onFerme={() => setFeuilleOuverte(false)}
            compte={compte.data ?? null}
          />
        </Feuille>
      )}
      <div className="barre-recherche">
        <input
          type="search"
          className="recherche"
          value={saisie}
          onChange={(e) => setSaisie(e.target.value)}
          placeholder="Rechercher une sortie…"
        />
        <button
          className={estActif(filtre) ? "bouton-filtre actif" : "bouton-filtre"}
          onClick={() => setFeuilleOuverte(true)}
          aria-label="Filtres"
        >
          <svg
            width="20"
            height="20"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.9"
            strokeLinecap="round"
            aria-hidden
          >
            <path d="M4 7h16M7 12h10M10 17h4" />
          </svg>
        </button>
      </div>
      {/* Une liste raccourcie sans raison visible déroute : ce résumé dit ce
          qui la restreint, comme la barre de titre du Mac. */}
      {resume(filtre) && (
        <button className="resume-filtre" onClick={() => setFeuilleOuverte(true)}>
          {resume(filtre)}
        </button>
      )}
    </>
  )

  if (isPending) {
    return (
      <>
        {entete}
        <p className="attenue">Chargement…</p>
      </>
    )
  }
  if (error) {
    return (
      <>
        {entete}
        <p className="erreur">{(error as Error).message}</p>
      </>
    )
  }

  // Le second passage, sur les lignes déjà rétrécies par la requête. Une page
  // peut en ressortir vide ; la sentinelle reste alors visible et la suivante
  // se charge d'elle-même.
  const activites = data.pages.flat().filter((a) => passeLeSecondFiltre(filtre, a))
  if (activites.length === 0 && !hasNextPage) {
    return (
      <>
        {entete}
        <p className="attenue">
          {estActif(filtre)
            ? "Aucune activité ne correspond."
            : "Aucune activité — le Mac n'a peut-être rien encore poussé."}
        </p>
      </>
    )
  }

  return (
    <>
      {entete}
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
