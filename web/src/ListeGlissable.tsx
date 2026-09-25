import { useEffect, useRef, useState, type ReactNode } from "react"

/// Une liste qu'on réordonne au doigt, comme dans Rappels : un appui long
/// soulève la ligne, elle suit le doigt, les autres s'écartent pour lui faire
/// place, et lâcher pose le nouvel ordre.
///
/// Ce qui ne doit pas changer, et ne change pas : un appui bref ouvre la ligne
/// comme avant, et un glissement rapide fait défiler la page — le doigt qui
/// bouge avant la fin de l'appui long est un défilement, pas une prise.
///
/// Remplace le mode « ⇅ » et ses flèches, qui demandaient d'entrer dans un
/// mode puis de toucher une flèche par cran — « pas naturel », signalé.
const APPUI_LONG_MS = 400
/// Ce que le doigt peut trembler pendant l'appui long sans que ce soit pris
/// pour un défilement.
const TOLERANCE_PX = 8

type Prise = {
  uuid: string
  /// Sa place au moment où on l'a prise.
  depuis: number
  /// Où le doigt s'est posé, et de combien il a bougé depuis.
  origine: number
  decalage: number
  /// La hauteur d'une ligne, mesurée à la prise : c'est elle qui dit combien
  /// de places le doigt a franchies.
  hauteur: number
}

export function ListeGlissable<T extends { uuid: string }>({
  elements,
  ligne,
  onOrdre,
}: {
  elements: T[]
  /// Le contenu d'une ligne — le bouton qui l'ouvre.
  ligne: (element: T) => ReactNode
  /// Le nouvel ordre, par identifiants, quand une ligne a changé de place.
  onOrdre: (ordre: string[]) => void
}) {
  const [prise, setPrise] = useState<Prise | null>(null)
  const priseRef = useRef<Prise | null>(null)
  priseRef.current = prise

  /// L'ordre qu'on vient de poser, montré en attendant que la base le
  /// confirme : sans lui, la ligne lâchée revenait à sa place d'avant le temps
  /// de l'aller-retour, puis sautait à la nouvelle.
  const [ordrePose, setOrdrePose] = useState<string[] | null>(null)
  useEffect(() => setOrdrePose(null), [elements])

  const attente = useRef<{ minuterie: number; x: number; y: number } | null>(null)
  /// Vrai juste après un glisser : le clic que le navigateur émet au lever du
  /// doigt ne doit pas ouvrir la ligne qu'on vient de poser.
  const vientDeGlisser = useRef(false)

  // Pendant qu'une ligne est tenue, la page ne défile plus : sur iOS, seul un
  // `touchmove` non passif peut l'en empêcher, et il faut l'avoir avant que le
  // défilement ne commence — le doigt, immobile pendant l'appui long, n'en a
  // encore déclenché aucun.
  useEffect(() => {
    if (!prise) return
    const bloquer = (e: TouchEvent) => e.preventDefault()
    document.addEventListener("touchmove", bloquer, { passive: false })
    return () => document.removeEventListener("touchmove", bloquer)
  }, [prise !== null])

  const base = ordrePose
    ? ordrePose.map((u) => elements.find((e) => e.uuid === u)).filter((e): e is T => !!e)
    : elements

  const cible = prise
    ? Math.max(
        0,
        Math.min(base.length - 1, prise.depuis + Math.round(prise.decalage / prise.hauteur)),
      )
    : null
  const affiches =
    prise && cible !== null
      ? (() => {
          const copie = base.filter((e) => e.uuid !== prise.uuid)
          copie.splice(cible, 0, base[prise.depuis])
          return copie
        })()
      : base

  const annulerAttente = () => {
    if (attente.current) clearTimeout(attente.current.minuterie)
    attente.current = null
  }

  const terminer = () => {
    annulerAttente()
    const p = priseRef.current
    if (!p) return
    const arrivee = Math.max(
      0,
      Math.min(base.length - 1, p.depuis + Math.round(p.decalage / p.hauteur)),
    )
    vientDeGlisser.current = true
    // Rendu au prochain tour : le clic du lever arrive juste après.
    setTimeout(() => (vientDeGlisser.current = false), 0)
    setPrise(null)
    if (arrivee !== p.depuis) {
      const ordre = base.filter((e) => e.uuid !== p.uuid).map((e) => e.uuid)
      ordre.splice(arrivee, 0, p.uuid)
      setOrdrePose(ordre)
      onOrdre(ordre)
    }
  }

  return (
    <ul
      className={prise ? "aliments en-glissement" : "aliments"}
      onClickCapture={(e) => {
        if (vientDeGlisser.current) {
          e.stopPropagation()
          e.preventDefault()
        }
      }}
    >
      {affiches.map((element) => {
        const tenue = prise?.uuid === element.uuid
        const style =
          tenue && prise && cible !== null
            ? {
                transform: `translateY(${prise.decalage - (cible - prise.depuis) * prise.hauteur}px)`,
              }
            : undefined
        return (
          <li
            key={element.uuid}
            className={tenue ? "souleve" : undefined}
            style={style}
            onPointerDown={(e) => {
              if (e.button !== 0 || priseRef.current) return
              const li = e.currentTarget
              const pointeur = e.pointerId
              const y = e.clientY
              const depuis = base.findIndex((b) => b.uuid === element.uuid)
              annulerAttente()
              attente.current = {
                x: e.clientX,
                y,
                minuterie: window.setTimeout(() => {
                  attente.current = null
                  // Pour que la ligne suive le doigt même quand il sort d'elle.
                  // Un doigt levé a déjà annulé l'appui long (`terminer`) : si
                  // la capture échoue malgré tout, la prise se fait sans elle.
                  try {
                    li.setPointerCapture(pointeur)
                  } catch {
                    // Rien : les mouvements arrivent encore tant que le doigt
                    // reste sur la ligne.
                  }
                  navigator.vibrate?.(10)
                  setPrise({
                    uuid: element.uuid,
                    depuis,
                    origine: y,
                    decalage: 0,
                    hauteur: li.getBoundingClientRect().height || 36,
                  })
                }, APPUI_LONG_MS),
              }
            }}
            onPointerMove={(e) => {
              const p = priseRef.current
              if (p) {
                e.preventDefault()
                const suivie = { ...p, decalage: e.clientY - p.origine }
                // Tout de suite dans la référence, sans attendre le rendu : un
                // doigt levé juste après son dernier mouvement lisait sinon la
                // position d'avant, et la place franchie en dernier se perdait.
                // Mesuré sur un geste simulé.
                priseRef.current = suivie
                setPrise(suivie)
                return
              }
              const a = attente.current
              if (
                a &&
                (Math.abs(e.clientX - a.x) > TOLERANCE_PX ||
                  Math.abs(e.clientY - a.y) > TOLERANCE_PX)
              ) {
                annulerAttente()
              }
            }}
            onPointerUp={terminer}
            onPointerCancel={() => {
              annulerAttente()
              setPrise(null)
            }}
          >
            {ligne(element)}
          </li>
        )
      })}
    </ul>
  )
}
