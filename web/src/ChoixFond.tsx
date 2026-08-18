import { useEffect, useRef, useState } from "react"
import { FONDS, type Fond } from "./fonds"

/// Le bouton de fond, posé sur la carte.
///
/// Sur la carte et non au-dessus d'elle : c'est la carte qu'on regarde en
/// changeant de fond, et un réglage rangé ailleurs oblige à faire l'aller-
/// retour pour juger du résultat. Même place et même geste que dans Plans.
export function ChoixFond({
  fond,
  onFond,
  relief,
  onRelief,
  plein,
  onPlein,
}: {
  fond: Fond
  onFond: (f: Fond) => void
  relief: boolean
  onRelief: (v: boolean) => void
  /// Absents sur la carte d'ensemble, qui occupe déjà toute la place qu'elle
  /// peut : le bouton n'apparaît que là où il a quelque chose à agrandir.
  plein?: boolean
  onPlein?: (v: boolean) => void
}) {
  const [ouvert, setOuvert] = useState(false)
  const boite = useRef<HTMLDivElement>(null)

  // Un appui ailleurs referme : sur un téléphone, il n'y a pas d'échappement
  // et un panneau qui ne se referme que par son propre bouton se fait oublier
  // ouvert au-dessus de la carte.
  useEffect(() => {
    if (!ouvert) return
    const ailleurs = (e: PointerEvent) => {
      if (!boite.current?.contains(e.target as Node)) setOuvert(false)
    }
    // `capture` : la carte avale les évènements de pointeur qui la touchent.
    addEventListener("pointerdown", ailleurs, true)
    return () => removeEventListener("pointerdown", ailleurs, true)
  }, [ouvert])

  return (
    <div className="choix-fond" ref={boite}>
      <button
        className="bouton-fond matiere"
        onClick={() => setOuvert((v) => !v)}
        aria-label="Fond de carte"
        aria-expanded={ouvert}
      >
        <svg
          width="20"
          height="20"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.7"
          strokeLinejoin="round"
          aria-hidden
        >
          <path d="M12 3l9 4.5-9 4.5-9-4.5z" />
          <path d="M3 12l9 4.5 9-4.5" />
          <path d="M3 16.5L12 21l9-4.5" />
        </svg>
      </button>

      {ouvert && (
        <div className="panneau-fond matiere">
          {(Object.keys(FONDS) as Fond[]).map((f) => (
            <button
              key={f}
              className={f === fond ? "option-fond active" : "option-fond"}
              onClick={() => {
                onFond(f)
                setOuvert(false)
              }}
            >
              {FONDS[f].nom}
            </button>
          ))}
          <label className="option-fond bascule">
            <span>Relief</span>
            <input
              type="checkbox"
              checked={relief}
              onChange={(e) => onRelief(e.target.checked)}
            />
          </label>
        </div>
      )}

      {onPlein && (
        <button
          className="bouton-fond matiere"
          onClick={() => onPlein(!plein)}
          aria-label={plein ? "Réduire la carte" : "Carte en plein écran"}
        >
          <svg
            width="19"
            height="19"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.9"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden
          >
            {plein ? (
              // Quatre flèches qui rentrent : le geste inverse, dessiné.
              <>
                <path d="M10 4v6H4M14 4v6h6M10 20v-6H4M14 20v-6h6" />
              </>
            ) : (
              <>
                <path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" />
              </>
            )}
          </svg>
        </button>
      )}
    </div>
  )
}
