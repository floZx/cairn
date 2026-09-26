import { useState, type FormEvent, type ReactNode } from "react"
import { Symbole } from "./IconeSport"
import { ouvrirAvecBiometrie, ouvrirAvecMotDePasse, useVerrou } from "./verrou"

/// Ce qui s'affiche à la place du journal tant qu'il est fermé — le pendant
/// de `JournalLockView` sur le Mac.
///
/// Face ID n'est pas demandé tout seul en arrivant, contrairement au Mac : le
/// navigateur ne le permet qu'au doigt, sur un bouton. Le mot de passe est
/// dessous, toujours, pour le jour où Face ID ne passe pas.
export function VerrouJournal({ children }: { children: ReactNode }) {
  const { reglage, ouvert } = useVerrou()
  const [motDePasse, setMotDePasse] = useState("")
  const [erreur, setErreur] = useState<string | null>(null)
  const [enCours, setEnCours] = useState(false)

  if (ouvert) return <>{children}</>

  const biometrie = async () => {
    setErreur(null)
    if (!(await ouvrirAvecBiometrie())) {
      setErreur("Pas reconnu. Le mot de passe du compte ouvre aussi le journal.")
    }
  }

  const envoyer = async (e: FormEvent) => {
    e.preventDefault()
    setEnCours(true)
    setErreur(null)
    const ok = await ouvrirAvecMotDePasse(motDePasse)
    setEnCours(false)
    if (ok) setMotDePasse("")
    else setErreur("Mot de passe refusé.")
  }

  return (
    <div className="verrou-journal">
      <Symbole nom="lock" taille={44} />
      <h2>Journal verrouillé</h2>
      <p className="attenue petit">Pour que ce qui est écrit là reste à vous.</p>
      {reglage.passkey && (
        <button className="bouton" onClick={biometrie}>
          Déverrouiller
        </button>
      )}
      <form onSubmit={envoyer} className="verrou-mot-de-passe">
        <input
          className="champ"
          type="password"
          autoComplete="current-password"
          placeholder="Mot de passe du compte"
          value={motDePasse}
          onChange={(e) => setMotDePasse(e.target.value)}
        />
        <button
          className={reglage.passkey ? "action-lien" : "bouton"}
          type="submit"
          disabled={!motDePasse || enCours}
        >
          {enCours ? "Vérification…" : "Ouvrir avec le mot de passe"}
        </button>
      </form>
      {erreur && <p className="attenue petit">{erreur}</p>}
    </div>
  )
}
