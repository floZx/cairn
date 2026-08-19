/// Les étiquettes d'une note, reconnues exactement comme le Mac les reconnaît.
///
/// Un portage de `JournalTag` et `JournalTagScanner`, pas une réinvention : la
/// colonne `tags_raw` est écrite des deux côtés, et deux règles qui divergent
/// donneraient une note dont les étiquettes changent selon l'appareil qui l'a
/// enregistrée en dernier.

/// Les caractères qu'Obsidian accepte dans une étiquette. Tout le reste la
/// termine.
///
/// `\p{M}` — les accents combinants — figure ici alors que le Swift ne le
/// mentionne pas, et c'est pour dire la même chose : là-bas la vérification
/// porte sur des `Character`, c'est-à-dire des groupes de graphèmes, où `é`
/// écrit `e` + accent combinant compte pour une lettre. JavaScript parcourt
/// des points de code, et sans cette classe `#café` en forme décomposée
/// s'arrêterait à `caf`.
const autorise = /[\p{L}\p{N}\p{M}_\-/]/u

/// Les mêmes caractères, en classe réutilisable.
///
/// Exportée pour le rendu Markdown, qui doit reconnaître exactement les mêmes
/// étiquettes que le scanner — une seconde règle écrite là-bas finirait par
/// afficher comme étiquette ce qui n'en est pas une, ou l'inverse.
export const CARACTERES_ETIQUETTE = "\\p{L}\\p{N}\\p{M}_\\-/"

function nettoie(nom: string): string | null {
  // Une barre finale est une étiquette qu'on est en train de taper, pas un
  // niveau : `#projet/` veut dire `#projet`.
  const net = nom.replace(/^\/+|\/+$/g, "")
  if (!net) return null
  const points = [...net]
  if (!points.every((c) => autorise.test(c))) return null
  // La règle d'Obsidian : une étiquette doit porter au moins un caractère qui
  // ne soit pas un chiffre, pour que `#2026` reste une année.
  if (!points.some((c) => !/\p{N}/u.test(c) && c !== "/")) return null
  return net
}

/// Le nom d'une étiquette, ou nul si ce n'en est pas une.
///
/// La porte d'entrée de `nettoie` pour le reste de l'application : le rendu
/// Markdown s'en sert pour savoir si un `#quelquechose` est bien une étiquette
/// avant d'en retirer le croisillon.
export function nomDEtiquette(brut: string): string | null {
  return nettoie(brut)
}

/// `projet/cairn/journal` appartient aussi à `projet/cairn` et à `projet`.
function ancetres(nom: string): string[] {
  const parts = nom.split("/").filter(Boolean)
  if (parts.length <= 1) return []
  return parts.slice(0, -1).map((_, i) => parts.slice(0, i + 1).join("/"))
}

/// `#etiquette` dans le corps.
///
/// Le `#` doit ouvrir la suite — début du texte, ou après une espace — ce qui
/// tient `code#4` à l'écart. Un `#` suivi d'une espace est un titre Markdown
/// et ne donne rien, le nom étant vide.
function enLigne(texte: string): string[] {
  const trouvees: string[] = []
  const points = [...texte]
  for (let i = 0; i < points.length; i++) {
    if (points[i] !== "#") continue
    if (i > 0 && !/\s/u.test(points[i - 1])) continue
    let fin = i + 1
    while (fin < points.length && autorise.test(points[fin])) fin++
    const nom = nettoie(points.slice(i + 1, fin).join(""))
    if (nom) trouvees.push(nom)
  }
  return trouvees
}

/// Une clé `tags:` dans un avant-propos YAML, dans l'une des deux formes
/// qu'Obsidian écrit. Volontairement pas un analyseur YAML : l'avant-propos
/// d'une note fait trois lignes tapées à la main, et se tromper coûte une
/// étiquette manquante, pas un fichier abîmé.
function avantPropos(texte: string): string[] {
  const lignes = texte.split(/\r?\n/)
  // Le bloc ne compte qu'en toute première ligne : un `---` au milieu d'une
  // note est un filet horizontal.
  if (lignes.shift()?.trim() !== "---") return []
  const fermeture = lignes.findIndex((l) => ["---", "..."].includes(l.trim()))
  if (fermeture < 0) return []

  const bloc = lignes.slice(0, fermeture)
  const cle = bloc.findIndex((l) => l.trim().startsWith("tags:"))
  if (cle < 0) return []

  let noms: string[] = []
  const reste = bloc[cle].trim().slice("tags:".length).replace(/^[\s[\]]+|[\s[\]]+$/g, "")
  if (reste) {
    noms = reste.split(",")
  } else {
    for (const ligne of bloc.slice(cle + 1)) {
      const net = ligne.trim()
      if (!net.startsWith("- ")) break
      noms.push(net.slice(2))
    }
  }
  return noms.flatMap((n) => {
    const nom = nettoie(n.replace(/^[\s"'#]+|[\s"'#]+$/g, ""))
    return nom ? [nom] : []
  })
}

/// Toutes les étiquettes d'un texte, chacune accompagnée de ses ancêtres, pour
/// que filtrer sur un parent soit une simple appartenance.
export function etiquettesDe(texte: string): string[] {
  const toutes = new Set<string>()
  for (const nom of [...enLigne(texte), ...avantPropos(texte)]) {
    toutes.add(nom)
    for (const parent of ancetres(nom)) toutes.add(parent)
  }
  return [...toutes]
}
