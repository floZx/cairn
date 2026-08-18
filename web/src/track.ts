/// Décodage de la trace simplifiée, telle que Postgres la rend.
///
/// La colonne est un `bytea`, et PostgREST le sérialise en hexadécimal préfixé
/// — `\x48656c6c6f`. Le Mac l'écrit dans ce même format ; c'est ce qui rend
/// l'aller-retour symétrique, et c'est pour ça qu'il n'envoie pas du base64
/// (que `byteain` accepterait en silence comme du format « escape », stockant
/// les caractères du base64 au lieu des octets qu'il représente).
///
/// Le contenu est ce que `TrackBlob` empaquette côté Swift : des `Float64`
/// bruts, sans en-tête, en petit-boutiste, par paires latitude/longitude.
export type Coordonnee = [longitude: number, latitude: number]

function octetsDepuisHex(hex: string): Uint8Array {
  const corps = hex.startsWith("\\x") ? hex.slice(2) : hex
  const octets = new Uint8Array(corps.length / 2)
  for (let i = 0; i < octets.length; i++) {
    octets[i] = parseInt(corps.substr(i * 2, 2), 16)
  }
  return octets
}

/// Rendue en `[longitude, latitude]`, l'ordre de GeoJSON et de MapLibre —
/// l'inverse de celui où `TrackBlob` les range. Faire la bascule ici, une
/// fois, plutôt qu'à chaque endroit qui dessine.
export function traceDepuisBytea(hex: string | null): Coordonnee[] {
  if (!hex) return []
  const octets = octetsDepuisHex(hex)
  // `DataView` plutôt qu'un `Float64Array` direct : le tampon peut commencer à
  // n'importe quel décalage, et `Float64Array` exigerait un alignement sur huit
  // octets que rien ne garantit.
  const vue = new DataView(octets.buffer, octets.byteOffset, octets.byteLength)
  const points: Coordonnee[] = []
  for (let i = 0; i + 16 <= vue.byteLength; i += 16) {
    const latitude = vue.getFloat64(i, true)
    const longitude = vue.getFloat64(i + 8, true)
    points.push([longitude, latitude])
  }
  return points
}

/// Une trace ramenée dans un cadre, ses proportions gardées.
///
/// Le portage de `TrackThumbnail.points` du Mac, correction de longitude
/// comprise : un degré de longitude ne vaut qu'environ 70 % d'un degré de
/// latitude en France, et projeter les deux à la même échelle étire toutes les
/// traces en largeur — une boucle ronde devient un ovale.
///
/// Le rapport est ensuite conservé et le résultat centré, parce que ce qu'on
/// vient lire dans une miniature est une **forme** : une trace écrasée pour
/// remplir sa boîte ne dit plus rien de la sortie d'où elle vient.
export function projeter(
  trace: Coordonnee[],
  largeur: number,
  hauteur: number,
  marge = 0,
): [x: number, y: number][] {
  const cadreL = largeur - 2 * marge
  const cadreH = hauteur - 2 * marge
  if (trace.length < 2 || cadreL <= 0 || cadreH <= 0) return []

  const longitudes = trace.map(([lon]) => lon)
  const latitudes = trace.map(([, lat]) => lat)
  const minLon = Math.min(...longitudes)
  const maxLon = Math.max(...longitudes)
  const minLat = Math.min(...latitudes)
  const maxLat = Math.max(...latitudes)

  const facteur = Math.cos((((minLat + maxLat) / 2) * Math.PI) / 180)
  // Un plancher, jamais zéro : une sortie sur place — un tapis, un bassin mal
  // capté — a une étendue nulle, et la division qui suit rendrait des `NaN`
  // qui vident le tracé sans rien dire.
  const etendueX = Math.max((maxLon - minLon) * facteur, Number.MIN_VALUE)
  const etendueY = Math.max(maxLat - minLat, Number.MIN_VALUE)
  // Le plus petit des deux rapports est celui qui tient : prendre l'autre
  // rognerait la trace.
  const unite = Math.min(cadreL / etendueX, cadreH / etendueY)

  const decalageX = marge + (cadreL - etendueX * unite) / 2
  const decalageY = marge + (cadreH - etendueY * unite) / 2

  return trace.map(([lon, lat]) => [
    decalageX + (lon - minLon) * facteur * unite,
    // La latitude croît vers le nord, l'ordonnée vers le bas : sans cette
    // soustraction, la trace sort à l'envers.
    decalageY + (maxLat - lat) * unite,
  ])
}
