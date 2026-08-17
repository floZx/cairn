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

/// Les dessins, à la ligne comme ceux de la barre d'onglets.
///
/// Approximations des symboles du système : `figure.run`, `figure.hiking` et
/// les autres n'existent pas hors des applications d'Apple, et un jeu d'icônes
/// tiers pèserait plus que tout le reste de l'application pour dix symboles.
function tracé(brut: string) {
  switch (brut) {
    case "ride":
    case "eBikeRide":
    case "mountainBikeRide":
    case "gravelRide":
      return (
        <>
          <circle cx="5.5" cy="17" r="3.5" />
          <circle cx="18.5" cy="17" r="3.5" />
          <path d="M5.5 17l4-8h5l4 8M9.5 9h5M12 9l2.5 8" />
        </>
      )
    case "run":
    case "trailRun":
      return (
        <>
          <circle cx="14.5" cy="4.5" r="2" />
          <path d="M13 8.5l-3.5 3 2.5 3 1 6M12 14.5l-4 1M13 8.5l4 2 1 3.5" />
        </>
      )
    case "walk":
      return (
        <>
          <circle cx="13" cy="4.5" r="2" />
          <path d="M13 8v6M13 14l-2.5 7M13 14l3 7M13 10l-3.5 2M13 10l3.5 2" />
        </>
      )
    case "hike":
      return (
        <>
          <circle cx="12" cy="4.5" r="2" />
          <path d="M12 8v5.5M12 13.5l-2.5 7.5M12 13.5l3 7.5M12 10l-3 2" />
          {/* Le bâton, seul trait qui distingue la randonnée de la marche. */}
          <path d="M18 5.5v15" />
        </>
      )
    case "swim":
      return (
        <>
          <circle cx="7" cy="8" r="2" />
          <path d="M9 10l4.5 2.5 4-3.5" />
          <path d="M2.5 18.5c1.6 0 1.6 1.5 3.2 1.5s1.6-1.5 3.2-1.5 1.6 1.5 3.2 1.5 1.6-1.5 3.2-1.5 1.6 1.5 3.2 1.5 1.6-1.5 3.2-1.5" />
        </>
      )
    case "nordicSki":
      return (
        <>
          <circle cx="13" cy="4" r="1.8" />
          <path d="M12 7.5l-2 5 3 2 .5 5M10 12.5l-3.5 1M12 7.5l4 2M16.5 4v13" />
          <path d="M3 20.5l17-4" />
        </>
      )
    case "alpineSki":
      return (
        <>
          <circle cx="14" cy="4" r="1.8" />
          <path d="M13 7.5l-3 4 3.5 2.5M13 7.5l4 1.5" />
          <path d="M3.5 17l16 3.5M6 20.5l14-4" />
        </>
      )
    case "rowing":
      return (
        <>
          <circle cx="9" cy="5" r="1.8" />
          <path d="M8 8.5l3 3 4-1.5M11 11.5l-1 4" />
          <path d="M3 19.5l18-6" />
        </>
      )
    case "workout":
      // Une barre et ses disques : le seul dessin de force qui se lise à
      // vingt pixels.
      return (
        <>
          <path d="M3 9v6M6 7v10M18 7v10M21 9v6M6 12h12" />
        </>
      )
    default:
      // Rien à dire d'un sport qu'on ne reconnaît pas : trois étincelles,
      // comme le `sparkles` du Mac.
      return (
        <>
          <path d="M12 4l1.4 3.6L17 9l-3.6 1.4L12 14l-1.4-3.6L7 9l3.6-1.4z" />
          <path d="M18 15l.7 1.8L20.5 17.5l-1.8.7L18 20l-.7-1.8L15.5 17.5l1.8-.7z" />
        </>
      )
  }
}

export function IconeSport({
  sport,
  taille = 22,
}: {
  sport: string
  taille?: number
}) {
  return (
    <svg
      width={taille}
      height={taille}
      viewBox="0 0 24 24"
      fill="none"
      stroke={couleurDuSport(sport)}
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      className="icone-sport"
    >
      {tracé(sport)}
    </svg>
  )
}
