/// L'icône et la couleur d'un sport, reprises de `SportType` et de
/// `SportLabel` côté Swift.
///
/// La règle du Mac vient avec : **seule l'icône porte la couleur, le texte
/// reste noir**. `Label(_:systemImage:)` teinte les deux ensemble, ce qui dans
/// une liste de noms d'activités donnerait des lignes entières en couleur —
/// illisible, et faux : la couleur identifie le sport, pas le nom de la
/// sortie.
///
/// Les quatre vélos partagent le même dessin, comme là-bas : rien ne
/// distingue un VTT d'un gravel en quelques traits, et c'est la couleur qui
/// les sépare.

/// Le nom de la variable CSS qui porte la couleur du sport.
///
/// En CSS et non en dur ici, parce que chaque teinte a deux valeurs — claire
/// et sombre — et qu'un composant ne sait pas laquelle s'applique.
export function couleurDuSport(brut: string): string {
  const connus = new Set([
    "ride",
    "eBikeRide",
    "mountainBikeRide",
    "gravelRide",
    "run",
    "trailRun",
    "walk",
    "hike",
    "swim",
    "nordicSki",
    "alpineSki",
    "rowing",
    "workout",
  ])
  // Un sport inconnu ne dit rien, donc il n'a rien à colorer.
  return connus.has(brut) ? `var(--sport-${brut})` : "var(--texte-2)"
}

/// Le symbole du Mac pour chaque sport — `SportType.symbolName`, le même nom.
///
/// Les vrais symboles SF et plus des approximations à la main : ceux-ci
/// étaient « pas ouf », signalé. Rendus depuis AppKit en PNG à trois fois leur
/// taille d'affichage (`public/sf`), et posés en masque pour prendre la couleur
/// du sport — voir `Symbole`. L'aviron prend `figure.outdoor.rowing` :
/// `figure.rowing`, que le Mac demande, n'existe pas dans les symboles.
const SYMBOLES: Record<string, string> = {
  ride: "bicycle",
  eBikeRide: "bicycle",
  mountainBikeRide: "bicycle",
  gravelRide: "bicycle",
  run: "figure.run",
  trailRun: "figure.run",
  walk: "figure.walk",
  hike: "figure.hiking",
  swim: "figure.pool.swim",
  nordicSki: "figure.skiing.crosscountry",
  alpineSki: "figure.skiing.downhill",
  rowing: "figure.outdoor.rowing",
  workout: "figure.strengthtraining.traditional",
}

/// Le nom du symbole d'un sport, pour qui le pose lui-même.
export function symboleDuSport(sport: string): string {
  return SYMBOLES[sport] ?? "sparkles"
}

export function IconeSport({
  sport,
  taille = 22,
}: {
  sport: string
  taille?: number
}) {
  return (
    <Symbole
      nom={SYMBOLES[sport] ?? "sparkles"}
      taille={taille}
      couleur={couleurDuSport(sport)}
      className="icone-sport"
    />
  )
}

/// Un symbole SF du Mac, dans une boîte carrée de `taille` pixels.
///
/// Un masque plutôt qu'une image : le PNG est noir sur transparent, et c'est
/// la couleur de fond de l'élément — celle du sport, ou la couleur du texte
/// par défaut — qui passe au travers. Ajusté dans la boîte sans être déformé :
/// un vélo est plus large que haut, un marcheur l'inverse, et tous deux se
/// posent au centre du même carré, comme dans une colonne d'icônes du Mac.
export function Symbole({
  nom,
  taille = 22,
  couleur = "currentColor",
  className,
}: {
  nom: string
  taille?: number
  couleur?: string
  className?: string
}) {
  const url = `url("/sf/${nom}.png")`
  return (
    <span
      aria-hidden
      className={className ? `symbole ${className}` : "symbole"}
      style={{
        width: taille,
        height: taille,
        backgroundColor: couleur,
        WebkitMaskImage: url,
        maskImage: url,
      }}
    />
  )
}

