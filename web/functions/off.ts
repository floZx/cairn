/// Le relais vers Open Food Facts.
///
/// Il existe parce que leurs serveurs ne laissent pas le choix, pas par goût
/// de l'indirection : `search.openfoodfacts.org` et `cgi/search.pl` rendent
/// bien du JSON, mais sans en-tête `Access-Control-Allow-Origin` — un
/// navigateur refuse donc la réponse. Seul `/api/v2/product/<code-barres>` est
/// ouvert au navigateur, et il ne cherche pas par texte. Mesuré le 17 août
/// 2026, en curl et depuis la page.
///
/// Une fonction Cloudflare Pages, donc servie depuis le même domaine que
/// l'application : la requête part bien vers chez eux, avec un saut de plus.
/// Elle porte aussi le `User-Agent` que leur documentation réclame, ce qu'une
/// page ne peut pas faire — les navigateurs interdisent d'y toucher.

/// Restreint aux produits vendus en France.
///
/// Posé comme un terme parmi les autres, **sans `AND`**, et c'est la seule
/// forme qui marche : leur moteur durcit les termes libres dès qu'on écrit un
/// opérateur booléen, si bien que « skyr danone AND countries_tags:… » ne rend
/// rien du tout là où « skyr danone » seul rend sept mille produits. En terme
/// souple il pèse sur le classement sans exclure. Mesuré, les quatre formes
/// essayées l'une après l'autre.
const FILTRE_PAYS = 'countries_tags:"en:france"'

/// La langue de recherche, et le réglage qui change tout.
///
/// Leur moteur cherche dans des sous-champs par langue, et **retombe sur
/// l'anglais** quand on ne dit rien. On cherchait donc « courgette » dans les
/// noms anglais. Mesuré le 18 août 2026 sur « banane » : 93 résultats sans ce
/// paramètre, 4 367 avec. Quarante-sept fois plus, pour un mot de trois
/// lettres dans l'URL — c'est l'essentiel de « c'est galère de trouver des
/// produits basiques ».
const LANGUES = "fr,en"

const RACINE = "https://search.openfoodfacts.org"
const ENTETES = { "User-Agent": "Cairn/1.0 (application personnelle)" }
/// Une recherche identique revient souvent — on tape trois lettres, on hésite,
/// on efface. Le cache de Cloudflare épargne leurs serveurs.
const CACHE = { cacheTtl: 3600, cacheEverything: true } as const

/// Sans accents ni majuscules, comme le fait la page.
function normalise(texte: string): string {
  return texte
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .trim()
}

/// La catégorie qui *est* ce qu'on a demandé, s'il y en a une.
///
/// Une courgette n'est pas une marque, c'est une catégorie — et c'est là que
/// leur taxonomie est excellente là où leur recherche plein texte est
/// médiocre : `categories_tags:"en:zucchini"` rend des courgettes sans marque,
/// quand « courgette » en texte libre rend d'abord des poêlées surgelées.
///
/// L'égalité est exigée, au pluriel près : « banane » vaut « Bananes », mais
/// « banane » ne doit pas attraper « Bananes gélifiées », que l'autocomplétion
/// propose aussi. Sans cette exigence, chercher un bonbon remonterait des
/// fruits frais.
async function categorieExacte(q: string): Promise<string | null> {
  const url = new URL(`${RACINE}/autocomplete`)
  url.searchParams.set("q", q)
  url.searchParams.set("taxonomy_names", "category")
  url.searchParams.set("lang", "fr")
  url.searchParams.set("size", "5")
  const reponse = await fetch(url, { headers: ENTETES, cf: CACHE })
  if (!reponse.ok) return null
  const corps = (await reponse.json()) as {
    options?: { text?: string; id?: string }[]
  }
  const cible = normalise(q)
  for (const option of corps.options ?? []) {
    const texte = normalise(option.text ?? "")
    if (!option.id) continue
    if (texte === cible || texte === `${cible}s` || cible === `${texte}s`) {
      return option.id
    }
  }
  return null
}

async function chercher(q: string, taille: number): Promise<unknown[]> {
  const url = new URL(`${RACINE}/search`)
  url.searchParams.set("q", q)
  url.searchParams.set("page_size", String(taille))
  url.searchParams.set("langs", LANGUES)
  const reponse = await fetch(url, { headers: ENTETES, cf: CACHE })
  if (!reponse.ok) throw new Error(String(reponse.status))
  const corps = (await reponse.json()) as { hits?: unknown[] }
  return corps.hits ?? []
}

export const onRequestGet: PagesFunction = async ({ request }) => {
  const q = new URL(request.url).searchParams.get("q")?.trim()
  if (!q) return Response.json({ hits: [] })

  try {
    // Les deux appels partent ensemble : le second ne dépend pas du premier,
    // et les enchaîner ajouterait un aller-retour à chaque frappe.
    const [categorie, libres] = await Promise.all([
      categorieExacte(q).catch(() => null),
      chercher(`${q} ${FILTRE_PAYS}`, 25),
    ])
    // La catégorie devant, le texte libre derrière, sans doublon. C'est
    // l'ordre qu'on veut : les vraies courgettes d'abord, les préparations
    // qui les mentionnent ensuite.
    const parCategorie = categorie
      ? await chercher(`categories_tags:"${categorie}" ${FILTRE_PAYS}`, 15).catch(
          () => [],
        )
      : []
    const vus = new Set<string>()
    const hits: unknown[] = []
    for (const hit of [...parCategorie, ...libres]) {
      const code = (hit as { code?: string }).code
      if (code && vus.has(code)) continue
      if (code) vus.add(code)
      hits.push(hit)
    }
    return Response.json(
      { hits },
      { headers: { "Cache-Control": "public, max-age=3600" } },
    )
  } catch (erreur) {
    return Response.json(
      { erreur: `Open Food Facts a répondu ${(erreur as Error).message}` },
      { status: 502 },
    )
  }
}
