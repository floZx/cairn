/// Les trois façons de regarder la même sélection d'activités.
///
/// Trois vues et non trois écrans : le filtre est le même, ce qu'il laisse
/// passer aussi, seule change la façon dont on le montre. La liste compacte
/// tient dix sorties par écran et sert à retrouver ; le fil en montre une à la
/// fois, avec sa trace et sa photo, et sert à revoir ; la carte les pose toutes
/// au même endroit et sert à situer.
export type Vue = "liste" | "fiches" | "carte"

/// Ce qui se retient d'une fois sur l'autre.
///
/// La carte n'en fait pas partie, et c'est délibéré : c'est un endroit où l'on
/// va, pas une préférence — rouvrir l'application sur une carte du monde plutôt
/// que sur ses dernières sorties serait une surprise à chaque lancement. Le
/// choix entre la liste et le fil, lui, est bien une préférence, comme l'est le
/// choix entre tableau et fiches sur le Mac.
export type Presentation = Exclude<Vue, "carte">

const CLEF = "cairn.presentation-activites"

export function presentationRetenue(): Presentation {
  return localStorage.getItem(CLEF) === "fiches" ? "fiches" : "liste"
}

export function retenirPresentation(p: Presentation) {
  localStorage.setItem(CLEF, p)
}
