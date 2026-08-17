/// L'arithmétique nutritionnelle, portée depuis `NutritionMath.swift`.
///
/// Portée et non re-dérivée, exactement pour la raison qui vaut déjà pour les
/// étiquettes du journal : deux règles qui divergent donneraient deux écrans
/// affichant des chiffres différents pour la même journée. Les commentaires
/// d'origine expliquent *pourquoi* chaque seuil vaut ce qu'il vaut — ils sont
/// là-bas, et c'est là-bas qu'il faut aller avant de toucher à un nombre ici.

export type Macros = {
  kcal: number
  proteines: number
  glucides: number
  lipides: number
}

export const ZERO: Macros = { kcal: 0, proteines: 0, glucides: 0, lipides: 0 }

export type Portion = {
  kcal100: number
  protein100: number
  carbs100: number
  fat100: number
  grams: number
}

export function macrosDe(portion: Portion): Macros {
  const facteur = portion.grams / 100
  return {
    kcal: portion.kcal100 * facteur,
    proteines: portion.protein100 * facteur,
    glucides: portion.carbs100 * facteur,
    lipides: portion.fat100 * facteur,
  }
}

export function somme(...m: Macros[]): Macros {
  return m.reduce(
    (a, b) => ({
      kcal: a.kcal + b.kcal,
      proteines: a.proteines + b.proteines,
      glucides: a.glucides + b.glucides,
      lipides: a.lipides + b.lipides,
    }),
    ZERO,
  )
}

export function multiplie(m: Macros, facteur: number): Macros {
  return {
    kcal: m.kcal * facteur,
    proteines: m.proteines * facteur,
    glucides: m.glucides * facteur,
    lipides: m.lipides * facteur,
  }
}

/// Chaque macro à l'unité, comme chacune est écrite.
///
/// Sommées depuis celles-ci et non depuis les décimales derrière elles : une
/// colonne de chiffres doit faire le total imprimé dessous. Elle ne le faisait
/// pas — sept lignes lues 24, 1, 5, 3, 19, 13, 0, soit soixante-cinq, sous un
/// titre disant 64.
export function arrondi(m: Macros): Macros {
  return {
    kcal: Math.round(m.kcal),
    proteines: Math.round(m.proteines),
    glucides: Math.round(m.glucides),
    lipides: Math.round(m.lipides),
  }
}

/// De combien un objectif peut être dépassé avant qu'on en dise quelque chose.
///
/// Un gramme au-dessus de 149 n'est pas un dépassement, c'est le même repas
/// pesé deux fois. Deux pour cent couvrent les grands objectifs, deux unités
/// les petits.
export function tolerance(objectif: number): number {
  return Math.max(objectif * 0.02, 2)
}

export type Depassement = "modere" | "franc" | null

/// Jugé sur les chiffres affichés, pas sur ce qu'il y a derrière : une couleur
/// qui contredit le nombre sur lequel elle est posée se lit comme un défaut, et
/// l'a été.
export function depassement(consomme: number, objectif: number): Depassement {
  if (objectif <= 0) return null
  const c = Math.round(consomme)
  const o = Math.round(objectif)
  const grace = tolerance(o)
  if (c <= o + grace) return null
  return c > o * 1.1 + grace ? "franc" : "modere"
}

/// Le pendant de `depassement`, et son contraire d'esprit : dépasser est ce
/// qu'on signale, celui-ci est ce dont on félicite. Un journal qui ne colore
/// que pour gronder est un journal qu'on cesse de lire.
export function dansLeMille(consomme: number, objectif: number): boolean {
  if (objectif <= 0) return false
  const c = Math.round(consomme)
  const o = Math.round(objectif)
  return c >= o * 0.9 && c <= o + tolerance(o)
}

/// Le reste de la journée, chaque macro plancher à zéro : une marge dépassée
/// se lit « plus rien », jamais comme une allocation négative.
export function reste(journee: Macros, consomme: Macros): Macros {
  return {
    kcal: Math.max(0, journee.kcal - consomme.kcal),
    proteines: Math.max(0, journee.proteines - consomme.proteines),
    glucides: Math.max(0, journee.glucides - consomme.glucides),
    lipides: Math.max(0, journee.lipides - consomme.lipides),
  }
}

export type EtatRepas = {
  pct: number
  commence: boolean
  consomme: Macros
}

/// Quels repas sont finis : un repas l'est dès qu'un plus tardif est entamé.
export function depasses(repas: EtatRepas[]): boolean[] {
  return repas.map((_, i) => repas.slice(i + 1).some((r) => r.commence))
}

/// Les objectifs par repas, qui s'adaptent à ce qui a réellement été mangé.
///
/// Les repas finis gardent leur part fixe du plan, pour qu'on voie comment ils
/// se sont comparés à lui. Le repas en cours prend sa part du budget restant
/// avec une formule inchangée — son objectif ne saute donc pas quand le premier
/// aliment y tombe. Les repas à venir se partagent ce qui reste vraiment, si
/// bien que manger exactement leur objectif fait atterrir pile sur celui du
/// jour, que les précédents aient dépassé ou non.
export function objectifsAdaptatifs(
  journee: Macros | null,
  repas: EtatRepas[],
): (Macros | null)[] {
  if (!journee) return repas.map(() => null)
  const finis = depasses(repas)

  // Ce qui pèse sur le budget sans posséder d'objectif : les repas finis et
  // les créneaux à 0 %. Ce que les repas en cours ou à venir ont déjà mangé
  // reste dans le budget — cela compte contre leur propre objectif.
  const autresConsomme = somme(
    ...repas.filter((_, i) => finis[i] || repas[i].pct <= 0).map((r) => r.consomme),
  )
  const budget = reste(journee, autresConsomme)

  const enJeu = repas.map((_, i) => i).filter((i) => !finis[i] && repas[i].pct > 0)
  const pctEnJeu = enJeu.reduce((s, i) => s + repas[i].pct, 0)

  // Le repas en cours est le dernier entamé encore en jeu — il ne peut y en
  // avoir qu'un, tout ce qui précède un repas entamé étant dépassé.
  const courant = [...enJeu].reverse().find((i) => repas[i].commence)

  let objectifCourant: Macros | null = null
  let consommeCourant = ZERO
  if (courant !== undefined && pctEnJeu > 0) {
    objectifCourant = multiplie(budget, repas[courant].pct / pctEnJeu)
    consommeCourant = repas[courant].consomme
  }

  const budgetFutur = reste(journee, somme(autresConsomme, consommeCourant))
  const pctFutur = enJeu
    .filter((i) => i !== courant && !repas[i].commence)
    .reduce((s, i) => s + repas[i].pct, 0)

  return repas.map((r, i) => {
    if (r.pct <= 0) return null
    if (finis[i]) return multiplie(journee, r.pct / 100)
    if (i === courant) return objectifCourant
    return pctFutur > 0 ? multiplie(budgetFutur, r.pct / pctFutur) : budgetFutur
  })
}
