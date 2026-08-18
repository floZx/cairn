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
}

export const FONDS: Record<Fond, Definition> = {
  plan: {
    nom: "Plan",
    couche: "GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2",
    format: "image/png",
    attribution: "© IGN — Géoplateforme",
    trace: "#e5332a",
  },
  carte: {
    nom: "Carte IGN",
    couche: "GEOGRAPHICALGRIDSYSTEMS.MAPS.BDUNI.J1",
    format: "image/png",
    attribution: "© IGN — Géoplateforme",
    trace: "#c1121f",
  },
  satellite: {
    nom: "Satellite",
    couche: "ORTHOIMAGERY.ORTHOPHOTOS",
    format: "image/jpeg",
    attribution: "© IGN — Géoplateforme",
    // Le rouge se perd dans la végétation d'une photo aérienne ; le jaune
    // tient sur la forêt comme sur la roche.
    trace: "#ffd60a",
  },
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
/// La couche du dessous, sous les tuiles.
///
/// Blanche, et non transparente : les PNG de l'IGN laissent voir au travers là
/// où la carte est vide, et sans rien dessous c'est le noir de la page qui
/// apparaissait — un plan blanc à traits fins se lisait alors comme une photo
/// de nuit. La photo aérienne, elle, est opaque et ne la voit jamais.
export const COUCHE_DU_DESSOUS = {
  id: "papier",
  type: "background" as const,
  paint: { "background-color": "#ffffff" },
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
