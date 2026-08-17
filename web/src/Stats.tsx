import { useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { nomDuSport } from "./sports"
import { denivele, distance, duree } from "./format"

/// Les statistiques, portées d'`ActivityStatistics`.
///
/// Sa règle de fond est reprise telle quelle, parce qu'elle décide de toute la
/// mise en page : **additionner des sports différents ne dit rien**. Une
/// distance totale mêlant vélo, course et natation n'informe sur rien. Les
/// chiffres qui s'additionnent honnêtement — le nombre de sorties, le temps,
/// le dénivelé — sont donc les seuls globaux, et la distance est rendue sport
/// par sport.

type Periode = "3mois" | "6mois" | "12mois" | "annee"

const PERIODES: { clef: Periode; nom: string; mois: number }[] = [
  { clef: "3mois", nom: "3 mois", mois: 3 },
  { clef: "6mois", nom: "6 mois", mois: 6 },
  { clef: "12mois", nom: "12 mois", mois: 12 },
  { clef: "annee", nom: "Année en cours", mois: 0 },
]

type Ligne = {
  uuid: string
  name: string
  sport_type_raw: string
  start_local_date: string
  distance: number
  moving_time: number
  total_elevation_gain: number
}

/// Le début de la fenêtre, et celui de la fenêtre précédente.
///
/// « L'année en cours » se compare à l'année précédente entière ; les autres à
/// la tranche immédiatement avant elles, ce que veut dire « les trois mois
/// précédents ».
function fenetres(periode: Periode, maintenant = new Date()) {
  if (periode === "annee") {
    const debut = new Date(maintenant.getFullYear(), 0, 1)
    return { debut, debutAvant: new Date(maintenant.getFullYear() - 1, 0, 1), finAvant: debut }
  }
  const mois = PERIODES.find((p) => p.clef === periode)!.mois
  const debut = new Date(maintenant)
  debut.setMonth(debut.getMonth() - mois)
  const debutAvant = new Date(debut)
  debutAvant.setMonth(debutAvant.getMonth() - mois)
  return { debut, debutAvant, finAvant: debut }
}

type Totaux = { nombre: number; temps: number; denivele: number }

function totaliser(lignes: Ligne[]): Totaux {
  return {
    nombre: lignes.length,
    temps: lignes.reduce((s, a) => s + a.moving_time, 0),
    denivele: lignes.reduce((s, a) => s + a.total_elevation_gain, 0),
  }
}

/// L'écart en pourcentage, ou null quand il n'y a rien à comparer — une
/// première période à zéro donnerait une division par zéro, et « +∞ % » n'est
/// pas une information.
function ecart(courant: number, avant: number): number | null {
  if (avant <= 0) return null
  return Math.round(((courant - avant) / avant) * 100)
}

function Evolution({ valeur }: { valeur: number | null }) {
  if (valeur === null) return null
  const signe = valeur > 0 ? "+" : ""
  // Le vert n'est pas « mieux » : plus de dénivelé n'est pas un progrès en
  // soi. Il dit seulement « en hausse », et la couleur suit le signe.
  // Zéro n'est ni une hausse ni une baisse : le colorer en vert lui ferait
  // dire quelque chose qu'il ne dit pas.
  const sens = valeur === 0 ? "" : valeur > 0 ? " hausse" : " baisse"
  return (
    <span className={"evolution" + sens}>
      {signe}
      {valeur} %
    </span>
  )
}

export function Stats() {
  const [periode, setPeriode] = useState<Periode>("3mois")
  const { debut, debutAvant, finAvant } = fenetres(periode)

  const { data, error, isPending } = useQuery({
    queryKey: ["stats", periode],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("activity")
        .select(
          "uuid, name, sport_type_raw, start_local_date, distance, moving_time, total_elevation_gain",
        )
        .is("deleted_at", null)
        .gte("start_local_date", debutAvant.toISOString())
        .order("start_local_date", { ascending: false })
      if (error) throw error
      return data as unknown as Ligne[]
    },
  })

  if (isPending) return <p className="attenue">Chargement…</p>
  if (error) return <p className="erreur">{(error as Error).message}</p>

  const dansLaFenetre = data.filter((a) => new Date(a.start_local_date) >= debut)
  const avant = data.filter((a) => {
    const d = new Date(a.start_local_date)
    return d >= debutAvant && d < finAvant
  })

  const totaux = totaliser(dansLaFenetre)
  const totauxAvant = totaliser(avant)

  // Par sport, dans l'ordre décroissant du temps passé : c'est le temps qui
  // dit ce qu'on pratique vraiment, pas le nombre de sorties — dix marches de
  // vingt minutes ne pèsent pas trois sorties longues.
  const parSport = new Map<string, { nombre: number; km: number; temps: number; dplus: number }>()
  for (const a of dansLaFenetre) {
    const t = parSport.get(a.sport_type_raw) ?? { nombre: 0, km: 0, temps: 0, dplus: 0 }
    t.nombre += 1
    t.km += a.distance
    t.temps += a.moving_time
    t.dplus += a.total_elevation_gain
    parSport.set(a.sport_type_raw, t)
  }
  const sports = [...parSport.entries()].sort((x, y) => y[1].temps - x[1].temps)

  const plusLongue = [...dansLaFenetre].sort((x, y) => y.distance - x.distance)[0]
  const plusGrimpante = [...dansLaFenetre].sort(
    (x, y) => y.total_elevation_gain - x.total_elevation_gain,
  )[0]
  const plusLongueEnTemps = [...dansLaFenetre].sort((x, y) => y.moving_time - x.moving_time)[0]

  return (
    <>
      <div className="pastilles">
        {PERIODES.map((p) => (
          <button
            key={p.clef}
            className={periode === p.clef ? "pastille-choix active" : "pastille-choix"}
            onClick={() => setPeriode(p.clef)}
          >
            {p.nom}
          </button>
        ))}
      </div>

      {/* Les trois seuls chiffres qu'on peut additionner tous sports
          confondus. La distance n'y est pas, et c'est délibéré. */}
      <div className="carte-groupe grands-totaux">
        <div className="grand-total">
          <span className="valeur">{totaux.nombre}</span>
          <span className="etiquette">
            sortie{totaux.nombre > 1 ? "s" : ""}{" "}
            <Evolution valeur={ecart(totaux.nombre, totauxAvant.nombre)} />
          </span>
        </div>
        <div className="grand-total">
          <span className="valeur">{duree(totaux.temps)}</span>
          <span className="etiquette">
            de mouvement <Evolution valeur={ecart(totaux.temps, totauxAvant.temps)} />
          </span>
        </div>
        <div className="grand-total">
          <span className="valeur">{denivele(totaux.denivele)}</span>
          <span className="etiquette">
            de dénivelé <Evolution valeur={ecart(totaux.denivele, totauxAvant.denivele)} />
          </span>
        </div>
      </div>

      {dansLaFenetre.length === 0 && (
        <p className="attenue">Aucune sortie sur cette période.</p>
      )}

      {sports.length > 0 && (
        <>
          <h4 className="titre-section">Par sport</h4>
          <ul className="liste sans-chevron">
            {sports.map(([sport, t]) => (
              <li className="ligne" key={sport}>
                <div className="ligne-tete">
                  <span className="titre">{nomDuSport(sport)}</span>
                  <span className="attenue petit">
                    {t.nombre} sortie{t.nombre > 1 ? "s" : ""}
                  </span>
                </div>
                <div className="attenue petit">
                  {distance(t.km)} · {duree(t.temps)} · {denivele(t.dplus)}
                </div>
              </li>
            ))}
          </ul>
        </>
      )}

      {plusLongue && (
        <>
          <h4 className="titre-section">Records de la période</h4>
          <ul className="liste sans-chevron">
            <li className="ligne">
              <div className="ligne-tete">
                <span className="titre">{plusLongue.name}</span>
                <span className="attenue petit">{distance(plusLongue.distance)}</span>
              </div>
              <div className="attenue petit">La plus longue</div>
            </li>
            <li className="ligne">
              <div className="ligne-tete">
                <span className="titre">{plusGrimpante.name}</span>
                <span className="attenue petit">
                  {denivele(plusGrimpante.total_elevation_gain)}
                </span>
              </div>
              <div className="attenue petit">La plus grimpante</div>
            </li>
            <li className="ligne">
              <div className="ligne-tete">
                <span className="titre">{plusLongueEnTemps.name}</span>
                <span className="attenue petit">{duree(plusLongueEnTemps.moving_time)}</span>
              </div>
              <div className="attenue petit">La plus longue en temps</div>
            </li>
          </ul>
        </>
      )}
    </>
  )
}
