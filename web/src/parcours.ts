/// Reconnaître deux enregistrements d'un même parcours — porté de
/// `RouteSignature.swift`, dont des tests tiennent la règle.
///
/// Les deux traces sont rééchantillonnées au même nombre de points, répartis
/// le long de leur propre longueur ; la distance moyenne entre points
/// appariés fait la mesure. Comparer par position **le long du chemin** rend
/// le sens du parcours signifiant sans rien coder pour : une boucle faite à
/// l'envers apparie son kilomètre 2 avec le kilomètre 38 de l'autre et échoue,
/// tandis qu'un aller-retour — symétrique par nature — se reconnaît dans les
/// deux sens, ce qui est exactement ce que « même parcours » veut dire pour
/// lui.

import type { Coordonnee } from "./track"

/// Assez pour fixer la forme d'un parcours, assez peu pour comparer une sortie
/// à des centaines sans que ça se sente.
const ECHANTILLONS = 32

/// Le rayon terrestre moyen, celui de `TrackMetrics`.
const RAYON = 6_371_008.8

export function distanceEntre(a: Coordonnee, b: Coordonnee): number {
  const [lonA, latA] = a
  const [lonB, latB] = b
  const phi1 = (latA * Math.PI) / 180
  const phi2 = (latB * Math.PI) / 180
  const dPhi = ((latB - latA) * Math.PI) / 180
  const dLambda = ((lonB - lonA) * Math.PI) / 180
  const h =
    Math.sin(dPhi / 2) ** 2 +
    Math.cos(phi1) * Math.cos(phi2) * Math.sin(dLambda / 2) ** 2
  return 2 * RAYON * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h))
}

/// La dérive GPS entre deux enregistrements honnêtes d'une même route se
/// compte en dizaines de mètres ; deux rues parallèles, en centaine. Le
/// plancher couvre les sorties courtes, le pourcentage laisse respirer les
/// longues — un 100 km qui prend un rond-point différent reste le même
/// parcours — et le plafond empêche « respirer » de vouloir dire « une vallée
/// plus loin ».
export function tolerance(distance: number): number {
  return Math.min(Math.max(75, distance * 0.01), 250)
}

/// La trace ramenée à `ECHANTILLONS` points, répartis le long de sa longueur
/// cumulée. `null` quand il n'y a pas de trace dont parler.
export function signature(trace: Coordonnee[]): Coordonnee[] | null {
  if (trace.length < 2) return null
  const pas: number[] = []
  for (let i = 0; i < trace.length - 1; i++) pas.push(distanceEntre(trace[i], trace[i + 1]))
  const total = pas.reduce((somme, valeur) => somme + valeur, 0)
  if (total <= 0) return null

  const points: Coordonnee[] = [trace[0]]
  let parcourue = 0
  let segment = 0
  for (let index = 1; index < ECHANTILLONS; index++) {
    const cible = (total * index) / (ECHANTILLONS - 1)
    while (segment < pas.length - 1 && parcourue + pas[segment] < cible) {
      parcourue += pas[segment]
      segment += 1
    }
    const longueur = pas[segment]
    const fraction = longueur > 0 ? Math.min(1, (cible - parcourue) / longueur) : 1
    const [lonA, latA] = trace[segment]
    const [lonB, latB] = trace[segment + 1]
    points.push([lonA + (lonB - lonA) * fraction, latA + (latB - latA) * fraction])
  }
  return points
}

/// La distance moyenne entre points appariés, en mètres.
export function ecartMoyen(a: Coordonnee[], b: Coordonnee[]): number {
  if (a.length !== b.length || a.length === 0) return Infinity
  let somme = 0
  for (let i = 0; i < a.length; i++) somme += distanceEntre(a[i], b[i])
  return somme / a.length
}

/// Même parcours ? Des longueurs à 10 % près de la plus grande, des formes à
/// la tolérance près l'une de l'autre.
export function memeParcours(
  a: Coordonnee[],
  b: Coordonnee[],
  distanceA: number,
  distanceB: number,
): boolean {
  const plusLongue = Math.max(distanceA, distanceB)
  if (plusLongue <= 0 || Math.abs(distanceA - distanceB) > plusLongue * 0.1) return false
  return ecartMoyen(a, b) <= tolerance(plusLongue)
}
