import { useMemo, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { traceDepuisBytea, type Coordonnee } from "./track"
import { memeParcours, signature } from "./parcours"
import { allureOuVitesse, dateCourte } from "./format"
import { couleurDuSport } from "./IconeSport"

/// Les autres sorties sur ce même tracé — les « parcours similaires » du Mac.
///
/// Tout l'intérêt est la comparaison : même parcours, un autre jour, d'autres
/// jambes. Chaque effort reconnu fait une ligne, celle qu'on regarde comprise
/// pour que la colonne d'écart ait son zéro, et le meilleur temps porte la
/// coupe.
///
/// Le tri se fait ici et non en base : reconnaître un parcours demande sa
/// trace, et Postgres ne sait pas comparer deux formes. Ce qui se demande au
/// serveur, c'est la présélection — même sport, longueur à 10 % près — qui
/// ramène une poignée de lignes là où la bibliothèque en compte des centaines.

type Candidate = {
  uuid: string
  name: string
  sport_type_raw: string
  start_local_date: string
  distance: number
  moving_time: number
  average_heartrate: number | null
  simplified_track: string | null
}

type Effort = {
  uuid: string
  nom: string
  date: string
  distance: number
  temps: number
  cardio: number | null
  courante: boolean
}

export function ParcoursSimilaires({
  uuid,
  sport,
  distance,
  temps,
  nom,
  date,
  trace,
  onOuvrir,
}: {
  uuid: string
  sport: string
  distance: number
  temps: number
  nom: string
  date: string
  trace: Coordonnee[]
  onOuvrir: (uuid: string) => void
}) {
  const { data } = useQuery({
    queryKey: ["parcours-candidats", uuid],
    // La présélection ne change pas d'une minute à l'autre : une sortie
    // enregistrée aujourd'hui ne modifie pas le parcours d'il y a trois ans.
    staleTime: 5 * 60 * 1000,
    enabled: distance > 0 && trace.length > 1,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("activity")
        .select(
          "uuid, name, sport_type_raw, start_local_date, distance, moving_time, " +
            "average_heartrate, simplified_track",
        )
        .is("deleted_at", null)
        .eq("sport_type_raw", sport)
        .gte("distance", distance * 0.9)
        .lte("distance", distance * 1.1)
        .neq("uuid", uuid)
      if (error) throw error
      return data as unknown as Candidate[]
    },
  })

  const efforts = useMemo<Effort[]>(() => {
    const reference = signature(trace)
    if (!reference) return []
    const reconnus = (data ?? [])
      .map((candidat) => {
        const forme = signature(traceDepuisBytea(candidat.simplified_track))
        if (!forme) return null
        if (!memeParcours(reference, forme, distance, candidat.distance)) return null
        return {
          uuid: candidat.uuid,
          nom: candidat.name,
          date: candidat.start_local_date,
          distance: candidat.distance,
          temps: candidat.moving_time,
          cardio: candidat.average_heartrate,
          courante: false,
        }
      })
      .filter((e): e is Effort => e !== null)
    if (reconnus.length === 0) return []
    return [
      ...reconnus,
      { uuid, nom, date, distance, temps, cardio: null, courante: true },
    ].sort((a, b) => b.date.localeCompare(a.date))
  }, [data, trace, distance, uuid, nom, date, temps])

  const [tout, setTout] = useState(false)

  if (efforts.length === 0) return null

  const chronos = efforts.map((e) => e.temps).filter((t) => t > 0)
  const meilleur = chronos.length > 0 ? Math.min(...chronos) : null

  return (
    <div className="parcours carte-groupe">
      <div className="tete-description">
        <span className="attenue petit">Parcours similaires</span>
        <span className="attenue petit">
          {efforts.length} sortie{efforts.length > 1 ? "s" : ""} sur ce tracé
        </span>
      </div>

      <Progression efforts={efforts} sport={sport} meilleur={meilleur} />

      <div className="efforts">
        {/* Huit lignes, puis un bouton : la section est une comparaison, pas
            une archive, et une boucle hebdomadaire en accumule des dizaines.
            Le Mac fait défiler les siennes dans un cadre ; sur un téléphone un
            défilement dans le défilement se prend à chaque geste. */}
        {(tout ? efforts : efforts.slice(0, 8)).map((effort) => (
          <button
            key={effort.uuid}
            className={effort.courante ? "effort courant" : "effort"}
            onClick={() => !effort.courante && onOuvrir(effort.uuid)}
            title={effort.courante ? "Cette sortie" : effort.nom}
          >
            <span className="quand">{dateCourte(effort.date)}</span>
            <span className="chrono">
              {chrono(effort.temps)}
              {effort.temps === meilleur && <span className="coupe">🏆</span>}
            </span>
            <span className="rythme">
              {allureOuVitesse(sport, effort.distance, effort.temps)?.valeur ?? "—"}
            </span>
            <span className={ecartClasse(effort, temps)}>{ecart(effort, temps)}</span>
          </button>
        ))}
      </div>
      {efforts.length > 8 && (
        <button className="lien petit" onClick={() => setTout(!tout)}>
          {tout ? "Réduire" : `Voir les ${efforts.length} sorties`}
        </button>
      )}
    </div>
  )
}

/// Un point par tentative, dans le temps.
///
/// Tracée en vitesse moyenne et non en temps, comme sur le Mac : le haut est
/// le rapide, ce qui est le sens dans lequel une courbe de progression se lit.
/// En SVG à la main, pour la raison que `Courbes` donne déjà — la moindre
/// bibliothèque de graphiques pèserait plus que tout le reste.
function Progression({
  efforts,
  sport,
  meilleur,
}: {
  efforts: Effort[]
  sport: string
  meilleur: number | null
}) {
  const toutes = efforts
    .filter((e) => e.temps > 0 && e.distance > 0)
    .sort((a, b) => a.date.localeCompare(b.date))
  // Les douze dernières, pas les quarante-trois.
  //
  // Le Mac fait défiler sa courbe horizontalement pour n'en montrer qu'une
  // dizaine à la fois ; sur un téléphone un défilement horizontal dans une
  // page qui défile déjà se déclenche à chaque geste. Couper à la fin revient
  // au même à l'ouverture — c'est là que le Mac se place — et une boucle
  // hebdomadaire de quarante-trois sorties tenait sinon en un seul zigzag
  // gris. Le compte complet reste dans la liste dessous.
  const points = toutes.slice(-12)
  // Sous trois tentatives il n'y a pas de progression à montrer, seulement
  // deux points reliés — la liste le dit déjà mieux.
  if (points.length < 3) return null

  const L = 300
  const H = 76
  const marge = 6
  const vitesses = points.map((p) => p.distance / p.temps)
  const min = Math.min(...vitesses)
  const max = Math.max(...vitesses)
  // Depuis la plus lente et non depuis zéro : les écarts se comptent en
  // secondes au kilomètre, et une échelle partant de zéro les aplatit en une
  // seule droite.
  const etendue = max - min || 1
  const dates = points.map((p) => new Date(p.date).getTime())
  const debut = dates[0]
  const duree = dates[dates.length - 1] - debut || 1

  const x = (i: number) => marge + ((dates[i] - debut) / duree) * (L - 2 * marge)
  const y = (i: number) => H - marge - ((vitesses[i] - min) / etendue) * (H - 2 * marge)

  return (
    <svg className="progression" viewBox={`0 0 ${L} ${H}`} preserveAspectRatio="none">
      <polyline
        points={points.map((_, i) => `${x(i)},${y(i)}`).join(" ")}
        fill="none"
        stroke="var(--trait)"
        strokeWidth="1.5"
      />
      {points.map((point, i) => (
        <circle
          key={point.uuid}
          cx={x(i)}
          cy={y(i)}
          r={point.courante ? 5 : 3.5}
          fill={
            point.courante
              ? couleurDuSport(sport)
              : point.temps === meilleur
                ? "var(--or)"
                : "var(--texte-3)"
          }
        >
          <title>
            {`${dateCourte(point.date)} — ${chrono(point.temps)} · ${
              allureOuVitesse(sport, point.distance, point.temps)?.valeur ?? ""
            }`}
          </title>
        </circle>
      ))}
    </svg>
  )
}

/// « 1 h 04 », « 38 min » — `Format.durationCompact` du Mac, à la lettre.
///
/// Les secondes sont du bruit quand on compare des sorties d'un coup d'œil.
/// Arrondi et non tronqué, pour que 59 min 45 s se lise « 1 h 00 » ici comme
/// là-bas.
function chrono(secondes: number): string {
  if (secondes <= 0) return "—"
  const minutes = Math.round(secondes / 60)
  if (minutes < 1) return "< 1 min"
  if (minutes < 60) return `${minutes} min`
  return `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, "0")}`
}

/// L'écart signé face à la sortie ouverte : en vert quand l'autre a été plus
/// rapide — quelque chose à aller chercher — en rouge quand c'est celle-ci qui
/// gagne.
function ecart(effort: Effort, reference: number): string {
  if (effort.courante || effort.temps <= 0 || reference <= 0) return "—"
  const delta = effort.temps - reference
  return delta <= 0 ? `−${chrono(-delta)}` : `+${chrono(delta)}`
}

function ecartClasse(effort: Effort, reference: number): string {
  if (effort.courante || effort.temps <= 0 || reference <= 0) return "delta"
  return effort.temps - reference <= 0 ? "delta mieux" : "delta moins"
}
