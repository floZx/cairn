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
