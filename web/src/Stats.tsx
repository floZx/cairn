import { useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { nomDuSport } from "./sports"
import { IconeSport } from "./IconeSport"
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

/// Ce qu'un graphique peut porter.
///
/// Pas la distance, et c'est la même règle qu'ailleurs : un mois qui empile
/// des kilomètres de vélo sur des kilomètres de course ne dit rien de plus
/// qu'un total annuel qui ferait pareil.
type Mesure = "sorties" | "temps" | "denivele"

const MESURES: { clef: Mesure; nom: string }[] = [
  { clef: "sorties", nom: "Sorties" },
  { clef: "temps", nom: "Temps" },
  { clef: "denivele", nom: "D+" },
]

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

/// La clé du mois d'une date : « 2026-08 ».
function moisDe(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`
}

const NOM_MOIS = new Intl.DateTimeFormat("fr-FR", { month: "short" })

/// Les mois de la fenêtre, du plus ancien au plus récent, chacun avec sa
/// valeur et celle de son homologue dans la période précédente.
///
/// L'homologue est le même rang, pas le même mois de l'année : sur trois mois,
/// juin se compare à mars. C'est ce que « les trois mois précédents » veut
/// dire, et c'est déjà la règle des totaux au-dessus.
function parMois(
  lignes: Ligne[],
  debut: Date,
  debutAvant: Date,
  mesure: Mesure,
): { etiquette: string; valeur: number; avant: number }[] {
  const valeurDe = (a: Ligne) =>
    mesure === "sorties" ? 1 : mesure === "temps" ? a.moving_time : a.total_elevation_gain

  const sommes = new Map<string, number>()
  for (const a of lignes) {
    const clef = moisDe(new Date(a.start_local_date))
    sommes.set(clef, (sommes.get(clef) ?? 0) + valeurDe(a))
  }

  const cases: { etiquette: string; valeur: number; avant: number }[] = []
  const curseur = new Date(debut.getFullYear(), debut.getMonth(), 1)
  const curseurAvant = new Date(debutAvant.getFullYear(), debutAvant.getMonth(), 1)
  const fin = new Date()
  while (curseur <= fin) {
    cases.push({
      etiquette: NOM_MOIS.format(curseur),
      valeur: sommes.get(moisDe(curseur)) ?? 0,
      avant: sommes.get(moisDe(curseurAvant)) ?? 0,
    })
    curseur.setMonth(curseur.getMonth() + 1)
    curseurAvant.setMonth(curseurAvant.getMonth() + 1)
  }
  return cases
}

/// Le graphique, en SVG comme les courbes d'une sortie.
///
/// La période précédente est dessinée derrière, en creux : deux séries côte à
/// côte doubleraient le nombre de barres et rendraient chacune deux fois plus
/// fine, alors qu'on ne compare qu'un coup d'œil.
function Graphique({
  cases,
  mesure,
}: {
  cases: { etiquette: string; valeur: number; avant: number }[]
  mesure: Mesure
}) {
  if (cases.length === 0) return null
  const haut = Math.max(1, ...cases.map((c) => Math.max(c.valeur, c.avant)))
  const format = (v: number) =>
    mesure === "sorties" ? String(Math.round(v)) : mesure === "temps" ? duree(v) : denivele(v)

  return (
    <div className="carte-groupe graphique">
      <div className="tete-courbe">
        <span>{format(haut)}</span>
        <span className="attenue petit">au plus haut</span>
      </div>
      <div className="barres">
        {cases.map((c, i) => (
          <div className="colonne" key={i}>
            <div className="pile">
              {/* Le creux d'abord, la barre pleine par-dessus : superposées et
                  non côte à côte, elles se comparent d'un regard. */}
              <div
                className="barre-avant"
                style={{ height: `${(c.avant / haut) * 100}%` }}
                title={`Avant : ${format(c.avant)}`}
              />
              <div
                className="barre"
                style={{ height: `${(c.valeur / haut) * 100}%` }}
                title={format(c.valeur)}
              />
            </div>
            {/* Un mois sur deux au-delà de huit colonnes : « sept. » et
                « févr. » sont plus larges que leur colonne sur un an, et les
                afficher tous les faisait déborder de l'écran. Les intercaler
                garde le repère sans étrangler le dessin — et sans imposer un
                défilement latéral à un graphique qu'on lit d'un coup d'œil. */}
            <span className="etiquette-mois">
              {cases.length <= 8 || i % 2 === 0 ? c.etiquette : ""}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}

/// La courbe du poids : une ligne, et non des barres.
///
/// Un poids est une mesure continue, pas un total qu'on cumule par mois — le
/// relier dit la tendance, l'empiler ne dirait rien. Les jours sans pesée sont
/// simplement absents : la ligne les enjambe, ce qui est exactement ce qu'on
/// lit d'une balance qu'on ne monte pas tous les jours.
function CourbePoids({ pesees }: { pesees: { jour: string; kg: number }[] }) {
  if (pesees.length < 2) return null

  const LARGEUR = 320
  const HAUTEUR = 90
  const kgs = pesees.map((p) => p.kg)
  const bas = Math.min(...kgs)
  const haut = Math.max(...kgs)
  // Une amplitude plancher : sur une période où le poids n'a pas bougé de
  // trois cents grammes, une échelle collée aux valeurs ferait des montagnes
  // d'un bruit de balance.
  const amplitude = Math.max(haut - bas, 1)
  const centre = (haut + bas) / 2
  const min = centre - amplitude / 2
  const premier = new Date(pesees[0].jour).getTime()
  const dernier = new Date(pesees[pesees.length - 1].jour).getTime()
  const etendue = Math.max(dernier - premier, 1)

  // En abscisse par la date et non par le rang : deux pesées à trois mois
  // d'écart ne doivent pas s'afficher côte à côte parce qu'elles se suivent
  // dans la liste.
  const x = (jour: string) =>
    ((new Date(jour).getTime() - premier) / etendue) * LARGEUR
  const y = (kg: number) => HAUTEUR - ((kg - min) / amplitude) * (HAUTEUR - 8) - 4

  const trace = pesees
    .map((p, i) => `${i ? "L" : "M"}${x(p.jour).toFixed(1)} ${y(p.kg).toFixed(1)}`)
    .join(" ")

  const format = (v: number) => `${v.toLocaleString("fr-FR", { maximumFractionDigits: 1 })} kg`

  return (
    <>
      <h4 className="titre-section">Poids</h4>
      <div className="carte-groupe graphique">
        <div className="tete-courbe">
          <span>{format(pesees[pesees.length - 1].kg)}</span>
          <span className="attenue petit">
            de {format(bas)} à {format(haut)}
          </span>
        </div>
        <svg
          className="courbe-poids"
          viewBox={`0 0 ${LARGEUR} ${HAUTEUR}`}
          preserveAspectRatio="none"
          role="img"
          aria-label={`Poids, de ${format(bas)} à ${format(haut)}`}
        >
          <path
            d={`${trace} L${LARGEUR} ${HAUTEUR} L0 ${HAUTEUR} Z`}
            fill="var(--accent)"
            fillOpacity="0.14"
            stroke="none"
          />
          <path
            d={trace}
            fill="none"
            stroke="var(--accent)"
            strokeWidth="2"
            strokeLinejoin="round"
            strokeLinecap="round"
            vectorEffect="non-scaling-stroke"
          />
        </svg>
      </div>
    </>
  )
}

export function Stats() {
  const [periode, setPeriode] = useState<Periode>("3mois")
  const [mesure, setMesure] = useState<Mesure>("temps")
  const { debut, debutAvant, finAvant } = fenetres(periode)

  const { data, error, isPending } = useQuery({
    queryKey: ["stats", periode],
    queryFn: async () => {
      const [sorties, poids] = await Promise.all([
        supabase
          .from("activity")
          .select(
            "uuid, name, sport_type_raw, start_local_date, distance, moving_time, total_elevation_gain",
          )
          .is("deleted_at", null)
          .gte("start_local_date", debutAvant.toISOString())
          .order("start_local_date", { ascending: false }),
        supabase
          .from("weight_entry")
          .select("date_key_raw, weight_kg")
          .is("deleted_at", null)
          .gte("date_key_raw", debut.toISOString().slice(0, 10))
          .order("date_key_raw"),
      ])
      if (sorties.error) throw sorties.error
      if (poids.error) throw poids.error
      return {
        sorties: sorties.data as unknown as Ligne[],
        pesees: (poids.data as { date_key_raw: string; weight_kg: number }[]).map((p) => ({
          jour: p.date_key_raw,
          kg: p.weight_kg,
        })),
      }
    },
  })

  if (isPending) return <p className="attenue">Chargement…</p>
  if (error) return <p className="erreur">{(error as Error).message}</p>

  const dansLaFenetre = data.sorties.filter((a) => new Date(a.start_local_date) >= debut)
  const avant = data.sorties.filter((a) => {
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

      {dansLaFenetre.length > 0 && (
        <>
          <h4 className="titre-section">Par mois</h4>
          <div className="pastilles">
            {MESURES.map((m) => (
              <button
                key={m.clef}
                className={mesure === m.clef ? "pastille-choix active" : "pastille-choix"}
                onClick={() => setMesure(m.clef)}
              >
                {m.nom}
              </button>
            ))}
          </div>
          <Graphique
            cases={parMois(data.sorties, debut, debutAvant, mesure)}
            mesure={mesure}
          />
        </>
      )}

      <CourbePoids pesees={data.pesees} />

      {sports.length > 0 && (
        <>
          <h4 className="titre-section">Par sport</h4>
          <ul className="liste sans-chevron">
            {sports.map(([sport, t]) => (
              <li className="ligne avec-icone" key={sport}>
                <IconeSport sport={sport} />
                <div>
                  <div className="ligne-tete">
                    <span className="titre">{nomDuSport(sport)}</span>
                    <span className="attenue petit">
                      {t.nombre} sortie{t.nombre > 1 ? "s" : ""}
                    </span>
                  </div>
                  <div className="attenue petit">
                    {distance(t.km)} · {duree(t.temps)} · {denivele(t.dplus)}
                  </div>
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
