/// Open Food Facts, vu du navigateur — c'est-à-dire à travers `/off`, le
/// relais dont `functions/off.ts` explique la nécessité.

/// Un aliment prêt à être consigné, d'où qu'il vienne : un favori, une ligne
/// de recette, un repas passé, ou le catalogue. La même forme partout, pour
/// que la liste du sélecteur en mélange les sources sans les distinguer.
export type Aliment = {
  /// Unique dans la liste affichée, pas dans le monde : le code-barres quand
  /// il y en a un, le nom sinon — un aliment saisi à la main n'a pas de code.
  id: string
  nom: string
  marque: string
  kcal100: number
  protein100: number
  carbs100: number
  fat100: number
  /// Les fibres, **nulles quand la source ne les connaît pas**.
  ///
  /// Open Food Facts ne les renseigne que pour cinq produits sur six. Nul et
  /// non zéro : un aliment muet n'en contient pas zéro, il n'a rien dit, et
  /// confondre les deux ferait d'un total partiel un total faux.
  fiber100: number | null
  productCode: string | null
  /// Non nul pour un favori : c'est ce qui lui vaut son étoile et pré-remplit
  /// la quantité.
  grammesFavori: number | null
}

type HitOFF = {
  code?: string
  product_name?: string
  brands?: string[] | string
  nutriments?: Record<string, number | undefined>
}

/// Sans calories, un aliment n'a rien à faire dans un journal — et Open Food
/// Facts en renvoie beaucoup : des fiches créées sans que personne n'ait saisi
/// le tableau nutritionnel. Écartés plutôt qu'affichés à zéro, ce qui ferait
/// consigner un repas gratuit.
function utilisable(hit: HitOFF): boolean {
  return typeof hit.nutriments?.["energy-kcal_100g"] === "number"
}

export function alimentDepuisOFF(hit: HitOFF): Aliment | null {
  if (!utilisable(hit)) return null
  const n = hit.nutriments ?? {}
  const marques = Array.isArray(hit.brands) ? hit.brands : hit.brands ? [hit.brands] : []
  return {
    id: hit.code ?? hit.product_name ?? "",
    nom: hit.product_name?.trim() || "Sans nom",
    marque: marques.join(", "),
    kcal100: n["energy-kcal_100g"] ?? 0,
    protein100: n["proteins_100g"] ?? 0,
    carbs100: n["carbohydrates_100g"] ?? 0,
    fat100: n["fat_100g"] ?? 0,
    fiber100: n["fiber_100g"] ?? null,
    productCode: hit.code ?? null,
    grammesFavori: null,
  }
}

export async function chercherDansOFF(query: string, signal?: AbortSignal): Promise<Aliment[]> {
  const q = query.trim()
  if (!q) return []
  const reponse = await fetch(`/off?q=${encodeURIComponent(q)}`, { signal })
  if (!reponse.ok) throw new Error(`Open Food Facts : ${reponse.status}`)
  const corps = (await reponse.json()) as { hits?: HitOFF[] }
  return (corps.hits ?? []).flatMap((h) => {
    const a = alimentDepuisOFF(h)
    return a ? [a] : []
  })
}

/// En minuscules et sans accents, comme `FoodSearch.normalized` du Mac, pour
/// que « creme » trouve le favori « Crème ».
export function normalise(texte: string): string {
  return texte
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
}

/// L'identité d'un aliment pour le dédoublonnage : le couple (nom, code), et
/// non le code seul — un aliment saisi à la main n'en a pas.
function clef(a: Aliment): string {
  return `${a.nom}|${a.productCode ?? ""}`
}

/// La liste du sélecteur, portée de `FoodSearch.assemble`.
///
/// Sans recherche : les favoris, puis les aliments récemment consignés qui
/// n'en sont pas déjà. Avec une recherche : les favoris dont le nom
/// correspond, puis le catalogue — jamais deux fois le même produit.
export function assemble(
  query: string,
  favoris: Aliment[],
  recents: Aliment[],
  catalogue: Aliment[],
): Aliment[] {
  const q = query.trim()
  if (!q) {
    const vus = new Set(favoris.map(clef))
    return [...favoris, ...recents.filter((a) => !vus.has(clef(a)))]
  }
  const aiguille = normalise(q)
  const correspondants = favoris.filter((a) => normalise(a.nom).includes(aiguille))
  // Seuls les favoris **affichés** masquent leur équivalent du catalogue : un
  // favori absent de l'écran ne cache rien.
  const masques = new Set(correspondants.flatMap((a) => (a.productCode ? [a.productCode] : [])))
  const visibles = catalogue.filter((a) => !a.productCode || !masques.has(a.productCode))
  // Trié par rang, l'ordre du moteur départageant les égalités — `sort` est
  // stable en JavaScript depuis ES2019, l'indice n'est donc pas nécessaire ici
  // comme il l'est côté Swift.
  const classes = [...visibles].sort((a, b) => rang(a, aiguille) - rang(b, aiguille))
  return [...correspondants, ...classes]
}

/// À quel point ce produit répond à ce qu'on a demandé — zéro étant le mieux.
///
/// Porté de `FoodSearch.rank`. Trois critères, dans cet ordre.
///
/// **Le nom d'abord.** Chercher « banane » et recevoir « Barre énergie banane
/// coco » avant « Bananes » est un mauvais classement, marque ou pas.
/// L'égalité se juge au pluriel près et sur la recherche entière : « skyr
/// danone » ne promeut rien, tout reste dans l'ordre du moteur.
///
/// **La donnée ensuite**, et ce critère vient d'une mesure qui a renversé
/// l'intuition de départ. Le 18 août 2026, sur les cinquante premiers de trois
/// catégories : dix-sept bananes génériques sans marque, sept courgettes, une
/// tomate — et aucune ne porte de fibres. Ce sont des fiches nues. Mettre le
/// générique devant sans réserve, c'était garantir un tiret à chaque saisie.
///
/// **L'absence de marque enfin**, pour départager : entre deux bananes
/// également documentées, celle du primeur.
export function rang(aliment: Aliment, aiguille: string): number {
  const nom = normalise(aliment.nom).trim()
  const entier = nom === aiguille || nom === aiguille + "s" || aiguille === nom + "s"
  if (!entier) return 4
  const renseigne = aliment.fiber100 !== null
  const sansMarque = aliment.marque.trim() === ""
  return (renseigne ? 0 : 2) + (sansMarque ? 0 : 1)
}
