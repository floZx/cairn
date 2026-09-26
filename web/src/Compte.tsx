import { useEffect, useState } from "react"
import { Symbole } from "./IconeSport"
import { useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { Feuille } from "./Chrome"
import {
  activer,
  ajouterBiometrie,
  biometrieConnue,
  choisirDelai,
  DELAIS,
  desactiver,
  useVerrou,
  verrouiller,
} from "./verrou"

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
  const [connecte, setConnecte] = useState<boolean | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [enCours, setEnCours] = useState(false)
  const client = useQueryClient()

  useEffect(() => {
    if (!ouvert) return
    supabase.auth.getUser().then(({ data }) => setCourriel(data.user?.email ?? null))
    supabase
      .from("strava_token")
      .select("user_id")
      .maybeSingle()
      // L'erreur est avalée : tant que la migration 009 n'est pas passée, la
      // table n'existe pas, et ce n'est pas une raison pour que la feuille du
      // compte disparaisse derrière un message.
      .then(({ data }) => setConnecte(data !== null))
  }, [ouvert])

  /// Va chercher chez Strava ce que le miroir n'a pas encore.
  ///
  /// Le Mac reste la source de vérité : ce que ce bouton pose est une ligne
  /// sommaire, que le Mac complétera sans la dédoubler. Voir
  /// `functions/strava/import.ts`.
  const chercher = async () => {
    setEnCours(true)
    setMessage(null)
    try {
      const { data } = await supabase.auth.getSession()
      const jeton = data.session?.access_token
      if (!jeton) throw new Error("Session expirée, reconnecte-toi.")
      const reponse = await fetch("/strava/import", {
        method: "POST",
        headers: { Authorization: `Bearer ${jeton}` },
      })
      const corps = (await reponse.json()) as {
        importees?: number
        vues?: number
        erreur?: string
      }
      if (corps.erreur) throw new Error(corps.erreur)
      // Trois issues et non deux : « rien de neuf » disait la même chose que
      // Strava n'ait rien renvoyé ou que tout fût déjà connu, et c'est
      // exactement ce qui a masqué le défaut de pagination. Le compte de ce
      // qui a été vu chez eux tranche.
      setMessage(
        corps.importees
          ? `${corps.importees} sortie${corps.importees > 1 ? "s" : ""} importée${corps.importees > 1 ? "s" : ""}.`
          : corps.vues
            ? `${corps.vues} sorties vues chez Strava, toutes déjà dans Cairn.`
            : "Strava n'a renvoyé aucune sortie.",
      )
      client.invalidateQueries({ queryKey: ["activites"] })
      client.invalidateQueries({ queryKey: ["journal-journees"] })
    } catch (e) {
      setMessage((e as Error).message)
    } finally {
      setEnCours(false)
    }
  }

  return (
    <>
      {/* Un onglet de la barre du bas, et non plus un rond en haut à droite :
          le pouce y est déjà, et le haut de l'écran n'a plus que le titre.
          Il ouvre une feuille au lieu de changer d'écran — le compte n'est
          pas un endroit où l'on reste. */}
      <button className="onglet-bas" onClick={() => setOuvert(true)}>
        <span className="dedans-onglet">
          <Symbole nom="onglet/person.crop.circle" taille={26} />
          <span>Compte</span>
        </span>
      </button>

      {ouvert && (
        <Feuille titre="Compte" onFerme={() => setOuvert(false)}>
          <h2 className="titre-feuille">Compte</h2>
          {courriel && <p className="attenue petit courriel">{courriel}</p>}
          <ul className="liste-actions">
            <li>
              {connecte ? (
                <button className="action-bleue" onClick={chercher} disabled={enCours}>
                  {enCours ? "Recherche…" : "Chercher les sorties récentes"}
                </button>
              ) : (
                <a className="action-lien" href="/strava/connexion">
                  Connecter Strava
                </a>
              )}
            </li>
          </ul>
          {message && <p className="attenue petit">{message}</p>}
          {/* Ce que ce bouton fait, et surtout ce qu'il ne fait pas : le Mac
              reste seul à tout télécharger. */}
          <p className="attenue minuscule">
            Le téléphone ne pose que le résumé d'une sortie — nom, chiffres,
            tracé. Le Mac la complétera à sa prochaine synchronisation, sans la
            dédoubler.
          </p>
          <VerrouReglage />
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
          {/* Le domaine d'où l'application tourne vraiment.
              Strava n'accepte de renvoyer que vers le domaine déclaré dans les
              réglages de l'application, et une PWA ajoutée à l'écran d'accueil
              garde pour toujours l'adresse depuis laquelle on l'a ajoutée —
              qui peut être une URL de déploiement à empreinte. Impossible de
              le savoir de l'extérieur : sans barre d'adresse, rien ne le dit.
              Une ligne ici répond en une seconde. */}
          <p className="attenue minuscule empreinte">
            Version {__EMPREINTE__} · {location.host}
          </p>
        </Feuille>
      )}
    </>
  )
}

/// Le verrou du journal, réglé pour ce téléphone : voir `verrou.ts`.
function VerrouReglage() {
  const { reglage, ouvert } = useVerrou()
  const [enCours, setEnCours] = useState(false)

  const basculer = async () => {
    if (reglage.actif) {
      desactiver()
      return
    }
    setEnCours(true)
    await activer()
    setEnCours(false)
  }

  return (
    <>
      <h3 className="titre-section-feuille">Verrou du journal</h3>
      <ul className="liste-actions liste-reglages">
        <li>
          <label className="ligne-reglage">
            <span>Verrouiller le journal</span>
            <input
              type="checkbox"
              className="interrupteur"
              checked={reglage.actif}
              disabled={enCours}
              onChange={basculer}
            />
          </label>
        </li>
        {reglage.actif && (
          <li>
            <label className="ligne-reglage">
              <span>Le refermer</span>
              <select
                value={reglage.delai}
                onChange={(e) => choisirDelai(Number(e.target.value))}
              >
                {DELAIS.map((d) => (
                  <option key={d.minutes} value={d.minutes}>
                    {d.libelle}
                  </option>
                ))}
              </select>
            </label>
          </li>
        )}
        {reglage.actif && !reglage.passkey && biometrieConnue() && (
          <li>
            <button className="action-bleue" onClick={() => void ajouterBiometrie()}>
              Activer Face ID
            </button>
          </li>
        )}
        {reglage.actif && ouvert && (
          <li>
            <button className="action-bleue" onClick={verrouiller}>
              Verrouiller maintenant
            </button>
          </li>
        )}
      </ul>
      <p className="attenue minuscule">
        {reglage.actif
          ? reglage.passkey
            ? "Face ID ou Touch ID pour l'ouvrir, ou le mot de passe du compte. "
            : "Le mot de passe du compte pour l'ouvrir. "
          : "Sur ce téléphone seulement. "}
        Il protège d'un regard, pas davantage : les notes ne sont pas chiffrées.
      </p>
    </>
  )
}
