import maplibregl from "maplibre-gl"

/// Les tuiles des fonds de carte, gardées d'une ouverture à l'autre.
///
/// Par un protocole de MapLibre et non par le service worker. MapLibre
/// télécharge ses tuiles depuis son propre worker, que le service worker de la
/// PWA ne voit pas passer : la règle de cache posée dans `vite.config.ts`
/// n'avait retenu aucune tuile — zéro, mesuré. Un protocole, lui, est appelé
/// sur le fil de la page, qui a le Cache Storage sous la main.
///
/// Les adresses des fonds s'écrivent donc `tuile://data.geopf.fr/…` : ce
/// gestionnaire sert la tuile depuis le cache s'il l'a, et sinon la demande en
/// `https://`, la range, et la rend.
///
/// Ce ne sont pas des données du journal : elles ne changent qu'au fil des
/// mises à jour de l'IGN. D'où un mois de garde, et quatre mille tuiles au
/// plus — une quarantaine de mégaoctets, de quoi garder les coins où l'on sort
/// à tous les niveaux de zoom sans laisser le cache grossir sans fin.

const PROTOCOLE = "tuile"
const CACHE = "tuiles-carte"
const GARDE_MS = 30 * 24 * 3600 * 1000
const MAXIMUM = 4000

/// L'adresse d'une tuile, réécrite pour passer par le cache.
export function viaLeCache(url: string): string {
  return url.replace(/^https:\/\//, `${PROTOCOLE}://`)
}

let enregistre = false

export function enregistrerLeCacheDesTuiles() {
  if (enregistre || typeof caches === "undefined") return
  enregistre = true
  maplibregl.addProtocol(PROTOCOLE, async (params, abandon) => {
    const url = `https://${params.url.slice(PROTOCOLE.length + 3)}`
    const cache = await caches.open(CACHE)
    const gardee = await cache.match(url)
    if (gardee) {
      const date = Number(gardee.headers.get("x-cairn-rangee") ?? 0)
      if (Date.now() - date < GARDE_MS) return { data: await gardee.arrayBuffer() }
    }
    const reponse = await fetch(url, { signal: abandon.signal })
    if (!reponse.ok) throw new Error(`Tuile ${reponse.status}`)
    const octets = await reponse.arrayBuffer()
    // Rangée avec sa date, que `expiration` de Workbox tiendrait sinon à part.
    const entetes = new Headers(reponse.headers)
    entetes.set("x-cairn-rangee", String(Date.now()))
    void cache
      .put(url, new Response(octets.slice(0), { status: 200, headers: entetes }))
      .then(() => elaguer(cache))
    return { data: octets }
  })
}

/// Au-delà du maximum, les plus anciennes s'en vont — `keys()` les rend dans
/// l'ordre où elles sont entrées. Pas à chaque tuile : une fois sur cinquante,
/// le compte suffit à tenir la borne à quelques dizaines près.
async function elaguer(cache: Cache) {
  if (Math.random() > 0.02) return
  const cles = await cache.keys()
  for (const cle of cles.slice(0, Math.max(0, cles.length - MAXIMUM))) {
    await cache.delete(cle)
  }
}
