import { useLayoutEffect, useRef, useState, type ReactNode, type RefObject, type PointerEvent as EvenementPointeur } from "react"
import { Chargement } from "./Chrome"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { CarteMeilleursEfforts } from "./Records"
import { POIDS_MASQUE } from "./masquees"
import { nomDuSport } from "./sports"
import { Symbole, symboleDuSport } from "./IconeSport"
import { COULEURS_ZONES } from "./Zones"
import { allureOuVitesse, denivele, distance, duree } from "./format"
import {
  PERIODES, type Periode, type Sortie, type Statistiques, type Record_, type Mesure,
  type PointForme, type Regularite, type Intensite, type Progression, type Granularite,
  calculer, quotidien, serie, etat, rampe, regularite, niveaux, intensite, part, profil,
  sportsSuivis, progression, tendance, valeur, enKmEffort, semaines, dateDuJour, jourDe,
} from "./statistiques"

/// Les statistiques, portées du tableau de bord du Mac : cumuls comparés à
/// date, forme et fatigue, régularité, intensité, progression d'un sport.
///
/// Le calcul vit dans `statistiques.ts`, porté règle par règle ; cet écran ne
/// fait que dessiner. La règle de fond reste la même : **additionner des
/// sports différents ne dit rien** — la distance ne se lit que par sport.

// MARK: - Outils de dessin

/// La largeur réelle d'un bloc, pour tracer les graphiques au pixel près :
/// un `viewBox` étiré grossirait le texte des axes avec l'écran.
function useLargeur(): [RefObject<HTMLDivElement>, number] {
  const ref = useRef<HTMLDivElement>(null)
  const [largeur, setLargeur] = useState(320)
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const ro = new ResizeObserver(([e]) => setLargeur(Math.max(200, e.contentRect.width)))
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  return [ref, largeur]
}

const NOM_MOIS = new Intl.DateTimeFormat("fr-FR", { month: "short", timeZone: "UTC" })
const DATE = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" })
const moisDe = (jour: number) => NOM_MOIS.format(dateDuJour(jour))
const dateDe = (jour: number) => DATE.format(dateDuJour(jour))

function heures(secondes: number): string {
  return duree(Math.round(secondes))
}

function signe(v: number): string {
  const r = Math.round(v)
  return r > 0 ? `+${r}` : `${r}`
}

function ecart(courant: number, avant: number): number | null {
  if (avant <= 0) return null
  return Math.round(((courant - avant) / avant) * 100)
}

function Evolution({ valeur }: { valeur: number | null }) {
  if (valeur === null) return null
  const sens = valeur === 0 ? "" : valeur > 0 ? " hausse" : " baisse"
  return (
    <span className={"evolution" + sens}>
      {valeur > 0 ? "↑ " : valeur < 0 ? "↓ " : "= "}
      {Math.abs(valeur)} %
    </span>
  )
}

function Carte({ titre, sousTitre, droite, children }: {
  titre: string
  sousTitre?: string
  droite?: ReactNode
  children: ReactNode
}) {
  return (
    <section className="carte-groupe carte-stats">
      <header className="tete-stats">
        <div>
          <h4>{titre}</h4>
          {sousTitre && <p className="attenue">{sousTitre}</p>}
        </div>
        {droite}
      </header>
      {children}
    </section>
  )
}

function Chiffre({ etiquette, valeur, children }: { etiquette: string; valeur: string; children?: ReactNode }) {
  return (
    <div className="chiffre-stats">
      <span className="etiquette">{etiquette}</span>
      <span className="valeur">{valeur}</span>
      {children && <span className="detail">{children}</span>}
    </div>
  )
}

function Segmente<T extends string>({ choix, valeur, onChange, etiquette }: {
  choix: { clef: T; nom: string }[]
  valeur: T
  onChange: (v: T) => void
  etiquette: string
}) {
  return (
    <div className="segmente" role="group" aria-label={etiquette}>
      {choix.map((c) => (
        <button
          key={c.clef}
          className={valeur === c.clef ? "segment-texte actif" : "segment-texte"}
          onClick={() => onChange(c.clef)}
          aria-pressed={valeur === c.clef}
        >
          {c.nom}
        </button>
      ))}
    </div>
  )
}

/// L'indice du point le plus proche d'un geste, au doigt comme à la souris.
function indiceSous(e: EvenementPointeur<SVGSVGElement>, n: number, gauche: number, largeur: number): number {
  const rect = e.currentTarget.getBoundingClientRect()
  const x = e.clientX - rect.left - gauche
  return Math.max(0, Math.min(n - 1, Math.round((x / Math.max(largeur, 1)) * (n - 1))))
}

/// Les repères de mois sous un axe de jours : un libellé au premier jour de
/// chaque mois, un sur deux quand ils se serreraient.
function reperesMois(debut: number, fin: number, x: (j: number) => number, largeur: number) {
  const reperes: { x: number; texte: string }[] = []
  for (let j = debut; j <= fin; j++) {
    if (dateDuJour(j).getUTCDate() === 1) reperes.push({ x: x(j), texte: moisDe(j) })
  }
  const pas = reperes.length > largeur / 45 ? 2 : 1
  return reperes.filter((_, i) => i % pas === 0)
}

// MARK: - Forme

function CarteForme({ points, debut, estimees, nombre }: {
  points: PointForme[]
  debut: number
  estimees: number
  nombre: number
}) {
  const [ref, largeur] = useLargeur()
  const [choisi, setChoisi] = useState<number | null>(null)
  const vus = points.filter((p) => p.jour >= debut)
  if (vus.length === 0) return null
  const lu = choisi !== null ? vus[choisi] : points[points.length - 1]
  const e = etat(lu)
  const r = rampe(points)

  const H = 170, HF = 60, DROITE = 30
  const l = largeur - DROITE
  const haut = Math.max(10, ...vus.map((p) => Math.max(p.forme, p.fatigue))) * 1.15
  const x = (i: number) => (i / Math.max(vus.length - 1, 1)) * l
  const y = (v: number) => H - (Math.min(v, haut) / haut) * H
  const ligne = (f: (p: PointForme) => number) =>
    vus.map((p, i) => `${i ? "L" : "M"}${x(i).toFixed(1)} ${y(f(p)).toFixed(1)}`).join(" ")
  const lf = Math.max(10, ...vus.map((p) => Math.abs(p.fraicheur)))
  const yf = (v: number) => HF / 2 - (v / lf) * (HF / 2 - 3)
  const traceF = vus.map((p, i) => `${i ? "L" : "M"}${x(i).toFixed(1)} ${yf(p.fraicheur).toFixed(1)}`).join(" ")
  const largeurBarre = Math.max(1, l / vus.length - 1)
  const reperes = reperesMois(vus[0].jour, vus[vus.length - 1].jour, (j) => x(j - vus[0].jour), l)
  const graduations = [0, haut / 2, haut].map((v) => Math.round(v / 10) * 10)

  const suivre = (ev: EvenementPointeur<SVGSVGElement>) => setChoisi(indiceSous(ev, vus.length, 0, l))
  const lacher = (ev: EvenementPointeur<SVGSVGElement>) => {
    if (ev.pointerType === "mouse") setChoisi(null)
  }

  return (
    <Carte titre="Forme" sousTitre="Charge d'entraînement tirée des zones de fréquence cardiaque">
      <div className="grille-chiffres">
        <Chiffre etiquette="Forme" valeur={String(Math.round(lu.forme))}>
          {r === null ? "" : Math.abs(r) < 0.5 ? "stable sur 7 jours" : `${signe(r)} en 7 jours`}
        </Chiffre>
        <Chiffre etiquette="Fatigue" valeur={String(Math.round(lu.fatigue))}>moyenne sur 7 jours</Chiffre>
        <Chiffre etiquette="Fraîcheur" valeur={signe(lu.fraicheur)}>forme − fatigue</Chiffre>
        <div className="chiffre-stats">
          <span className="etiquette">{choisi !== null ? dateDe(lu.jour) : "Aujourd'hui"}</span>
          <span className="etat" style={{ color: e.couleur }}>{e.nom}</span>
          <span className="detail">{e.conseil}</span>
        </div>
      </div>

      <div ref={ref} className="dessin">
        <div className="legende-stats">
          <span><i style={{ background: "var(--accent)" }} />Forme</span>
          <span><i style={{ background: "var(--trace-3)" }} />Fatigue</span>
          <span><i style={{ background: "var(--texte-3)" }} />Charge du jour</span>
        </div>
        <svg
          width={largeur} height={H + 18} className="svg-stats"
          onPointerMove={suivre} onPointerDown={suivre} onPointerLeave={lacher}
          role="img" aria-label={`Forme ${Math.round(lu.forme)}, fatigue ${Math.round(lu.fatigue)}`}
        >
          {graduations.map((v) => (
            <g key={v}>
              <line x1={0} x2={l} y1={y(v)} y2={y(v)} className="grille" />
              <text x={largeur - 2} y={y(v) + 4} textAnchor="end" className="axe">{v}</text>
            </g>
          ))}
          {vus.map((p, i) =>
            p.charge > 0 ? (
              <rect key={p.jour} x={x(i) - largeurBarre / 2} y={y(p.charge)} width={largeurBarre}
                height={H - y(p.charge)} className="barre-charge" />
            ) : null,
          )}
          <path d={`${ligne((p) => p.forme)} L${l} ${H} L0 ${H} Z`} fill="var(--accent)" fillOpacity={0.1} />
          <path d={ligne((p) => p.forme)} fill="none" stroke="var(--accent)" strokeWidth={2.5} strokeLinejoin="round" />
          <path d={ligne((p) => p.fatigue)} fill="none" stroke="var(--trace-3)" strokeOpacity={0.7} strokeWidth={1.5} strokeLinejoin="round" />
          {choisi !== null && <line x1={x(choisi)} x2={x(choisi)} y1={0} y2={H} className="curseur" />}
          {reperes.map((m) => (
            <text key={m.x} x={m.x} y={H + 14} className="axe">{m.texte}</text>
          ))}
        </svg>
        <div className="etiquette-mini">Fraîcheur</div>
        <svg width={largeur} height={HF} className="svg-stats"
          onPointerMove={suivre} onPointerDown={suivre} onPointerLeave={lacher}>
          <line x1={0} x2={l} y1={HF / 2} y2={HF / 2} className="grille" />
          <path d={`${traceF} L${l} ${HF / 2} L0 ${HF / 2} Z`} fill="var(--texte)" fillOpacity={0.08} />
          <path d={traceF} fill="none" stroke="var(--texte-2)" strokeWidth={1.5} strokeLinejoin="round" />
          {choisi !== null && <line x1={x(choisi)} x2={x(choisi)} y1={0} y2={HF} className="curseur" />}
          <text x={largeur - 2} y={HF / 2 + 4} textAnchor="end" className="axe">0</text>
        </svg>
      </div>
      <p className="note-stats">
        Charge d'une sortie : minutes dans chaque zone × numéro de la zone. Forme : moyenne sur 42
        jours, fatigue : sur 7.
        {estimees > 0 &&
          ` ${estimees} sorties sur ${nombre} n'ont pas de zones Garmin : leur charge est estimée d'après la FC moyenne.`}
      </p>
    </Carte>
  )
}

// MARK: - Régularité

const COULEURS_NIVEAUX = [
  "color-mix(in srgb, var(--texte) 9%, transparent)",
  "color-mix(in srgb, var(--accent) 30%, transparent)",
  "color-mix(in srgb, var(--accent) 50%, transparent)",
  "color-mix(in srgb, var(--accent) 75%, transparent)",
  "var(--accent)",
]

function CarteRegularite({ r }: { r: Regularite }) {
  const [ref, largeur] = useLargeur()
  const [choisi, setChoisi] = useState<number | null>(null)
  const niv = niveaux(r.jours)
  const semainesN = Math.max(...r.jours.map((j) => j.semaine)) + 1
  const GAUCHE = 24, ECART = 2
  const cote = Math.min(14, Math.max(4, (largeur - GAUCHE) / semainesN - ECART))
  const pas = cote + ECART
  const jourChoisi = r.jours.find((j) => j.jour === choisi)
  const lundis = r.jours.filter((j) => j.jourSemaine === 0)
  const reperes = lundis.filter((j, i) => i > 0 && dateDuJour(j.jour).getUTCMonth() !== dateDuJour(j.jour - 7).getUTCMonth())
  const espaces = reperes.filter((_, i) => largeur > 420 || i % 2 === 0)
  const part = Math.round((r.joursActifs / Math.max(r.joursPeriode, 1)) * 100)
  const p = r.projection

  return (
    <Carte titre="Régularité" sousTitre="Les 52 dernières semaines, un carré par jour">
      <div className="grille-chiffres">
        <Chiffre etiquette="Série en cours" valeur={`${r.serieEnCours} sem.`}>semaines d'affilée avec une sortie</Chiffre>
        <Chiffre etiquette="Meilleure série" valeur={`${r.meilleureSerie} sem.`}>
          {r.serieEnCours >= r.meilleureSerie && r.meilleureSerie > 0 ? "c'est celle-ci !" : "depuis la première sortie"}
        </Chiffre>
        <Chiffre etiquette="Jours actifs" valeur={String(r.joursActifs)}>sur {r.joursPeriode} jours ({part} %)</Chiffre>
        <Chiffre etiquette="Par semaine" valeur={heures(r.heuresParSemaine * 3600)}>en moyenne sur la période</Chiffre>
      </div>
      <div ref={ref} className="dessin">
        <svg width={largeur} height={14 + 7 * pas} className="svg-stats">
          {espaces.map((j) => (
            <text key={j.jour} x={GAUCHE + j.semaine * pas} y={9} className="axe">{moisDe(j.jour)}</text>
          ))}
          {["lun.", "mer.", "ven.", "dim."].map((t, i) => (
            <text key={t} x={0} y={14 + [0, 2, 4, 6][i] * pas + cote - 1} className="axe">{t}</text>
          ))}
          {r.jours.map((j) => (
            <rect
              key={j.jour}
              x={GAUCHE + j.semaine * pas}
              y={14 + j.jourSemaine * pas}
              width={cote} height={cote} rx={Math.min(2.5, cote / 4)}
              fill={COULEURS_NIVEAUX[niv.get(j.jour) ?? 0]}
              stroke={choisi === j.jour ? "var(--texte)" : "none"}
              onPointerEnter={() => setChoisi(j.jour)}
              onPointerDown={() => setChoisi(j.jour)}
            />
          ))}
        </svg>
      </div>
      <div className="pied-carte">
        <span className="attenue">
          {jourChoisi
            ? `${dateDe(jourChoisi.jour)} — ${jourChoisi.temps > 0 ? `${heures(jourChoisi.temps)}, charge ${Math.round(jourChoisi.charge)}` : "repos"}`
            : "Toucher un jour pour le détail"}
        </span>
        <span className="echelle">
          Moins {COULEURS_NIVEAUX.map((c) => <i key={c} style={{ background: c }} />)} Plus
        </span>
      </div>
      {p && (
        <p className="projection">
          À ce rythme, {p.annee} finira à {Math.floor(p.tempsProjete / 3600)} h d'effort
          {p.sportPrincipal && p.distanceProjetee > 0
            ? `, dont ${distance(p.distanceProjetee)} de ${nomDuSport(p.sportPrincipal).toLowerCase()}`
            : ""}{" "}
          — {Math.floor(p.tempsADate / 3600)} h à ce jour.
        </p>
      )}
    </Carte>
  )
}

// MARK: - Intensité

const NOMS_ZONES = ["Échauffement", "Facile", "Aérobie", "Seuil", "Maximum"]

function CarteIntensite({ i, g }: { i: Intensite; g: Granularite }) {
  const [ref, largeur] = useLargeur()
  const total = i.secondes.reduce((s, v) => s + v, 0)
  const pr = profil(i)
  const pc = (v: number) => `${Math.round(v * 100)} %`
  const h = (de: number, a: number) => heures(i.secondes.slice(de - 1, a).reduce((s, v) => s + v, 0))

  const H = 130, DROITE = 30
  const l = largeur - DROITE
  const hauts = i.creneaux.map((c) => c.secondes.reduce((s, v) => s + v, 0) / 3600)
  const max = Math.max(1, ...hauts)
  const pasX = l / Math.max(i.creneaux.length, 1)
  const lb = Math.max(2, pasX * 0.7)

  return (
    <Carte titre="Intensité" sousTitre="Le temps passé dans chaque zone de fréquence cardiaque">
      {total === 0 ? (
        <p className="attenue">Aucune sortie de la période n'a de zones Garmin.</p>
      ) : (
        <>
          <div className="grille-chiffres">
            <Chiffre etiquette="Facile · Z1–2" valeur={pc(part(i, 1, 2))}>{h(1, 2)}</Chiffre>
            <Chiffre etiquette="Modéré · Z3" valeur={pc(part(i, 3, 3))}>{h(3, 3)}</Chiffre>
            <Chiffre etiquette="Intense · Z4–5" valeur={pc(part(i, 4, 5))}>{h(4, 5)}</Chiffre>
            {pr && (
              <div className="chiffre-stats">
                <span className="etiquette">Répartition</span>
                <span className="etat">{pr.nom}</span>
                <span className="detail">{pr.explication}</span>
              </div>
            )}
          </div>
          <div className="barre-zones">
            {i.secondes.map((s, z) =>
              s > 0 ? (
                <span key={z} style={{ flexGrow: s, background: COULEURS_ZONES[z] }}>
                  {s / total > 0.08 ? pc(s / total) : ""}
                </span>
              ) : null,
            )}
          </div>
          <div className="legende-zones">
            {i.secondes.map((s, z) => (
              <span key={z}>
                <i style={{ background: COULEURS_ZONES[z] }} />
                Z{z + 1} {NOMS_ZONES[z]} <b>{heures(s)}</b>
              </span>
            ))}
          </div>
          <div ref={ref} className="dessin">
            <svg width={largeur} height={H + 18} className="svg-stats">
              {[0, max / 2, max].map((v) => (
                <g key={v}>
                  <line x1={0} x2={l} y1={H - (v / max) * H} y2={H - (v / max) * H} className="grille" />
                  <text x={largeur - 2} y={H - (v / max) * H + 4} textAnchor="end" className="axe">{Math.round(v)} h</text>
                </g>
              ))}
              {i.creneaux.map((c, k) => {
                let base = H
                return (
                  <g key={c.debut}>
                    {c.secondes.map((s, z) => {
                      const hh = (s / 3600 / max) * H
                      base -= hh
                      return hh > 0 ? (
                        <rect key={z} x={k * pasX + (pasX - lb) / 2} y={base} width={lb} height={hh} fill={COULEURS_ZONES[z]} />
                      ) : null
                    })}
                    {(g === "mois" || dateDuJour(c.debut).getUTCDate() <= 7) &&
                      (g === "semaine" || i.creneaux.length <= 8 || k % 2 === 0) && (
                        <text x={k * pasX + pasX / 2} y={H + 14} textAnchor="middle" className="axe">{moisDe(c.debut)}</text>
                      )}
                  </g>
                )
              })}
            </svg>
          </div>
          <p className="note-stats">
            {i.couvertes} sorties sur {i.nombre} ont des zones Garmin ; les autres ne comptent pas
            ici : une FC moyenne ne dit pas comment le temps s'est réparti.
          </p>
        </>
      )}
    </Carte>
  )
}

// MARK: - Progression

const NOMS_RECORDS: { [k in Record_["type"]]: string } = {
  distance: "La plus longue",
  denivele: "La plus grimpante",
  duree: "La plus longue en temps",
  vitesse: "La plus rapide",
}

function formatRecord(r: Record_): string {
  switch (r.type) {
    case "distance": return distance(r.valeur)
    case "denivele": return denivele(r.valeur)
    case "duree": return duree(r.valeur)
    case "vitesse": return allureOuVitesse(r.sortie.sport_type_raw, r.valeur * 1000, 1000)?.valeur ?? "—"
  }
}

function nomRecord(r: Record_): string {
  return r.type === "vitesse" && enKmEffort(r.sortie.sport_type_raw)
    ? "La plus rapide (km-effort)"
    : NOMS_RECORDS[r.type]
}

function ListeRecords({ records, onOuvrir }: { records: Record_[]; onOuvrir: (uuid: string) => void }) {
  return (
    <ul className="liste liste-records">
      {records.map((r) => (
        <li key={r.type}>
          <button className="ligne" onClick={() => onOuvrir(r.sortie.uuid)}>
            <div className="ligne-tete">
              <span className="titre">{r.sortie.name}</span>
              <span className="petit valeur-record">{formatRecord(r)}</span>
            </div>
            <div className="attenue petit">
              {nomRecord(r)} · {dateDe(jourDe(r.sortie))}
            </div>
          </button>
        </li>
      ))}
    </ul>
  )
}

const MESURES_PROGRESSION: Mesure[] = ["vitesse", "fc", "efficacite"]

function CarteProgression({ p, sports, sport, setSport, onOuvrir }: {
  p: Progression | null
  sports: string[]
  sport: string | null
  setSport: (s: string) => void
  onOuvrir: (uuid: string) => void
}) {
  const [ref, largeur] = useLargeur()
  const [mesure, setMesure] = useState<Mesure>("vitesse")
  const [choisi, setChoisi] = useState<string | null>(null)

  const selecteur = sport && (
    <select className="choix-sport" value={sport} onChange={(e) => setSport(e.target.value)} aria-label="Sport">
      {sports.map((s) => <option key={s} value={s}>{nomDuSport(s)}</option>)}
    </select>
  )

  if (!p || !sport) {
    return (
      <Carte titre="Progression">
        <p className="attenue">Pas assez de sorties d'un même sport sur la période.</p>
      </Carte>
    )
  }

  const aPied = ["run", "trailRun", "walk", "hike", "swim"].includes(sport)
  const nomMesure = (m: Mesure) => (m === "vitesse" ? (aPied ? "Allure" : "Vitesse") : m === "fc" ? "FC moy." : "Efficacité")
  const format = (v: number) =>
    mesure === "vitesse"
      ? allureOuVitesse(sport, v * 1000, 1000)?.valeur ?? "—"
      : mesure === "fc"
        ? `${Math.round(v)} bpm`
        : `${v.toLocaleString("fr-FR", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} m/batt.`

  const points = p.points.filter((pt) => valeur(pt, mesure) !== null)
  const valeurs = points.map((pt) => valeur(pt, mesure)!)
  const moyenne = valeurs.length ? valeurs.reduce((s, v) => s + v, 0) / valeurs.length : null
  const t = tendance(p.points, mesure)
  const pointChoisi = points.find((pt) => pt.sortie.uuid === choisi)
  const plusHautMieux = mesure !== "fc"
  const mieux = t ? (plusHautMieux ? t.ecart > 0 : t.ecart < 0) : false
  const plat = t ? Math.abs(t.ecart) < 1 : true

  const H = 190, DROITE = 62
  const l = largeur - DROITE
  const bas = Math.min(...valeurs), haut = Math.max(...valeurs)
  const marge = Math.max((haut - bas) * 0.1, haut * 0.02)
  const y0 = bas - marge, y1 = haut + marge
  const j0 = points[0]?.jour ?? 0, j1 = points[points.length - 1]?.jour ?? 1
  const x = (j: number) => 6 + ((j - j0) / Math.max(j1 - j0, 1)) * (l - 12)
  const y = (v: number) => H - ((v - y0) / Math.max(y1 - y0, 1e-9)) * H
  const reperes = reperesMois(j0, j1, x, l)

  const suivre = (ev: EvenementPointeur<SVGSVGElement>) => {
    const rect = ev.currentTarget.getBoundingClientRect()
    const px = ev.clientX - rect.left
    const proche = points.reduce<typeof points[number] | null>(
      (m, pt) => (!m || Math.abs(x(pt.jour) - px) < Math.abs(x(m.jour) - px) ? pt : m), null)
    setChoisi(proche?.sortie.uuid ?? null)
  }

  let note =
    mesure === "efficacite"
      ? "Efficacité : mètres parcourus par battement de cœur. Elle monte quand on va plus vite pour le même effort — le vrai signe d'une forme qui progresse."
      : mesure === "fc"
        ? "FC moyenne de chaque sortie : plus basse à allure égale, c'est bon signe."
        : "Chaque point est une sortie ; toucher pour la voir, puis l'ouvrir."
  if (enKmEffort(sport) && mesure !== "fc")
    note += " En km-effort : 100 m de D+ comptent pour 1 km, sans quoi une sortie en montagne paraîtrait lente."

  return (
    <Carte titre="Progression" sousTitre="Chaque sortie de la période, et la tendance qui les traverse" droite={selecteur}>
      <Segmente
        etiquette="Mesure"
        choix={MESURES_PROGRESSION.map((m) => ({ clef: m, nom: nomMesure(m) }))}
        valeur={mesure}
        onChange={(m) => { setMesure(m); setChoisi(null) }}
      />
      <div className="grille-chiffres">
        {pointChoisi ? (
          <div className="chiffre-stats">
            <span className="etiquette">{dateDe(pointChoisi.jour)}</span>
            <span className="valeur">{format(valeur(pointChoisi, mesure)!)}</span>
            <button className="lien-sortie" onClick={() => onOuvrir(pointChoisi.sortie.uuid)}>
              {pointChoisi.sortie.name} ›
            </button>
          </div>
        ) : (
          <Chiffre etiquette="Moyenne" valeur={moyenne === null ? "—" : format(moyenne)}>{valeurs.length} sorties</Chiffre>
        )}
        {t && (
          <div className="chiffre-stats">
            <span className="etiquette">Tendance</span>
            <span className="valeur tendance">{format(t.debut)} → {format(t.fin)}</span>
            <span className="detail">
              <span className={"evolution" + (plat ? "" : mieux ? " hausse" : " baisse")}>
                {t.ecart > 0 ? "↑ " : t.ecart < 0 ? "↓ " : ""}{Math.round(Math.abs(t.ecart))} %
              </span>{" "}
              {plat ? "stable" : mieux ? "en progrès" : "en recul"}
            </span>
          </div>
        )}
      </div>
      {points.length > 0 && (
        <div ref={ref} className="dessin">
          <svg width={largeur} height={H + 18} className="svg-stats"
            onPointerMove={suivre} onPointerDown={suivre}>
            {[y0 + marge, (y0 + y1) / 2, y1 - marge].map((v) => (
              <g key={v}>
                <line x1={0} x2={l} y1={y(v)} y2={y(v)} className="grille" />
                <text x={largeur - 2} y={y(v) + 4} textAnchor="end" className="axe">{format(v)}</text>
              </g>
            ))}
            {points.map((pt) => (
              <circle key={pt.sortie.uuid} cx={x(pt.jour)} cy={y(valeur(pt, mesure)!)}
                r={pt.sortie.uuid === choisi ? 6 : 3.5}
                fill="var(--accent)" fillOpacity={pt.sortie.uuid === choisi ? 1 : 0.55} />
            ))}
            {t && (
              <line x1={x(t.jourDebut)} y1={y(t.debut)} x2={x(t.jourFin)} y2={y(t.fin)}
                stroke="var(--texte)" strokeOpacity={0.55} strokeWidth={2} strokeDasharray="5 4" />
            )}
            {reperes.map((m) => <text key={m.x} x={m.x} y={H + 14} className="axe">{m.texte}</text>)}
          </svg>
        </div>
      )}
      <p className="note-stats">{note}</p>

      <h5 className="sous-titre-stats">Records de tous les temps</h5>
      <ListeRecords records={p.records} onOuvrir={onOuvrir} />

      {p.materiel.length > 0 && (
        <>
          <h5 className="sous-titre-stats">Matériel</h5>
          <ul className="liste sans-chevron">
            {p.materiel.map((m) => (
              <li className="ligne" key={m.id}>
                <div className="ligne-tete">
                  <span className="titre">{m.nom}</span>
                  <span className="petit">{distance(m.distance)}</span>
                </div>
                <div className="attenue petit">{m.nombre} sortie{m.nombre > 1 ? "s" : ""} sur la période</div>
              </li>
            ))}
          </ul>
          <p className="note-stats">Distance de toutes les sorties faites avec, recalculée dans Cairn.</p>
        </>
      )}
    </Carte>
  )
}

// MARK: - Volume et semaine

type MesureVolume = "distance" | "denivele" | "temps"
const MESURES_VOLUME: { clef: MesureVolume; nom: string }[] = [
  { clef: "distance", nom: "Distance" },
  { clef: "denivele", nom: "D+" },
  { clef: "temps", nom: "Temps" },
]

function formatVolume(m: MesureVolume, v: number): string {
  if (m === "distance") return `${Math.round(v / 1000)} km`
  if (m === "denivele") return `${Math.round(v)} m`
  return `${Math.round(v / 3600)} h`
}

function CarteVolume({ s, comparaison, mesure, setMesure }: {
  s: Statistiques
  comparaison: string
  mesure: MesureVolume
  setMesure: (m: MesureVolume) => void
}) {
  const [ref, largeur] = useLargeur()
  const H = 140, DROITE = 44
  const l = largeur - DROITE
  const v = (c: Statistiques["creneaux"][number]) => (mesure === "distance" ? c.distance : mesure === "denivele" ? c.denivele : c.temps)
  const va = (c: Statistiques["creneaux"][number]) => (mesure === "distance" ? c.distanceAvant : mesure === "denivele" ? c.deniveleAvant : c.tempsAvant)
  const max = Math.max(1, ...s.creneaux.map((c) => Math.max(v(c), va(c))))
  const pasX = l / s.creneaux.length
  const lb = Math.max(2, pasX * 0.65)
  const y = (x: number) => H - (x / max) * H
  const ligne = s.creneaux.map((c, k) => `${k ? "L" : "M"}${(k * pasX + pasX / 2).toFixed(1)} ${y(va(c)).toFixed(1)}`).join(" ")
  return (
    <Carte titre={s.granularite === "semaine" ? "Par semaine" : "Par mois"} sousTitre={`En trait, ${comparaison}`}>
      <Segmente etiquette="Mesure" choix={MESURES_VOLUME} valeur={mesure} onChange={setMesure} />
      <div ref={ref} className="dessin">
        <svg width={largeur} height={H + 18} className="svg-stats">
          {[0, max / 2, max].map((g) => (
            <g key={g}>
              <line x1={0} x2={l} y1={y(g)} y2={y(g)} className="grille" />
              <text x={largeur - 2} y={y(g) + 4} textAnchor="end" className="axe">{formatVolume(mesure, g)}</text>
            </g>
          ))}
          {s.creneaux.map((c, k) => (
            <g key={c.debut}>
              <rect x={k * pasX + (pasX - lb) / 2} y={y(v(c))} width={lb} height={H - y(v(c))} rx={2} fill="var(--accent)">
                <title>{formatVolume(mesure, v(c))}</title>
              </rect>
              {(s.granularite === "mois" ? s.creneaux.length <= 8 || k % 2 === 0 : dateDuJour(c.debut).getUTCDate() <= 7) && (
                <text x={k * pasX + pasX / 2} y={H + 14} textAnchor="middle" className="axe">{moisDe(c.debut)}</text>
              )}
            </g>
          ))}
          <path d={ligne} fill="none" stroke="var(--texte-2)" strokeWidth={1.5} />
          {s.creneaux.map((c, k) => (
            <circle key={c.debut} cx={k * pasX + pasX / 2} cy={y(va(c))} r={2.5} fill="var(--carte)" stroke="var(--texte-2)" strokeWidth={1.5} />
          ))}
        </svg>
      </div>
    </Carte>
  )
}

const JOURS = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."]

function CarteSemaine({ sorties, mesure }: { sorties: Sortie[]; mesure: MesureVolume }) {
  const [ref, largeur] = useLargeur()
  const { celleCi, derniere } = semaines(sorties)
  const v = (p: { distance: number; denivele: number; temps: number }) =>
    mesure === "distance" ? p.distance : mesure === "denivele" ? p.denivele : p.temps
  const H = 120, DROITE = 44
  const l = largeur - DROITE
  const max = Math.max(1, ...celleCi.map(v), ...derniere.map(v))
  const x = (i: number) => 8 + (i / 6) * (l - 16)
  const y = (x: number) => H - (x / max) * H
  const trace = (pts: typeof celleCi) => pts.map((p, i) => `${i ? "L" : "M"}${x(p.jour)} ${y(v(p))}`).join(" ")
  const aujourdHui = celleCi[celleCi.length - 1]
  const memeJour = derniere.find((p) => p.jour === aujourdHui?.jour)
  let phrase = ""
  if (aujourdHui && memeJour) {
    const d = v(aujourdHui) - v(memeJour)
    const jour = JOURS[aujourdHui.jour]
    const seuil = mesure === "distance" ? 50 : mesure === "denivele" ? 0.5 : 180
    phrase = Math.abs(d) < seuil
      ? `Au même point que ${jour} dernier.`
      : `${formatVolume(mesure, Math.abs(d))} de ${d > 0 ? "plus" : "moins"} que ${jour} dernier.`
  }
  return (
    <Carte titre="Cette semaine" sousTitre="Cumul jour par jour, contre la semaine dernière">
      <div ref={ref} className="dessin">
        <svg width={largeur} height={H + 18} className="svg-stats">
          {[0, max / 2, max].map((g) => (
            <g key={g}>
              <line x1={0} x2={l} y1={y(g)} y2={y(g)} className="grille" />
              <text x={largeur - 2} y={y(g) + 4} textAnchor="end" className="axe">{formatVolume(mesure, g)}</text>
            </g>
          ))}
          <path d={trace(derniere)} fill="none" stroke="var(--texte-2)" strokeWidth={1.5} />
          <path d={trace(celleCi)} fill="none" stroke="var(--accent)" strokeWidth={3} strokeLinejoin="round" />
          {celleCi.map((p) => <circle key={p.jour} cx={x(p.jour)} cy={y(v(p))} r={3} fill="var(--accent)" />)}
          {JOURS.map((j, i) => <text key={j} x={x(i)} y={H + 14} textAnchor="middle" className="axe">{j}</text>)}
        </svg>
      </div>
      {phrase && <p className="note-stats">{phrase}</p>}
    </Carte>
  )
}

// MARK: - Poids

/// La courbe du poids : une ligne, et non des barres — un poids est une
/// mesure continue. Masquée tant que `POIDS_MASQUE` l'est.
function CourbePoids({ pesees }: { pesees: { jour: string; kg: number }[] }) {
  if (pesees.length < 2) return null
  const LARGEUR = 320, HAUTEUR = 90
  const kgs = pesees.map((p) => p.kg)
  const bas = Math.min(...kgs), haut = Math.max(...kgs)
  const amplitude = Math.max(haut - bas, 1)
  const min = (haut + bas) / 2 - amplitude / 2
  const premier = new Date(pesees[0].jour).getTime()
  const etendue = Math.max(new Date(pesees[pesees.length - 1].jour).getTime() - premier, 1)
  const x = (jour: string) => ((new Date(jour).getTime() - premier) / etendue) * LARGEUR
  const y = (kg: number) => HAUTEUR - ((kg - min) / amplitude) * (HAUTEUR - 8) - 4
  const trace = pesees.map((p, i) => `${i ? "L" : "M"}${x(p.jour).toFixed(1)} ${y(p.kg).toFixed(1)}`).join(" ")
  const format = (v: number) => `${v.toLocaleString("fr-FR", { maximumFractionDigits: 1 })} kg`
  return (
    <Carte titre="Poids" sousTitre={`de ${format(bas)} à ${format(haut)}`}>
      <svg className="courbe-poids" viewBox={`0 0 ${LARGEUR} ${HAUTEUR}`} preserveAspectRatio="none" role="img">
        <path d={`${trace} L${LARGEUR} ${HAUTEUR} L0 ${HAUTEUR} Z`} fill="var(--accent)" fillOpacity="0.14" />
        <path d={trace} fill="none" stroke="var(--accent)" strokeWidth="2" vectorEffect="non-scaling-stroke" />
      </svg>
    </Carte>
  )
}

// MARK: - L'écran

const CLE_SPORT = "cairn.stats.sport"

/// Par pages de mille : Supabase n'en rend pas plus d'un coup, et la
/// bibliothèque en compte déjà près de neuf cents.
async function toutesLesSorties(): Promise<Sortie[]> {
  const PAGE = 1000
  const toutes: Sortie[] = []
  for (let debut = 0; ; debut += PAGE) {
    const { data, error } = await supabase
      .from("activity")
      .select(
        "uuid, name, sport_type_raw, start_date, start_local_date, distance, moving_time, total_elevation_gain, average_speed, average_heartrate, hr_zone_floors, hr_zone_seconds, gear_id",
      )
      .is("deleted_at", null)
      .order("start_local_date", { ascending: true })
      .order("uuid")
      .range(debut, debut + PAGE - 1)
    if (error) throw error
    toutes.push(...(data as unknown as Sortie[]))
    if (!data || data.length < PAGE) return toutes
  }
}

export function Stats({ onOuvrir }: { onOuvrir: (uuid: string) => void }) {
  const [periode, setPeriode] = useState<Periode>("3mois")
  const [mesure, setMesure] = useState<MesureVolume>("distance")
  const [sportRetenu, setSportRetenu] = useState<string | null>(() => {
    try { return localStorage.getItem(CLE_SPORT) } catch { return null }
  })

  // Toute la bibliothèque, une fois : la forme se calcule depuis la première
  // sortie, les séries et les records portent sur tout l'historique, et le
  // changement de période n'a plus rien à recharger.
  const { data, error, isPending } = useQuery({
    queryKey: ["stats-bibliotheque"],
    queryFn: async () => {
      const [sorties, materiel, poids] = await Promise.all([
        toutesLesSorties(),
        supabase.from("gear").select("strava_id, name").is("deleted_at", null),
        POIDS_MASQUE
          ? Promise.resolve({ data: [], error: null })
          : supabase.from("weight_entry").select("date_key_raw, weight_kg").is("deleted_at", null).order("date_key_raw"),
      ])
      if (materiel.error) throw materiel.error
      if (poids.error) throw poids.error
      return {
        sorties,
        materiel: new Map((materiel.data as { strava_id: string; name: string }[]).map((g) => [g.strava_id, g.name])),
        pesees: (poids.data as { date_key_raw: string; weight_kg: number }[]).map((p) => ({ jour: p.date_key_raw, kg: p.weight_kg })),
      }
    },
  })

  if (isPending) return <Chargement />
  if (error) return <p className="erreur">{(error as Error).message}</p>

  const s = calculer(data.sorties, periode)
  const q = quotidien(data.sorties)
  const forme = serie(q)
  const r = regularite(data.sorties, q, s.debutPeriode)
  const sports = sportsSuivis(data.sorties, s.debutPeriode)
  const sport = sports.find((x) => x === sportRetenu) ?? sports[0] ?? null
  const prog = sport ? progression(data.sorties, sport, s.debutPeriode, data.materiel) : null
  const comparaison = periode === "annee" ? "l'année précédente" : "la période précédente"
  const pesees = data.pesees.filter((p) => p.jour >= dateDuJour(s.debutPeriode).toISOString().slice(0, 10))

  return (
    <div className="page-stats">
      <div className="periode-stats">
        <Segmente etiquette="Période" choix={PERIODES} valeur={periode} onChange={setPeriode} />
      </div>

      {s.totaux.nombre === 0 ? (
        <p className="attenue">Aucune sortie sur cette période.</p>
      ) : (
        <>
          <Carte titre="Cumuls" sousTitre="La distance se lit par sport : additionner des sports différents n'aurait pas de sens.">
            <div className="grille-chiffres">
              <Chiffre etiquette="Sorties" valeur={String(s.totaux.nombre)}>
                <Evolution valeur={ecart(s.totaux.nombre, s.comparaison.nombre)} />
              </Chiffre>
              <Chiffre etiquette="Temps" valeur={duree(s.totaux.temps)}>
                <Evolution valeur={ecart(s.totaux.temps, s.comparaison.temps)} />
              </Chiffre>
              <Chiffre etiquette="Dénivelé" valeur={denivele(s.totaux.denivele)}>
                <Evolution valeur={ecart(s.totaux.denivele, s.comparaison.denivele)} />
              </Chiffre>
              <Chiffre etiquette="Par semaine" valeur={heures(r.heuresParSemaine * 3600)}>
                {r.joursActifs} jours actifs
              </Chiffre>
            </div>
            <p className="note-stats">Écarts avec {comparaison}, arrêtée au même point.</p>
          </Carte>

          <CarteForme points={forme} debut={s.debutPeriode} estimees={q.estimees} nombre={q.nombre} />
          <CarteRegularite r={r} />
          <CarteIntensite i={intensite(data.sorties, s.creneaux.map((c) => c.debut), s.granularite)} g={s.granularite} />
          <CarteProgression
            p={prog} sports={sports} sport={sport} onOuvrir={onOuvrir}
            setSport={(x) => {
              setSportRetenu(x)
              try { localStorage.setItem(CLE_SPORT, x) } catch { /* sans mémoire, tant pis */ }
            }}
          />
          <CarteVolume s={s} comparaison={comparaison} mesure={mesure} setMesure={setMesure} />
          <CarteSemaine sorties={data.sorties} mesure={mesure} />

          {!POIDS_MASQUE && <CourbePoids pesees={pesees} />}

          <Carte titre="Par sport">
            <ul className="liste sans-chevron">
              {s.sports.map((t) => (
                <li className="ligne avec-icone ligne-mail" key={t.sport}>
                  <span className="pastille-sport">
                    <Symbole nom={symboleDuSport(t.sport)} taille={17} couleur="var(--accent)" />
                  </span>
                  <div>
                    <div className="ligne-tete">
                      <span className="titre">{nomDuSport(t.sport)}</span>
                      <span className="attenue petit">{t.nombre} sortie{t.nombre > 1 ? "s" : ""}</span>
                    </div>
                    <div className="attenue petit">
                      {[t.distance > 0 ? distance(t.distance) : null, duree(t.temps), t.denivele > 0 ? `${denivele(t.denivele)} D+` : null]
                        .filter(Boolean).join(" · ")}
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          </Carte>

          <CarteMeilleursEfforts onOuvrir={onOuvrir} />

          <Carte titre="Records de la période">
            <ListeRecords records={s.records} onOuvrir={onOuvrir} />
          </Carte>
        </>
      )}
    </div>
  )
}
