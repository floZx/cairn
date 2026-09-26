import type { FocusEvent } from "react"

/// Sélectionne tout le contenu d'un champ quand il prend le focus, pour qu'on
/// tape la nouvelle valeur par-dessus l'ancienne.
///
/// Un tour plus tard et non sur-le-champ : sur iPhone, le toucher qui donne le
/// focus replace le curseur juste après, et défaisait une sélection faite dans
/// l'événement même. Un minuteur plutôt qu'une image : l'image n'arrive pas
/// dans une page en arrière-plan, et la sélection y manquait — mesuré.
///
/// Reposée ensuite chaque fois que la fenêtre visuelle bouge, pendant un
/// instant. Clavier levé, un champ qui prend le focus fait défiler la page
/// pour rester visible — la feuille d'ajout d'un aliment rétrécit d'un coup en
/// passant de la liste à la quantité —, et iOS 27 laissait la sélection et ses
/// poignées dessinées là où le champ était avant ce défilement, à cheval sur le
/// titre : signalé, capture à l'appui. Reposer la sélection la redessine.
/// Seulement tant que rien n'a été tapé : on ne resélectionne pas ce qu'on
/// est en train d'écrire.
export function selectionnerAuFocus(e: FocusEvent<HTMLInputElement>) {
  const champ = e.currentTarget
  const valeur = champ.value
  const reposer = () => {
    if (document.activeElement !== champ || champ.value !== valeur) return
    champ.setSelectionRange(champ.value.length, champ.value.length)
    champ.select()
  }
  setTimeout(reposer, 0)

  let attente: ReturnType<typeof setTimeout> | undefined
  const apresMouvement = () => {
    clearTimeout(attente)
    attente = setTimeout(reposer, 80)
  }
  const vv = window.visualViewport
  vv?.addEventListener("resize", apresMouvement)
  vv?.addEventListener("scroll", apresMouvement)
  window.addEventListener("scroll", apresMouvement, true)
  setTimeout(() => {
    vv?.removeEventListener("resize", apresMouvement)
    vv?.removeEventListener("scroll", apresMouvement)
    window.removeEventListener("scroll", apresMouvement, true)
  }, 1200)
}
