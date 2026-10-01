/// Les médailles des meilleurs efforts : sur une ligne de la liste, sous le
/// titre d'une fiche, et en carte dans les statistiques. Un toucher sur une
/// médaille ouvre les podiums de ses distances ; un titre y ouvre la sortie.

import { useState } from "react"
import { Feuille } from "./Chrome"
import { Symbole } from "./IconeSport"
import { allureOuVitesse, dateCourte } from "./format"
import {
  DISTANCES,
  couleurMedaille,
  rangEnLettres,
  tempsDeCourse,
  usePodiums,
  type Medaille,
} from "./podiums"

function IconeMedaille({ rang, taille = 14 }: { rang: number; taille?: number }) {
  return <Symbole nom="medal.fill" taille={taille} couleur={couleurMedaille(rang)} />
}

/// Les podiums des distances demandées. La sortie d'où l'on vient est en
/// gras, sans lien : on y est déjà.
function Podiums({ distances, ici, onOuvrir }: {
  distances: number[]
  ici?: string
  onOuvrir: (uuid: string) => void
}) {
  const { data } = usePodiums()
  if (!data) return null
  return (
    <div className="podiums">
      {distances.map((d) => (
        <section key={d}>
          <h4>{DISTANCES[d].label}</h4>
          <ul className="liste sans-chevron">
            {data.parDistance[d].map((p, i) => {
              const allure = allureOuVitesse("run", DISTANCES[d].metres, p.secondes)
              const estIci = p.sortie.uuid === ici
              return (
                <li key={p.sortie.uuid} className="ligne place-podium">
                  <IconeMedaille rang={i + 1} taille={18} />
                  <span className={"temps-podium" + (estIci ? " ici" : "")}>{tempsDeCourse(p.secondes)}</span>
                  <span className="attenue petit">{allure?.valeur}/km</span>
                  <span className="sortie-podium">
                    {estIci ? (
                      <strong>{p.sortie.name}</strong>
                    ) : (
                      <button className="lien" onClick={() => onOuvrir(p.sortie.uuid)}>
                        {p.sortie.name}
                      </button>
                    )}
                    <span className="attenue petit">{dateCourte(p.sortie.start_local_date)}</span>
                  </span>
                </li>
              )
            })}
          </ul>
        </section>
      ))}
    </div>
  )
}

function FeuillePodiums({ medailles, ici, onOuvrir, onFerme }: {
  medailles: Medaille[]
  ici: string
  onOuvrir: (uuid: string) => void
  onFerme: () => void
}) {
  const distances = [...new Set(medailles.map((m) => m.distance))].sort((a, b) => a - b)
  return (
    <Feuille titre={distances.length === 1 ? DISTANCES[distances[0]].label : "Records"} onFerme={onFerme}>
      <Podiums
        distances={distances}
        ici={ici}
        onOuvrir={(uuid) => {
          onFerme()
          onOuvrir(uuid)
        }}
      />
    </Feuille>
  )
}

/// La médaille d'une ligne de la liste : la meilleure place, et le nombre de
/// records quand il y en a plusieurs. Rien quand la sortie n'est sur aucun
/// podium.
export function MedailleSortie({ uuid, onOuvrir }: { uuid: string; onOuvrir: (uuid: string) => void }) {
  const { data } = usePodiums()
  const [ouverte, setOuverte] = useState(false)
  const medailles = data?.medailles.get(uuid)
  if (!medailles) return null
  const meilleure = Math.min(...medailles.map((m) => m.rang))
  return (
    <>
      <button
        className="medaille-sortie"
        aria-label="Records"
        onClick={(e) => {
          // La ligne entière ouvre la sortie ; la médaille, ses podiums.
          e.stopPropagation()
          setOuverte(true)
        }}
      >
        <IconeMedaille rang={meilleure} />
        {medailles.length > 1 && <span className="attenue petit">{medailles.length}</span>}
      </button>
      {ouverte && (
        <FeuillePodiums medailles={medailles} ici={uuid} onOuvrir={onOuvrir} onFerme={() => setOuverte(false)} />
      )}
    </>
  )
}

/// Les records d'une fiche, une pastille par distance ; chacune ouvre son
/// podium.
export function PastillesRecords({ uuid, onOuvrir }: { uuid: string; onOuvrir: (uuid: string) => void }) {
  const { data } = usePodiums()
  const [ouverte, setOuverte] = useState<Medaille | null>(null)
  const medailles = data?.medailles.get(uuid)
  if (!medailles) return null
  return (
    <div className="etiquettes">
      {[...medailles]
        .sort((a, b) => a.distance - b.distance)
        .map((m) => (
          <button
            key={m.distance}
            className="etiquette-tag pastille-record"
            style={{ background: `color-mix(in srgb, ${couleurMedaille(m.rang)} 18%, transparent)` }}
            onClick={() => setOuverte(m)}
            title={`${rangEnLettres(m.rang)} meilleur temps sur ${DISTANCES[m.distance].label}`}
          >
            <IconeMedaille rang={m.rang} taille={13} />
            {DISTANCES[m.distance].label}
            <strong>{tempsDeCourse(m.secondes)}</strong>
          </button>
        ))}
      {ouverte && (
        <FeuillePodiums medailles={[ouverte]} ici={uuid} onOuvrir={onOuvrir} onFerme={() => setOuverte(null)} />
      )}
    </div>
  )
}

/// La carte des statistiques : toutes les distances courues, leurs trois
/// meilleurs temps. Toute la bibliothèque, pas la période — un record de
/// l'an dernier reste le record.
export function CarteMeilleursEfforts({ onOuvrir }: { onOuvrir: (uuid: string) => void }) {
  const { data, isPending } = usePodiums()
  const distances = data ? DISTANCES.map((_, i) => i).filter((i) => data.parDistance[i].length > 0) : []
  return (
    <section className="carte-groupe carte-stats">
      <header className="tete-stats">
        <div>
          <h4>Meilleurs efforts</h4>
          <p className="attenue">Course et trail, toutes dates · les trois meilleurs temps</p>
        </div>
      </header>
      {isPending ? (
        <p className="attenue petit">Chargement…</p>
      ) : distances.length === 0 ? (
        <p className="attenue petit">Rien encore : le Mac calcule les records et les envoie à sa prochaine synchronisation.</p>
      ) : (
        <Podiums distances={distances} onOuvrir={onOuvrir} />
      )}
    </section>
  )
}
