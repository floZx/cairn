/// Les fonds de carte, et le relief.
///
/// Partagés entre la carte d'une sortie et celle d'ensemble : deux définitions
/// finiraient par diverger, et se retrouver sur un fond différent selon
/// l'écran serait déroutant.

export type Fond = "plan" | "carte" | "satellite"

type Definition = {
  nom: string
  couche: string
  format: string
  /// Ce que la licence de la source exige.
  attribution: string
  /// Les fonds sombres veulent une trace claire, et l'inverse : une ligne
  /// rouge sur une photo aérienne de forêt disparaît.
  trace: string
  /// Une carte de papier, par opposition à une photo.
  ///
  /// Ce qui est dessiné se renverse — c'est ainsi qu'on obtient une carte
  /// sombre là où la source n'en propose pas. Ce qui est photographié, non :
  /// une forêt en négatif ne ressemble plus à rien.
  papier: boolean
}

export const FONDS: Record<Fond, Definition> = {
  plan: {
    nom: "Plan",
    couche: "GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2",
    format: "image/png",
    attribution: "© IGN — Géoplateforme",
    trace: "#e5332a",
    papier: true,
  },
  carte: {
    nom: "Carte IGN",
    couche: "GEOGRAPHICALGRIDSYSTEMS.MAPS.BDUNI.J1",
    format: "image/png",
    attribution: "© IGN — Géoplateforme",
    trace: "#c1121f",
    papier: true,
  },
  satellite: {
    nom: "Satellite",
    couche: "ORTHOIMAGERY.ORTHOPHOTOS",
    format: "image/jpeg",
    attribution: "© IGN — Géoplateforme",
    // Le rouge se perd dans la végétation d'une photo aérienne ; le jaune
    // tient sur la forêt comme sur la roche.
    trace: "#ffd60a",
    papier: false,
  },
}

/// L'adresse d'une tuile précise, pour une carte posée en `<img>`.
///
/// Le même gabarit que `tuiles`, ses trois trous remplis. Deux formes plutôt
/// qu'une parce que les deux clients ne veulent pas la même chose : MapLibre
/// veut le gabarit et remplit lui-même, une balise `img` veut une adresse.
export function urlDeTuile(fond: Fond, zoom: number, x: number, y: number): string {
  return tuiles(fond)
    .replace("{z}", String(zoom))
    .replace("{x}", String(x))
    .replace("{y}", String(y))
}

function tuiles(fond: Fond): string {
  const d = FONDS[fond]
  return (
    "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile" +
    `&LAYER=${d.couche}&STYLE=normal&TILEMATRIXSET=PM` +
    `&FORMAT=${encodeURIComponent(d.format)}&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}`
  )
}

/// Les tuiles d'altitude, en encodage « terrarium ».
///
/// Chez Amazon et non chez l'IGN : la Géoplateforme sert bien un modèle
/// d'élévation, mais en BIL 32 bits, que MapLibre ne sait pas lire — il lui
/// faut une altitude encodée dans les canaux d'une image, ce que « terrarium »
/// fait et que ce jeu-ci fournit, en libre accès et sans restriction
/// d'origine. Vérifié : `Access-Control-Allow-Origin: *`.
const ALTITUDE = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"

const CLEF_FOND = "cairn.fond"
const CLEF_RELIEF = "cairn.relief"

/// Le fond retenu de la dernière fois.
///
/// Dans `localStorage` et non dans l'état de React : un choix de fond survit à
/// la fermeture de l'application, sans quoi il faudrait le refaire à chaque
/// ouverture — ce qui, pour un réglage qu'on pose une fois, est une corvée.
export function fondRetenu(): Fond {
  const v = localStorage.getItem(CLEF_FOND)
  return v === "carte" || v === "satellite" || v === "plan" ? v : "plan"
}

export function retenirFond(f: Fond) {
  localStorage.setItem(CLEF_FOND, f)
}

export function reliefRetenu(): boolean {
  return localStorage.getItem(CLEF_RELIEF) === "oui"
}

export function retenirRelief(actif: boolean) {
  localStorage.setItem(CLEF_RELIEF, actif ? "oui" : "non")
}

/// Les sources et couches d'un fond, à poser dans un style.
///
/// La source d'altitude est déclarée même quand le relief est éteint : une
/// source ajoutée après coup demande de reconstruire le style, et l'allumer
/// doit rester instantané.
/// L'application est-elle en thème sombre ?
function sombre(): boolean {
  return matchMedia("(prefers-color-scheme: dark)").matches
}

/// La couche du dessous, sous les tuiles.
///
/// Les PNG de l'IGN laissent voir au travers là où la carte est vide : sans
/// rien dessous, c'est le noir de la page qui apparaissait, et un plan à traits
/// fins se lisait comme une photo de nuit. Elle prend la couleur du papier une
/// fois renversé, pour que les trous se confondent avec lui.
export function coucheDuDessous(fond: Fond) {
  const papier = FONDS[fond].papier
  return {
    id: "papier",
    type: "background" as const,
    paint: { "background-color": papier && sombre() ? "#0f0f11" : "#ffffff" },
  }
}

/// La peinture des tuiles.
///
/// En thème sombre, une carte de papier est renversée : l'IGN n'en publie pas
/// de version nocturne, et une grande page blanche dans le noir éblouit. Le
/// renversement se fait ici, dans la couche du fond, et non par un filtre CSS
/// sur la toile — celui-là retournerait aussi les traces, dont les couleurs
/// sont justement choisies.
///
/// `brightness-min` à un et `brightness-max` à zéro : la rampe de MapLibre est
/// prise à l'envers, ce qui donne `1 − c` sur chaque canal. La rotation de
/// teinte remet ensuite les couleurs d'aplomb — sans elle, le bleu des
/// rivières vire à l'orange.
export function peintureDuFond(fond: Fond) {
  if (!FONDS[fond].papier || !sombre()) return {}
  return {
    "raster-brightness-min": 1,
    "raster-brightness-max": 0,
    "raster-hue-rotate": 180,
    // Le renversement crève les couleurs : sans cette retenue, les routes
    // ressortent en fluo là où elles étaient discrètes.
    "raster-saturation": -0.35,
  }
}

export function sourcesDuFond(fond: Fond) {
  return {
    fond: {
      type: "raster" as const,
      tiles: [tuiles(fond)],
      tileSize: 256,
      maxzoom: 19,
      attribution: FONDS[fond].attribution,
    },
    relief: {
      type: "raster-dem" as const,
      tiles: [ALTITUDE],
      tileSize: 256,
      // Au-delà, les tuiles d'altitude n'existent plus et MapLibre les
      // redemande en boucle ; il vaut mieux qu'il agrandisse les dernières.
      maxzoom: 13,
      encoding: "terrarium" as const,
    },
  }
}

/// Le style de la carte est-il monté ?
///
/// La présence d'une source le dit : elles naissent avec le style, et MapLibre
/// lève « Style is not done loading » sur tout ce qu'on tente avant lui.
///
/// `isStyleLoaded()` ne répond pas à cette question-là : il attend aussi les
/// tuiles, et celles du relief n'arrêtent jamais d'arriver — il reste faux
/// aussi longtemps qu'on regarde la carte.
export function styleMonte(instance: { getSource(id: string): unknown }): boolean {
  return instance.getSource("fond") !== undefined
}
