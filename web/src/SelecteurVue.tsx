import { retenirPresentation, type Vue } from "./vues"

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
  const commun = {
    width: 19,
    height: 19,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
  }
  switch (nom) {
    case "liste":
      return (
        <svg {...commun}>
          <path d="M4 7h16M4 12h16M4 17h16" />
        </svg>
      )
    case "fiches":
      // Le `rectangle.grid.1x2` du Mac, qui désigne là-bas la même chose.
      return (
        <svg {...commun}>
          <rect x="3.5" y="4" width="17" height="7" rx="2" />
          <rect x="3.5" y="13" width="17" height="7" rx="2" />
        </svg>
      )
    default:
      return (
        <svg {...commun}>
          <path d="M9 4L3 6.5v13L9 17l6 3 6-2.5v-13L15 7z M9 4v13 M15 7v13" />
        </svg>
      )
  }
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
