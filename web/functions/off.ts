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
/// souple il pèse sur le classement sans exclure : « skyr danone » remonte
/// alors des Danone français, contre un yaourt brésilien sans lui. Mesuré, les
/// quatre formes essayées l'une après l'autre.
const FILTRE_PAYS = 'countries_tags:"en:france"'

export const onRequestGet: PagesFunction = async ({ request }) => {
  const q = new URL(request.url).searchParams.get("q")?.trim()
  if (!q) return Response.json({ hits: [] })

  const amont = new URL("https://search.openfoodfacts.org/search")
  // Restreint à la France : sans ce filtre, « skyr danone » remonte d'abord un
  // yaourt brésilien. La syntaxe est celle de leur moteur, guillemets compris.
  amont.searchParams.set("q", `${q} ${FILTRE_PAYS}`)
  amont.searchParams.set("page_size", "25")

  const reponse = await fetch(amont, {
    headers: { "User-Agent": "Cairn/1.0 (application personnelle)" },
    // Une recherche identique revient souvent — on tape trois lettres, on
    // hésite, on efface. Le cache de Cloudflare épargne leurs serveurs.
    cf: { cacheTtl: 3600, cacheEverything: true },
  })
  if (!reponse.ok) {
    return Response.json(
      { erreur: `Open Food Facts a répondu ${reponse.status}` },
      { status: 502 },
    )
  }
  return new Response(reponse.body, {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
    },
  })
}
