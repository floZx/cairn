import { retenirPresentation, type Vue } from "./vues"
import { Symbole } from "./IconeSport"

/// Les trois vues dans l'ordre du sélecteur : les deux listes d'abord, la
/// carte au bout — on quitte une liste pour la carte, on ne traverse pas la
/// carte pour passer d'une liste à l'autre.
const VUES: { id: Vue; nom: string }[] = [
  { id: "liste", nom: "Liste" },
  { id: "fiches", nom: "Fiches" },
  { id: "carte", nom: "Carte" },
]

/// Les trois symboles du sélecteur, à la ligne comme ceux de la barre
/// d'onglets : des lignes empilées, deux fiches l'une sur l'autre, une carte
/// pliée.
function IconeVue({ nom }: { nom: Vue }) {
  // Les symboles du Mac : `list.bullet` pour la liste, `rectangle.grid.1x2`
  // pour les fiches — celui du sélecteur de la barre d'outils là-bas —, `map`.
  const symbole = nom === "liste" ? "list.bullet" : nom === "fiches" ? "rectangle.grid.1x2" : "map"
  return <Symbole nom={symbole} taille={19} />
}

/// Les trois présentations, dans la ligne du grand titre.
///
/// Là-haut et non dans la ligne de recherche, où il partageait la largeur avec
/// le champ et le bouton de filtres : trois éléments pour une seule ligne, dont
/// un qui se faisait rogner son texte — « Rechercher une sortie… » avait déjà
/// dû devenir « Rechercher… » pour lui faire place.
///
/// Le titre, lui, occupe une ligne entière pour un seul mot. C'est là que la
/// place est, et c'est là que le sélecteur dit ce qu'il est : un réglage de
/// l'écran entier, au même rang que son nom, pas un accessoire de la recherche.
///
/// Un sélecteur segmenté plutôt que trois boutons — il dit qu'ils s'excluent.
export function SelecteurVue({
  vue,
  onVue,
}: {
  vue: Vue
  onVue: (v: Vue) => void
}) {
  return (
    <div className="segments-vue" role="group" aria-label="Présentation">
      {VUES.map((v) => (
        <button
          key={v.id}
          className={vue === v.id ? "segment actif" : "segment"}
          onClick={() => {
            // Retenue tout de suite, et seulement quand ce n'est pas la carte :
            // voir `vues.ts` pour ce qui se garde d'une ouverture à l'autre.
            if (v.id !== "carte") retenirPresentation(v.id)
            onVue(v.id)
          }}
          aria-label={v.nom}
          aria-pressed={vue === v.id}
        >
          <IconeVue nom={v.id} />
        </button>
      ))}
    </div>
  )
}
