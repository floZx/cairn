import { useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"

/// Les zones de FC et de puissance d'une sortie, telles que Garmin les
/// appliquait ce jour-là — le pendant d'`ActivityZonesView` sur le Mac, et le
/// tableau de Garmin : zone 5 en haut, plage, nom, temps, part.
///
/// Une requête à part : les colonnes n'existent qu'une fois `013-zones.sql`
/// passé, et une fiche qui les demanderait avec le reste ne s'ouvrirait plus
/// du tout sans elles.

type Ligne = {
  hr_zone_floors: number[] | null
  hr_zone_seconds: number[] | null
  power_zone_floors: number[] | null
  power_zone_seconds: number[] | null
}

const NOMS = {
  fc: ["Échauffement", "Facile", "Aérobie", "Seuil", "Maximum"],
  puissance: ["Facile", "Modéré", "Tempo", "Intervalle long", "Intervalle court"],
}
const COULEURS = ["var(--zone-1)", "var(--zone-2)", "var(--zone-3)", "var(--zone-4)", "var(--zone-5)"]

function duree(secondes: number): string {
  const s = Math.round(secondes)
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const r = s % 60
  const deux = (n: number) => String(n).padStart(2, "0")
  return h > 0 ? `${h}:${deux(m)}:${deux(r)}` : `${m}:${deux(r)}`
}

/// Le donut et sa légende : la zone 1 part du haut, dans le sens des
/// aiguilles ; au centre, la durée et la zone où la sortie s'est passée. La
/// légende porte tout — plage, temps, part — et garde les zones vides,
/// atténuées, pour que l'échelle reste entière.
function Tableau({
  planchers,
  secondes,
  unite,
  noms,
}: {
  planchers: number[]
  secondes: number[]
  unite: string
  noms: string[]
}) {
  const n = Math.min(planchers.length, secondes.length)
  if (n === 0) return null
  const total = secondes.slice(0, n).reduce((a, b) => a + b, 0)
  const rayon = 46
  const tour = 2 * Math.PI * rayon
  const ecart = 1.2
  let depart = 0
  const arcs = Array.from({ length: n }, (_, i) => {
    const longueur = total > 0 ? (secondes[i] / total) * tour : 0
    const arc = { i, longueur, depart }
    depart += longueur
    return arc
  }).filter((a) => a.longueur > 0)
  const dominante = Array.from({ length: n }, (_, i) => i).reduce((m, i) =>
    secondes[i] > secondes[m] ? i : m, 0)
  const plage = (i: number) => {
    const bas = Math.round(planchers[i])
    return i + 1 < n ? `${bas} - ${Math.round(planchers[i + 1]) - 1} ${unite}` : `> ${bas - 1} ${unite}`
  }
  return (
    <div className="donut-zones">
      <svg viewBox="0 0 120 120" role="img" aria-label="Répartition par zone">
        <circle cx="60" cy="60" r={rayon} fill="none" stroke="var(--champ)" strokeWidth="14" />
        {arcs.map((a) => (
          <circle
            key={a.i}
            cx="60"
            cy="60"
            r={rayon}
            fill="none"
            stroke={COULEURS[a.i]}
            strokeWidth="14"
            strokeDasharray={`${Math.max(a.longueur - ecart, 0.8)} ${tour}`}
            strokeDashoffset={-a.depart}
            transform="rotate(-90 60 60)"
          />
        ))}
        <text x="60" y="58" textAnchor="middle" className="donut-total">
          {duree(total)}
        </text>
        {total > 0 && (
          <text x="60" y="74" textAnchor="middle" className="donut-sous">
            {Math.floor((secondes[dominante] / total) * 100)} % en Z{dominante + 1}
          </text>
        )}
      </svg>
      <div className="legende-zones">
        {Array.from({ length: n }, (_, i) => i)
          .reverse()
          .map((i) => {
            const part = total > 0 ? secondes[i] / total : 0
            return (
              <div className={secondes[i] > 0 ? "legende-zone" : "legende-zone vide"} key={i}>
                <span className="legende-point" style={{ background: COULEURS[i] }} />
                <div className="legende-nom">
                  <b>Z{i + 1}</b> {noms[i] ?? ""}
                  <div className="attenue">{plage(i)}</div>
                </div>
                <div className="legende-valeur">
                  {duree(secondes[i])}
                  {/* Tronqué, comme Garmin : 74,9 % s'y lit « 74 % ». */}
                  <div className="attenue">{Math.floor(part * 100)} %</div>
                </div>
              </div>
            )
          })}
      </div>
    </div>
  )
}

export function Zones({ uuid }: { uuid: string }) {
  const [vue, setVue] = useState<"fc" | "puissance">("fc")
  const { data } = useQuery({
    queryKey: ["zones", uuid],
    staleTime: 10 * 60 * 1000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("activity")
        .select("hr_zone_floors, hr_zone_seconds, power_zone_floors, power_zone_seconds")
        .eq("uuid", uuid)
        .single()
      // Colonnes absentes : pas de zones, et la fiche vit sans elles.
      if (error) return null
      return data as unknown as Ligne
    },
  })
  if (!data) return null
  const fc = data.hr_zone_floors && data.hr_zone_seconds
  const puissance = data.power_zone_floors && data.power_zone_seconds
  if (!fc && !puissance) return null
  // Une seule carte, et le choix entre les deux quand les deux existent :
  // deux tableaux de cinq lignes l'un sous l'autre prenaient deux écrans.
  const montre = fc && (vue === "fc" || !puissance) ? "fc" : "puissance"
  return (
    <section className="zones carte-groupe">
      <div className="tete-description">
        <span className="attenue petit">Zones</span>
        {fc && puissance ? (
          <div className="choix-zones" role="group" aria-label="Zones">
            <button className={montre === "fc" ? "actif" : ""} onClick={() => setVue("fc")}>
              FC
            </button>
            <button
              className={montre === "puissance" ? "actif" : ""}
              onClick={() => setVue("puissance")}
            >
              Puissance
            </button>
          </div>
        ) : (
          <span className="attenue petit">{fc ? "FC" : "Puissance"}</span>
        )}
      </div>
      {montre === "fc" ? (
        <Tableau
          planchers={data.hr_zone_floors!}
          secondes={data.hr_zone_seconds!}
          unite="bpm"
          noms={NOMS.fc}
        />
      ) : (
        <Tableau
          planchers={data.power_zone_floors!}
          secondes={data.power_zone_seconds!}
          unite="W"
          noms={NOMS.puissance}
        />
      )}
    </section>
  )
}
