import { dansLeMille, depassement, type Fibres } from "./macros"

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

/// Les fibres du jour : un chiffre qu'on cherche à atteindre, jamais à ne pas
/// dépasser.
///
/// Sœur de `JaugeMacro` plutôt que variante à drapeaux — portée de `FiberGauge`
/// côté Swift, où le même choix est fait et pour les deux mêmes raisons.
///
/// La couleur d'abord : quarante grammes pour trente visés n'est pas un
/// dépassement, c'est une bonne journée. Elle verdit à la cible et s'arrête
/// là, sans l'orange ni le rouge des autres.
///
/// Et surtout elle avoue ce qu'elle ignore. Open Food Facts ne connaît les
/// fibres que de cinq produits sur six ; « 22 / 30 g » sur une journée dont
/// trois aliments n'ont rien annoncé n'est ni vrai ni faux, il est incomplet.
export function JaugeFibres({
  fibres,
  objectif,
}: {
  fibres: Fibres
  objectif: number
}) {
  const entier = (v: number) => String(Math.round(v))
  /// Atteinte dès neuf dixièmes, et pour toujours au-delà : la clémence de
  /// `dansLeMille`, sans sa borne haute.
  const atteint = objectif > 0 && Math.round(fibres.grammes) >= Math.round(objectif * 0.9)

  /// Ce qui reste, ou ce qu'on ignore — jamais les deux, et le manque d'abord.
  /// Un « reste 8 g » calculé sur une journée trouée dirait un chiffre précis
  /// à propos d'une somme qui ne l'est pas.
  const sousLigne = () => {
    if (fibres.inconnus > 0) {
      return `${fibres.inconnus} aliment${fibres.inconnus > 1 ? "s" : ""} sans donnée`
    }
    const reste = Math.round(objectif) - Math.round(fibres.grammes)
    return reste > 0 ? `reste ${entier(reste)} g` : "objectif atteint"
  }

  return (
    <div className="jauge">
      <div className="titre-jauge">
        Fibres <span className="unite-jauge">g</span>
      </div>
      <div className={"chiffre-jauge" + (atteint ? " atteint" : "")}>
        {entier(fibres.grammes)} / {entier(objectif)}
      </div>
      {objectif > 0 && (
        <>
          <div className="barre-jauge">
            <div
              className={"remplissage" + (atteint ? " atteint" : "")}
              style={{ width: `${Math.min(fibres.grammes / objectif, 1) * 100}%` }}
            />
          </div>
          <div className={"reste-jauge" + (atteint ? " atteint" : "")}>{sousLigne()}</div>
        </>
      )}
    </div>
  )
}
