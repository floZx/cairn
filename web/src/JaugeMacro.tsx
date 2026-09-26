import { dansLeMille, depassement } from "./macros"

/// L'état d'un chiffre face à son objectif — la règle des couleurs, partout la
/// même : rien tant que la journée se construit, vert dès que l'objectif est à
/// un dixième près, orange tant qu'on le dépasse de peu, rouge une fois
/// franchement dépassé. Le dépassement répond en premier : l'avertissement
/// prime sur l'encouragement.
export function etatDe(consomme: number, objectif: number | null): string | null {
  if (objectif === null || objectif <= 0) return null
  const d = depassement(consomme, objectif)
  if (d === "franc") return "franc"
  if (d === "modere") return "modere"
  return dansLeMille(consomme, objectif) ? "atteint" : null
}

const arrondi = (v: number) => String(Math.round(v))

function Barre({ consomme, objectif, etat }: { consomme: number; objectif: number; etat: string | null }) {
  return (
    <div className="barre-jauge">
      {/* Plafonnée à un : au-delà, une barre qui déborderait de son rail ne
          dirait rien de plus que la couleur ne dit déjà. */}
      <div
        className={"remplissage" + (etat ? " " + etat : "")}
        style={{ width: `${Math.min(consomme / objectif, 1) * 100}%` }}
      />
    </div>
  )
}

/// Le bilan de la journée : les calories d'abord, en grand — la question
/// qu'on se pose en ouvrant l'écran est « combien il me reste » —, puis les
/// trois macros, plus petites, côte à côte.
///
/// Quatre jauges identiques ne hiérarchisaient rien : même taille, même
/// barre bleue pour les calories et pour les lipides.
export function BilanDuJour({
  typeDuJour,
  onType,
  kcal,
  proteines,
  glucides,
  lipides,
}: {
  /// Le type de journée, qui fixe l'objectif : son nom en tête du bilan, et
  /// c'est là qu'on le change.
  typeDuJour: string | null
  onType: () => void
  kcal: { consomme: number; objectif: number | null }
  proteines: { consomme: number; objectif: number | null }
  glucides: { consomme: number; objectif: number | null }
  lipides: { consomme: number; objectif: number | null }
}) {
  const etatKcal = etatDe(kcal.consomme, kcal.objectif)
  const cible = kcal.objectif && kcal.objectif > 0 ? kcal.objectif : null
  // Sur les chiffres arrondis qu'on affiche : pris sur les valeurs brutes, il
  // annonçait « dépassé de 1 » sous un « 33 / 33 » qui ne dépasse rien.
  const reste = cible === null ? null : Math.round(cible) - Math.round(kcal.consomme)

  return (
    <div className="bilan">
      <button className="type-journee" onClick={onType}>
        {typeDuJour ?? "Choisir le type de journée"}
        <span aria-hidden> ›</span>
      </button>
      <div className="bilan-kcal">
        <span className={"bilan-grand" + (etatKcal ? " " + etatKcal : "")}>
          {reste === null ? arrondi(kcal.consomme) : arrondi(Math.abs(reste))}
        </span>
        <span className="bilan-legende">
          {reste === null ? "kcal" : reste >= 0 ? "kcal restantes" : "kcal de trop"}
        </span>
        {cible !== null && (
          <span className="bilan-sur">
            {arrondi(kcal.consomme)} / {arrondi(cible)}
          </span>
        )}
      </div>
      {cible !== null && <Barre consomme={kcal.consomme} objectif={cible} etat={etatKcal} />}
      <div className="bilan-macros">
        <Macro titre="Protéines" {...proteines} />
        <Macro titre="Glucides" {...glucides} />
        <Macro titre="Lipides" {...lipides} />
      </div>
    </div>
  )
}

function Macro({ titre, consomme, objectif }: { titre: string; consomme: number; objectif: number | null }) {
  const etat = etatDe(consomme, objectif)
  const cible = objectif && objectif > 0 ? objectif : null
  return (
    <div className="macro">
      <div className="macro-titre">{titre}</div>
      <div className={"macro-chiffre" + (etat ? " " + etat : "")}>
        {arrondi(consomme)}
        {cible !== null && <span className="attenue"> / {arrondi(cible)}</span>}
        <span className="attenue"> g</span>
      </div>
      {cible !== null && <Barre consomme={consomme} objectif={cible} etat={etat} />}
    </div>
  )
}
