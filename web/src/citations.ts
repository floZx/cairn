/// Les personnes citées, portées de `PersonHandle`, `PersonScanner` et
/// `PeopleIndex` côté Swift.
///
/// Porté à la lettre, et pas seulement dans l'esprit : les deux écrans
/// affichent la même liste, et quelqu'un qui apparaîtrait ici et pas là ferait
/// douter des deux. Toute retouche se fait là-bas, où des tests la tiennent.

/// Les caractères qu'un pseudo accepte. Ni `.` ni `/` : le point clôt les
/// phrases, et une personne n'a pas de hiérarchie contrairement à un tag.
function permis(c: string): boolean {
  return /[\p{L}\p{N}_-]/u.test(c)
}

/// Ce qui peut précéder un `@` sans le disqualifier.
function ouvrante(c: string): boolean {
  return /\s/.test(c) || "([{«\"'-–—*>".includes(c)
}

/// Le pseudo replié — sans casse ni accents. C'est lui qui identifie :
/// « @Hélène » et « @helene » sont la même personne.
export function replie(texte: string): string {
  return texte
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
}

export type Personne = { nom: string; cle: string }

export function personne(nom: string): Personne | null {
  const propre = nom.replace(/^[-_]+|[-_]+$/g, "")
  if (!propre) return null
  if (![...propre].every(permis)) return null
  // La règle des tags, pour la même raison : `@2026` reste une année.
  if (![...propre].some((c) => !/\p{N}/u.test(c))) return null
  return { nom: propre, cle: replie(propre) }
}

/// Les personnes citées dans un texte.
///
/// Le `@` doit **ouvrir le mot** — c'est cette seule règle qui écarte les
/// adresses de courriel, où il suit une lettre. Sans elle, chaque adresse
/// écrite dans une note aurait créé quelqu'un nommé « gmail ».
export function citations(texte: string): Personne[] {
  const trouves = new Map<string, Personne>()
  for (let i = 0; i < texte.length; i++) {
    if (texte[i] !== "@") continue
    if (i > 0 && !ouvrante(texte[i - 1])) continue
    let fin = i + 1
    while (fin < texte.length && permis(texte[fin])) fin++
    const trouve = personne(texte.slice(i + 1, fin))
    if (trouve && !trouves.has(trouve.cle)) trouves.set(trouve.cle, trouve)
  }
  return [...trouves.values()]
}

export type Source = { libelle: string; activite?: string }

export type Citation = {
  dateKey: string
  source: Source
  texte: string
}

export type Ligne = {
  personne: Personne
  compte: number
  derniere: string | null
  aUneNote: boolean
}

/// Les citations de chacun, les plus récentes d'abord.
///
/// Une personne citée deux fois dans le même texte n'y figure qu'une : on veut
/// la liste des notes qui parlent d'elle, pas celle des occurrences.
export function index(
  textes: { dateKey: string; source: Source; contenu: string }[],
): Map<string, { personne: Personne; citations: Citation[] }> {
  const table = new Map<string, { personne: Personne; citations: Citation[] }>()
  for (const texte of textes) {
    const propre = texte.contenu.trim()
    if (!propre) continue
    for (const qui of citations(propre)) {
      const entree = table.get(qui.cle) ?? { personne: qui, citations: [] }
      entree.citations.push({
        dateKey: texte.dateKey,
        source: texte.source,
        texte: propre,
      })
      table.set(qui.cle, entree)
    }
  }
  for (const entree of table.values()) {
    entree.citations.sort((a, b) =>
      a.dateKey === b.dateKey
        ? a.source.libelle.localeCompare(b.source.libelle)
        : b.dateKey.localeCompare(a.dateKey),
    )
  }
  return table
}

/// La liste, la plus récemment citée d'abord.
///
/// Les personnes dont la fiche existe mais qu'aucune note ne cite plus y
/// figurent quand même, en bas : perdre ce qu'on a écrit sur quelqu'un parce
/// qu'une note a été retouchée serait une trappe.
export function lignes(
  table: Map<string, { personne: Personne; citations: Citation[] }>,
  fiches: { key: string; name: string }[],
): Ligne[] {
  const sorties: Ligne[] = [...table.values()].map((entree) => ({
    personne: entree.personne,
    compte: entree.citations.length,
    derniere: entree.citations[0]?.dateKey ?? null,
    aUneNote: fiches.some((f) => f.key === entree.personne.cle),
  }))
  for (const fiche of fiches) {
    if (table.has(fiche.key)) continue
    const qui = personne(fiche.name)
    if (!qui) continue
    sorties.push({ personne: qui, compte: 0, derniere: null, aUneNote: true })
  }
  return sorties.sort((a, b) => {
    if (a.derniere && b.derniere && a.derniere !== b.derniere) {
      return b.derniere.localeCompare(a.derniere)
    }
    if (a.derniere && !b.derniere) return -1
    if (!a.derniere && b.derniere) return 1
    return a.personne.nom.localeCompare(b.personne.nom, "fr")
  })
}

/// Ce qui est en train d'être tapé après un `@`, au curseur.
///
/// À la différence du Mac, la position est **connue** : un `<textarea>` la
/// donne, là où `TextEditor` la garde pour lui. Le portage n'a donc pas besoin
/// de la déduire de ce qui vient d'être inséré, et la complétion marche aussi
/// au milieu d'une phrase déjà écrite.
export function enCoursDe(
  texte: string,
  curseur: number,
): { fragment: string; debut: number } | null {
  let i = curseur
  let fragment = ""
  while (i > 0) {
    const c = texte[i - 1]
    if (c === "@") {
      const avant = i > 1 ? texte[i - 2] : " "
      if (!ouvrante(avant)) return null
      return { fragment, debut: i - 1 }
    }
    if (!permis(c)) return null
    fragment = c + fragment
    i--
    // Un pseudo ne fait pas trente caractères : au-delà, c'est qu'on remonte
    // dans du texte ordinaire.
    if (fragment.length > 30) return null
  }
  return null
}

/// Les personnes proposées pour un fragment, les plus courtes d'abord.
///
/// Par le début du pseudo et non « contient » : on tape le début d'un prénom,
/// et une liste qui remonte « Marie » pour « ari » ferait douter de ce qu'elle
/// cherche.
export function propositions(
  fragment: string,
  connus: Personne[],
  limite = 6,
): Personne[] {
  const cherche = replie(fragment)
  return connus
    .filter((p) => cherche === "" || p.cle.startsWith(cherche))
    .sort((a, b) =>
      a.nom.length !== b.nom.length
        ? a.nom.length - b.nom.length
        : a.nom.localeCompare(b.nom, "fr"),
    )
    .slice(0, limite)
}
