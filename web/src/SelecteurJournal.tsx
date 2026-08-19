/// Le sélecteur du journal : les journées, ou les gens qui y sont cités.
///
/// En icônes et non en mots, comme celui des activités : la ligne du titre
/// n'a que la place qui reste à côté d'un grand mot, et « Journées » y arrivait
/// coupé en deux. Mesuré à 400 points de large.
export type VueJournal = "journees" | "gens"

function Icone({ nom }: { nom: VueJournal }) {
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
  return nom === "journees" ? (
    // Le carnet de la barre d'onglets, en plus petit : c'est la même chose
    // qu'il désigne.
    <svg {...commun}>
      <path d="M5 4.5A1.5 1.5 0 016.5 3H18a1 1 0 011 1v16a1 1 0 01-1 1H6.5A1.5 1.5 0 015 19.5z" />
      <path d="M5 17.5h14M9 7.5h6" />
    </svg>
  ) : (
    // Une arobase : le caractère qui fait la fonctionnalité, et le seul dessin
    // qui n'ait rien à expliquer.
    <svg {...commun}>
      <circle cx="12" cy="12" r="4" />
      <path d="M16 8v5a2.5 2.5 0 005 0v-1a9 9 0 10-3.5 7.1" />
    </svg>
  )
}

export function SelecteurJournal({
  vue,
  onVue,
}: {
  vue: VueJournal
  onVue: (v: VueJournal) => void
}) {
  return (
    <div className="segments-vue" role="group" aria-label="Vue du journal">
      {(["journees", "gens"] as VueJournal[]).map((v) => (
        <button
          key={v}
          className={vue === v ? "segment actif" : "segment"}
          onClick={() => onVue(v)}
          aria-label={v === "journees" ? "Journées" : "People"}
          aria-pressed={vue === v}
        >
          <Icone nom={v} />
        </button>
      ))}
    </div>
  )
}
