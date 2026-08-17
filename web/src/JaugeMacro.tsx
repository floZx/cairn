import { dansLeMille, depassement } from "./macros"

/// Un « consommé / visé » avec sa barre — l'unité du résumé de la journée,
/// portée de `MacroGauge`.
///
/// Quatre états, les mêmes que la ligne d'un repas : gris tant que la journée
/// se construit, vert dès que l'objectif est à un dixième près, orange tant
/// qu'on le dépasse de peu, rouge une fois franchement dépassé.
export function JaugeMacro({
  titre,
  consomme,
  objectif,
  unite,
}: {
  titre: string
  consomme: number
  objectif: number | null
  unite: string
}) {
  const arrondi = (v: number) => String(Math.round(v))

  /// Nul veut dire « rien à dire encore » : la barre garde la couleur d'accent
  /// et la ligne du dessous reste grise.
  ///
  /// Le dépassement répond en premier, comme sur la ligne d'un repas : un
  /// chiffre au-delà de sa cible l'est quoi qu'il soit par ailleurs, et
  /// l'avertissement prime sur l'encouragement.
  const sens = (): string | null => {
    if (objectif === null || objectif <= 0) return null
    const d = depassement(consomme, objectif)
    if (d === "franc") return "franc"
    if (d === "modere") return "modere"
    return dansLeMille(consomme, objectif) ? "atteint" : null
  }
  const etat = sens()

  /// Calculée sur les chiffres arrondis que la jauge affiche : prise sur les
  /// valeurs brutes, elle annonçait « dépassé de 1 g » sous un « 33 / 33 g »
  /// qui ne dépasse rien de visible.
  const reste = (cible: number) => {
    const r = Math.round(cible) - Math.round(consomme)
    return r >= 0 ? `reste ${arrondi(r)} ${unite}` : `dépassé de ${arrondi(-r)} ${unite}`
  }

  return (
    <div className="jauge">
      <div className="titre-jauge">
        {titre} <span className="unite-jauge">{unite}</span>
      </div>
      {/* L'unité quitte le chiffre pour le titre : sur deux colonnes de
          téléphone, « 1509 / 2400 kcal » passait à la ligne et désalignait la
          jauge d'à côté. Elle reste dite, une ligne plus bas, dans le
          « reste ». */}
      <div className={"chiffre-jauge" + (etat ? " " + etat : "")}>
        {objectif === null || objectif <= 0
          ? arrondi(consomme)
          : `${arrondi(consomme)} / ${arrondi(objectif)}`}
      </div>
      {objectif !== null && objectif > 0 && (
        <>
          <div className="barre-jauge">
            {/* Plafonnée à un : au-delà, une barre qui déborderait de son rail
                ne dirait rien de plus que la couleur ne dit déjà. */}
            <div
              className={"remplissage" + (etat ? " " + etat : "")}
              style={{ width: `${Math.min(consomme / objectif, 1) * 100}%` }}
            />
          </div>
          <div className={"reste-jauge" + (etat ? " " + etat : "")}>{reste(objectif)}</div>
        </>
      )}
    </div>
  )
}
