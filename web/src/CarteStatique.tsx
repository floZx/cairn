import { useEffect, useMemo, useRef, useState } from "react"
import { FONDS, fondRetenu, urlDeTuile, type Fond } from "./fonds"
import type { Coordonnee } from "./track"

/// Une vraie carte, sans moteur de rendu.
///
/// La `Miniature` qu'elle remplace dans le fil dessinait la trace toute seule,
/// et son commentaire disait pourquoi : une carte par ligne, ce sont autant de
/// moteurs. C'est vrai de MapLibre, qui ouvre **un contexte WebGL par carte**
/// là où un navigateur en plafonne une quinzaine — un fil de vingt sorties les
/// épuise, et les dernières cartes ne s'affichent plus du tout.
///
/// Mais une carte de fil n'a besoin d'aucun moteur : on ne la déplace pas, on
/// ne zoome pas dedans, on la regarde. Les tuiles sont donc posées en `<img>`,
/// la trace par-dessus en SVG. Pas de WebGL, pas de plafond, et le navigateur
/// fait ce qu'il sait faire de mieux — charger des images et les jeter quand
/// elles sortent de l'écran.
///
/// Le fond est celui que la fiche a retenu : se retrouver sur un plan dans le
/// fil et sur une photo aérienne dans le détail donnerait deux applications.

/// Le côté d'une tuile, chez tout le monde.
const TUILE = 256

/// Web Mercator, en pixels au zoom donné — la projection des tuiles, et donc
/// la seule qui fasse tomber la trace au bon endroit dessus.
function enPixels([lon, lat]: Coordonnee, zoom: number): [number, number] {
  const echelle = TUILE * 2 ** zoom
  const x = ((lon + 180) / 360) * echelle
  const phi = (lat * Math.PI) / 180
  const y =
    ((1 - Math.log(Math.tan(phi) + 1 / Math.cos(phi)) / Math.PI) / 2) * echelle
  return [x, y]
}

/// Le plus grand zoom auquel la trace tient encore dans le cadre.
///
/// Cherché par essais successifs du plus fin au plus large : la formule
/// inverse existe, mais elle demande de traiter à part le cas d'une trace
/// d'étendue nulle — un tapis, un bassin mal capté — et l'essai s'en accommode
/// sans rien de spécial.
function zoomQuiTient(
  trace: Coordonnee[],
  largeur: number,
  hauteur: number,
  marge: number,
): number {
  const cadreL = Math.max(largeur - 2 * marge, 1)
  const cadreH = Math.max(hauteur - 2 * marge, 1)
  for (let zoom = 17; zoom > 1; zoom--) {
    let minX = Infinity
    let maxX = -Infinity
    let minY = Infinity
    let maxY = -Infinity
    for (const point of trace) {
      const [x, y] = enPixels(point, zoom)
      if (x < minX) minX = x
      if (x > maxX) maxX = x
      if (y < minY) minY = y
      if (y > maxY) maxY = y
    }
    if (maxX - minX <= cadreL && maxY - minY <= cadreH) return zoom
  }
  return 2
}

export function CarteStatique({
  trace,
  couleur,
  /// De l'air autour de la trace, pour qu'elle ne touche pas les bords.
  marge = 16,
  epaisseur = 3,
  /// Un voile sombre entre les tuiles et la trace.
  ///
  /// Pour la vignette posée sur une photo, où la carte est si petite qu'un nom
  /// de ville en occupe le quart : « ST-ÉTIENNE » y ressortait plus que le
  /// tracé, alors que la vignette est là pour dire le parcours, la photo
  /// disant déjà le lieu. Le voile fait reculer le plan d'un cran sans
  /// l'effacer.
  ///
  /// Un élément et non un filtre : les tuiles de papier en portent déjà un en
  /// thème sombre, et deux règles de `filter` se remplacent au lieu de se
  /// composer.
  voile = false,
}: {
  trace: Coordonnee[]
  couleur: string
  marge?: number
  epaisseur?: number
  voile?: boolean
}) {
  const boite = useRef<HTMLDivElement>(null)
  const [taille, setTaille] = useState<{ l: number; h: number } | null>(null)
  const [fond] = useState<Fond>(fondRetenu)

  // Mesurée plutôt que devinée : la bande fait toute la largeur de l'écran, et
  // poser les tuiles demande des pixels réels — une tuile placée d'après une
  // largeur supposée tombe à côté de la trace.
  useEffect(() => {
    const cible = boite.current
    if (!cible) return
    const observateur = new ResizeObserver(([entree]) => {
      const { width, height } = entree.contentRect
      if (width > 0 && height > 0) setTaille({ l: width, h: height })
    })
    observateur.observe(cible)
    return () => observateur.disconnect()
  }, [])

  const plan = useMemo(() => {
    if (!taille || trace.length < 2) return null
    const zoom = zoomQuiTient(trace, taille.l, taille.h, marge)
    const points = trace.map((p) => enPixels(p, zoom))
    const xs = points.map(([x]) => x)
    const ys = points.map(([, y]) => y)
    const centreX = (Math.min(...xs) + Math.max(...xs)) / 2
    const centreY = (Math.min(...ys) + Math.max(...ys)) / 2
    // Le coin haut-gauche du cadre, en pixels du monde : tout le reste s'en
    // déduit, tuiles comme trace.
    const gauche = centreX - taille.l / 2
    const haut = centreY - taille.h / 2

    const tuiles: { cle: string; url: string; x: number; y: number }[] = []
    const max = 2 ** zoom
    for (let tx = Math.floor(gauche / TUILE); tx <= Math.floor((gauche + taille.l) / TUILE); tx++) {
      for (let ty = Math.floor(haut / TUILE); ty <= Math.floor((haut + taille.h) / TUILE); ty++) {
        // Hors du monde en latitude : il n'y a rien à demander, et la tuile
        // manquante vaut mieux qu'une requête qui rendra 404.
        if (ty < 0 || ty >= max) continue
        // En longitude le monde boucle, lui : une trace près du 180ᵉ méridien
        // reprend de l'autre côté.
        const monde = ((tx % max) + max) % max
        tuiles.push({
          cle: `${tx}/${ty}`,
          url: urlDeTuile(fond, zoom, monde, ty),
          x: tx * TUILE - gauche,
          y: ty * TUILE - haut,
        })
      }
    }
    return {
      tuiles,
      trait: points.map(([x, y]) => [x - gauche, y - haut] as const),
    }
  }, [taille, trace, marge, fond])

  return (
    <div className="carte-statique" ref={boite}>
      {plan?.tuiles.map((t) => (
        <img
          key={t.cle}
          className={FONDS[fond].papier ? "tuile-fil papier" : "tuile-fil"}
          src={t.url}
          alt=""
          width={TUILE}
          height={TUILE}
          style={{ left: t.x, top: t.y }}
          // Les tuiles hors de l'écran ne partent jamais : c'est ce qui rend un
          // fil de cinquante sorties aussi léger qu'une seule.
          loading="lazy"
          decoding="async"
          aria-hidden
        />
      ))}
      {voile && <div className="voile-carte" aria-hidden />}
      {plan && plan.trait.length > 1 && (
        <svg className="trace-fil" aria-hidden>
          <polyline
            points={plan.trait.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ")}
            fill="none"
            stroke={couleur}
            strokeWidth={epaisseur}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      )}
    </div>
  )
}
