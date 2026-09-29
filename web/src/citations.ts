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

/// D'où vient une citation.
///
/// La nature en plus du libellé, et pas par goût du détail : c'est elle qui
/// décide où l'on va en cliquant. Sans elle, la carte d'une note de repas
/// n'avait aucun moyen de mener au repas — seule celle d'une sortie savait où
/// aller, et la même carte se comportait de deux façons.
export type Source = {
  sorte: "journal" | "sortie" | "repas" | "pesee"
  libelle: string
  activite?: string
}

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

/// Qui est qui : chaque nom cité, par sa clé, vers la personne qu'il désigne.
/// Porté de `PeopleIndex.Annuaire` : les alias d'une fiche mènent à son nom,
/// son nom à lui-même ; un alias qui est le nom d'une autre fiche est ignoré,
/// et l'alias d'un alias ne mène nulle part.
export type Annuaire = {
  parCle: Map<string, Personne>
  /// Les alias retenus de chaque fiche, par la clé de son nom, tels qu'écrits.
  alias: Map<string, Personne[]>
}

export const ANNUAIRE_VIDE: Annuaire = { parCle: new Map(), alias: new Map() }

export function annuaire(fiches: { name: string; aliases?: string[] | null }[]): Annuaire {
  const parCle = new Map<string, Personne>()
  const alias = new Map<string, Personne[]>()
  const principaux = fiches.map((f) => personne(f.name)).filter((p): p is Personne => !!p)
  const nomsPropres = new Set(principaux.map((p) => p.cle))
  for (const p of principaux) parCle.set(p.cle, p)
  for (const fiche of fiches) {
    const principal = personne(fiche.name)
    if (!principal) continue
    for (const nom of fiche.aliases ?? []) {
      const qui = personne(nom)
      if (!qui || nomsPropres.has(qui.cle) || parCle.has(qui.cle)) continue
      parCle.set(qui.cle, principal)
      alias.set(principal.cle, [...(alias.get(principal.cle) ?? []), qui])
    }
  }
  return { parCle, alias }
}

/// La personne qu'un nom cité désigne — lui-même quand il n'est l'alias de
/// personne.
export function resoudre(a: Annuaire, qui: Personne): Personne {
  return a.parCle.get(qui.cle) ?? qui
}

/// Les citations de chacun, les plus récentes d'abord.
///
/// Une personne citée deux fois dans le même texte n'y figure qu'une : on veut
/// la liste des notes qui parlent d'elle, pas celle des occurrences. Sous un
/// alias comme sous son nom, c'est la même personne.
export function index(
  textes: { dateKey: string; source: Source; contenu: string }[],
  a: Annuaire = ANNUAIRE_VIDE,
): Map<string, { personne: Personne; citations: Citation[] }> {
  const table = new Map<string, { personne: Personne; citations: Citation[] }>()
  for (const texte of textes) {
    const propre = texte.contenu.trim()
    if (!propre) continue
    const citees = new Map(citations(propre).map((p) => resoudre(a, p)).map((p) => [p.cle, p]))
    for (const qui of citees.values()) {
      const entree = table.get(qui.cle) ?? { personne: qui, citations: [] }
      entree.citations.push({
        dateKey: texte.dateKey,
        source: texte.source,
        texte: extrait(propre, qui.cle, a),
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

/// Ce qu'on montre d'un texte sur la fiche de quelqu'un : les passages où elle
/// est nommée, et rien d'autre. Porté de `PeopleIndex.extrait(de:citant:)`,
/// qui dit pourquoi.
///
/// Plusieurs passages citants sont recollés, séparés par une ligne vide ; le
/// texte entier quand le découpage ne trouve rien.
export function extrait(texte: string, cle: string, a: Annuaire = ANNUAIRE_VIDE): string {
  const citants = unites(texte).filter((u) =>
    citations(u).some((p) => resoudre(a, p).cle === cle),
  )
  return citants.length === 0 ? texte : citants.join("\n\n")
}

/// Les unités de lecture d'un texte : les blocs séparés par une ligne vide, et
/// chaque item de liste pour son compte. Porté de `PeopleIndex.unites(de:)`.
export function unites(texte: string): string[] {
  const sorties: string[] = []
  let courante: string[] = []
  const clore = () => {
    if (courante.length > 0) sorties.push(courante.join("\n"))
    courante = []
  }
  // Les mêmes fins de ligne que `CharacterSet.newlines`.
  for (const ligne of texte.split(/[\n\r\u000B\u000C\u0085\u2028\u2029]/)) {
    if (ligne.replace(/[ \t]/g, "") === "") {
      clore()
      continue
    }
    if (courante.length > 0 && ouvreUneUnite(ligne)) clore()
    courante.push(ligne)
  }
  clore()
  return sorties
}

/// Ce qui ouvre une unité au milieu d'un bloc : un item de liste — `-`, `*`,
/// `+`, `1.`, `1)` — ou un titre. L'espace après la puce est exigé.
function ouvreUneUnite(ligne: string): boolean {
  const nu = ligne.replace(/^[ \t]+/, "")
  if (nu.startsWith("#")) return true
  if (/^[-*+] /.test(nu)) return true
  return /^\p{N}+[.)] /u.test(nu)
}

/// Les ordres que la liste des gens propose. Porté de `PeopleIndex.Tri`.
export type Tri = "recentes" | "alphabetique" | "nombre"

export const TRIS: { tri: Tri; libelle: string }[] = [
  { tri: "recentes", libelle: "Récentes" },
  { tri: "alphabetique", libelle: "Alphabétique" },
  { tri: "nombre", libelle: "Nombre de notes" },
]

/// La liste remise dans un autre ordre ; à égalité de notes, l'alphabet
/// départage. Porté de `PeopleIndex.trier(_:par:)`.
export function trier(liste: Ligne[], tri: Tri): Ligne[] {
  const alpha = (a: Ligne, b: Ligne) => a.personne.nom.localeCompare(b.personne.nom, "fr")
  if (tri === "alphabetique") return [...liste].sort(alpha)
  if (tri === "nombre") return [...liste].sort((a, b) => b.compte - a.compte || alpha(a, b))
  return liste
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
