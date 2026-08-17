import { useState, type FormEvent } from "react"
import { supabase } from "./supabase"

/// Adresse et mot de passe, pas de lien magique : le compte est créé à la main
/// dans le tableau de bord Supabase, il n'y en a qu'un, et le lien magique
/// demanderait de configurer l'envoi de courriel pour zéro gain.
export function SignIn() {
  const [email, setEmail] = useState("")
  const [password, setPassword] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function submit(event: FormEvent) {
    event.preventDefault()
    setBusy(true)
    setError(null)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    // Pas de `setBusy(false)` en cas de succès : `onAuthStateChange` remplace
    // cet écran, et remettre le bouton à l'état actif ferait clignoter une
    // interface qui s'en va.
    if (error) {
      setError(
        error.message === "Invalid login credentials"
          ? "Adresse ou mot de passe incorrect."
          : error.message,
      )
      setBusy(false)
    }
  }

  return (
    <div className="centre">
      <form className="carte" onSubmit={submit}>
        <h1>Cairn</h1>
        <p className="sous">Votre journal, partout.</p>
        <input
          className="champ"
          type="email"
          inputMode="email"
          autoComplete="username"
          placeholder="Adresse"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <input
          className="champ"
          type="password"
          autoComplete="current-password"
          placeholder="Mot de passe"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
        />
        {error && <p className="erreur">{error}</p>}
        <button className="bouton" type="submit" disabled={busy}>
          {busy ? "Connexion…" : "Se connecter"}
        </button>
      </form>
    </div>
  )
}
