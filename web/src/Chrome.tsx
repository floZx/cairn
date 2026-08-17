import { useEffect, useRef, useState, type ReactNode } from "react"
import { createPortal } from "react-dom"

/// Le châssis de l'application : ce qui ne change pas d'un écran à l'autre.
///
/// Trois choses distinguent une application d'un site, et aucune n'est
/// décorative :
///
/// - **Les onglets sont en bas.** Le pouce atteint le bas d'un téléphone, pas
///   le haut ; toutes les applications d'Apple les y mettent depuis 2007, et
///   des onglets en haut est le détail qui trahit une page web en premier.
/// - **Le grand titre se replie.** Il annonce l'écran quand on arrive, puis
///   cède la place au contenu dès qu'on défile, et laisse derrière lui une
///   barre compacte qui dit toujours où l'on est.
/// - **Les zones sûres sont respectées.** En application installée il n'y a
///   plus de barre d'adresse pour absorber l'encoche en haut ni la barre
///   d'accueil en bas : sans `env(safe-area-inset-*)`, le premier titre passe
///   sous l'heure et le dernier onglet sous le trait blanc.

export type Section = "activites" | "journal" | "nutrition"

/// Les icônes, dessinées ici plutôt qu'importées.
///
/// Trois traits chacune, à la ligne — le style d'Apple depuis qu'il a quitté
/// les icônes pleines. Une bibliothèque d'icônes pèserait cent fois ça pour
/// trois symboles, et le trait se règle ici au demi-pixel près.
function Icone({ nom, actif }: { nom: Section; actif: boolean }) {
  const commun = {
    width: 26,
    height: 26,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: actif ? 2.1 : 1.7,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
  }
  switch (nom) {
    case "activites":
      // Un relief : deux sommets, ce que l'application raconte.
      return (
        <svg {...commun}>
          <path d="M3 18l5.5-8 3.5 5 2.5-3.5L21 18z" />
          <path d="M3 21h18" />
        </svg>
      )
    case "journal":
      return (
        <svg {...commun}>
          <path d="M5 4.5A1.5 1.5 0 016.5 3H18a1 1 0 011 1v16a1 1 0 01-1 1H6.5A1.5 1.5 0 015 19.5z" />
          <path d="M5 17.5h14" />
          <path d="M9 7.5h6" />
        </svg>
      )
    default:
      // Une assiette vue de dessus, plutôt qu'une fourchette : le sujet est
      // le repas, pas le couvert.
      return (
        <svg {...commun}>
          <circle cx="12" cy="12" r="8.5" />
          <circle cx="12" cy="12" r="4" />
        </svg>
      )
  }
}

const TITRES: Record<Section, string> = {
  activites: "Activités",
  journal: "Journal",
  nutrition: "Repas",
}

export function Chrome({
  section,
  onSection,
  children,
  action,
  /// Vrai quand une fiche occupe l'écran : les onglets s'effacent, comme une
  /// vue poussée sur une pile de navigation masque la barre d'onglets, et le
  /// grand titre avec eux — la fiche porte son propre en-tête et son retour.
  masquerOnglets = false,
}: {
  section: Section
  onSection: (s: Section) => void
  children: ReactNode
  /// Le bouton de droite de la barre, s'il y en a un.
  action?: ReactNode
  masquerOnglets?: boolean
}) {
  const [replie, setReplie] = useState(false)
  const zone = useRef<HTMLDivElement>(null)

  // Deux seuils au lieu d'un : à seuil unique, un doigt posé pile dessus fait
  // clignoter le titre à chaque pixel de défilement.
  useEffect(() => {
    const cible = zone.current
    if (!cible) return
    const surDefilement = () => {
      const y = cible.scrollTop
      setReplie((etait) => (etait ? y > 24 : y > 52))
    }
    cible.addEventListener("scroll", surDefilement, { passive: true })
    return () => cible.removeEventListener("scroll", surDefilement)
  }, [])

  // Le repli est propre à l'écran : passer d'un onglet défilé à un onglet
  // remis en haut laisserait sinon un titre compact au-dessus d'un contenu
  // qui commence.
  useEffect(() => {
    zone.current?.scrollTo({ top: 0 })
    setReplie(false)
  }, [section, masquerOnglets])

  return (
    <div className="chassis">
      <header
        className={replie && !masquerOnglets ? "barre-nav repliee" : "barre-nav"}
      >
        <div className="titre-compact">{TITRES[section]}</div>
        <div className="action-barre">{action}</div>
      </header>

      <div className="defilement" ref={zone}>
        {!masquerOnglets && <h1 className="grand-titre">{TITRES[section]}</h1>}
        <main className="contenu">{children}</main>
      </div>

      {!masquerOnglets && (
        <nav className="onglets-bas matiere" aria-label="Sections">
          {(Object.keys(TITRES) as Section[]).map((s) => (
            <button
              key={s}
              className={s === section ? "onglet-bas actif" : "onglet-bas"}
              onClick={() => onSection(s)}
              aria-current={s === section ? "page" : undefined}
            >
              {/* Le contenu dans sa propre enveloppe : c'est elle qui porte la
                  pastille de l'onglet actif, et qui l'ajuste au texte plutôt
                  qu'à la largeur du tiers. Une pastille aussi large qu'un tiers
                  d'écran pour un mot de huit lettres écrase toute la barre. */}
              <span className="dedans-onglet">
                <Icone nom={s} actif={s === section} />
                <span>{TITRES[s]}</span>
              </span>
            </button>
          ))}
        </nav>
      )}
    </div>
  )
}

/// Une feuille modale, qui monte depuis le bas.
///
/// C'est la façon dont iOS présente une saisie depuis 2018 : le contenu
/// dessous reste visible et recule légèrement, ce qui dit « tu es par-dessus,
/// pas ailleurs » — un écran qui remplace brutalement le précédent laisse
/// toujours un doute sur le chemin du retour.
///
/// La poignée en haut n'est pas qu'un ornement : elle annonce qu'on peut
/// refermer en tirant vers le bas, geste que le clavier du téléphone rend
/// naturel.
export function Feuille({
  titre,
  onFerme,
  children,
}: {
  titre: string
  onFerme: () => void
  children: ReactNode
}) {
  // Montée à l'ouverture : posée à sa place finale au premier rendu, la
  // transition n'aurait rien à animer.
  const [montee, setMontee] = useState(false)
  useEffect(() => {
    const t = requestAnimationFrame(() => setMontee(true))
    return () => cancelAnimationFrame(t)
  }, [])

  useEffect(() => {
    const surEchap = (e: KeyboardEvent) => e.key === "Escape" && onFerme()
    addEventListener("keydown", surEchap)
    return () => removeEventListener("keydown", surEchap)
  }, [onFerme])

  // Rendue dans le corps du document, jamais à sa place dans l'arbre : la
  // barre de navigation porte un `backdrop-filter`, et une propriété de
  // filtre crée un **bloc conteneur** pour tout descendant en
  // `position: fixed`. Le voile s'y retrouvait enfermé, haut de quelques
  // dizaines de pixels, et la feuille s'affichait en haut de l'écran par
  //-dessus la barre au lieu de couvrir la page. Mesuré : le bouton de compte
  // vit dans cette barre.
  return createPortal(
    <div className="voile" onClick={onFerme}>
      <div
        className={montee ? "feuille-modale montee" : "feuille-modale"}
        role="dialog"
        aria-label={titre}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="poignee" aria-hidden />
        {children}
      </div>
    </div>,
    document.body,
  )
}
