import type { FocusEvent } from "react"

/// Sélectionne tout le contenu d'un champ quand il prend le focus, pour qu'on
/// tape la nouvelle valeur par-dessus l'ancienne.
///
/// Un tour plus tard et non sur-le-champ : sur iPhone, le toucher qui donne le
/// focus replace le curseur juste après, et défaisait une sélection faite dans
/// l'événement même. Un minuteur plutôt qu'une image : l'image n'arrive pas
/// dans une page en arrière-plan, et la sélection y manquait — mesuré.
export function selectionnerAuFocus(e: FocusEvent<HTMLInputElement>) {
  const champ = e.currentTarget
  setTimeout(() => champ.select(), 0)
}
