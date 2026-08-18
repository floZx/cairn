import { useMemo } from "react"
import { projeter, type Coordonnee } from "./track"

/// La forme d'une trace, dessinée sans carte.
///
/// La `TrackThumbnail` du Mac, et pour la raison qu'elle donne : une carte par
/// activité dans une liste, ce sont des centaines de requêtes de tuiles et un
/// moteur de rendu par ligne. La trace simplifiée voyage déjà avec la ligne, et
/// quarante points suffisent à reconnaître une boucle, un aller-retour ou un
/// huit.
///
/// Le repère est fixe et le SVG se met à l'échelle tout seul
/// (`preserveAspectRatio`) : mesurer la largeur réelle demanderait un
/// observateur de redimensionnement par vignette, et une trace projetée dans un
/// cadre puis étirée par la feuille de style ressortirait déformée — exactement
/// ce que la correction de longitude cherche à éviter.
const REPERE = { largeur: 300, hauteur: 160 }

export function Miniature({
  trace,
  couleur,
  epaisseur = 2.6,
}: {
  trace: Coordonnee[]
  /// La couleur du sport, telle que `couleurDuSport` la rend.
  couleur: string
  epaisseur?: number
}) {
  // De l'air autour de la trace : sans marge, un aller-retour qui touche le
  // bord du cadre se fait couper la moitié de son trait, et une boucle collée
  // aux quatre côtés de sa bande se lit comme une trace rognée.
  const points = useMemo(
    () => projeter(trace, REPERE.largeur, REPERE.hauteur, 12),
    [trace],
  )
  if (points.length < 2) return null

  return (
    <svg
      className="miniature-trace"
      viewBox={`0 0 ${REPERE.largeur} ${REPERE.hauteur}`}
      preserveAspectRatio="xMidYMid meet"
      aria-hidden
    >
      <polyline
        points={points.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ")}
        fill="none"
        stroke={couleur}
        strokeWidth={epaisseur}
        // L'épaisseur est en pixels d'écran, pas en unités du repère : le même
        // dessin sert une bande pleine largeur et une vignette de quatre-vingts
        // pixels, et sans cela le trait maigrissait avec la boîte — dans le
        // coin d'une photo, la trace n'était plus qu'un cheveu.
        vectorEffect="non-scaling-stroke"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}
