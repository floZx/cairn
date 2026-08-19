import { useEffect, useState } from "react"
import { supabase } from "./supabase"
import { Feuille } from "./Chrome"

/// Le bouton de compte, et ce qu'il ouvre.
///
/// « Quitter » écrit en toutes lettres dans la barre était deux fautes à la
/// fois : c'est laid, et se déconnecter n'est pas une chose qu'on fait dans
/// cette application — on l'ouvre pour lire ses sorties et noter ses repas,
/// pas pour en sortir. Un bouton de compte discret la range où on va la
/// chercher quand on la cherche, c'est-à-dire presque jamais.
export function BoutonCompte() {
  const [ouvert, setOuvert] = useState(false)
  const [courriel, setCourriel] = useState<string | null>(null)

  useEffect(() => {
    if (!ouvert) return
    supabase.auth.getUser().then(({ data }) => setCourriel(data.user?.email ?? null))
  }, [ouvert])

  return (
    <>
      <button
        className="bouton-compte"
        onClick={() => setOuvert(true)}
        aria-label="Compte"
      >
        <svg
          width="26"
          height="26"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.7"
          strokeLinecap="round"
          aria-hidden
        >
          <circle cx="12" cy="12" r="9" />
          <circle cx="12" cy="10" r="3.2" />
          <path d="M5.9 19a6.4 6.4 0 0112.2 0" />
        </svg>
      </button>

      {ouvert && (
        <Feuille titre="Compte" onFerme={() => setOuvert(false)}>
          <h2 className="titre-feuille">Compte</h2>
          {courriel && <p className="attenue petit courriel">{courriel}</p>}
          <ul className="liste-actions">
            <li>
              {/* Rouge, et seul de sa carte : une action qui met dehors ne se
                  range pas à côté de celles qui ne coûtent rien. */}
              <button className="action-rouge" onClick={() => supabase.auth.signOut()}>
                Se déconnecter
              </button>
            </li>
          </ul>
          {/* Quelle version tourne vraiment. Une application posée sur l'écran
              d'accueil garde son service worker, et rien ne disait laquelle des
              builds était servie — au point de mesurer des captures d'écran
              pour le deviner. */}
          <p className="attenue minuscule empreinte">Version {__EMPREINTE__}</p>
        </Feuille>
      )}
    </>
  )
}
