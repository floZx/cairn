import { useEffect, useState } from "react"
import type { Session } from "@supabase/supabase-js"
import { supabase } from "./supabase"
import { SignIn } from "./SignIn"
import { ActivityList } from "./ActivityList"
import { ActivityDetail } from "./ActivityDetail"
import { Journal } from "./Journal"
import { Nutrition } from "./Nutrition"

export function App() {
  const [session, setSession] = useState<Session | null>(null)
  // Distinct de `session === null` : au premier rendu on ne sait pas encore
  // s'il y en a une en réserve, et afficher l'écran de connexion pendant ce
  // temps le ferait clignoter à chaque ouverture.
  const [ready, setReady] = useState(false)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setReady(true)
    })
    const { data } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next)
    })
    return () => data.subscription.unsubscribe()
  }, [])

  // Adossé à l'historique du navigateur plutôt qu'à un simple état : sur un
  // téléphone, le geste de retour est le premier réflexe, et une application
  // installée qui le laisse quitter l'écran d'accueil se fait fermer.
  const [ouverte, setOuverte] = useState<string | null>(
    () => new URLSearchParams(location.search).get("activite"),
  )

  useEffect(() => {
    const onPop = () => {
      setOuverte(new URLSearchParams(location.search).get("activite"))
    }
    addEventListener("popstate", onPop)
    return () => removeEventListener("popstate", onPop)
  }, [])

  const [section, setSection] = useState<"activites" | "journal" | "nutrition">(
    "activites",
  )

  function ouvrir(uuid: string) {
    history.pushState(null, "", `?activite=${uuid}`)
    setOuverte(uuid)
  }

  if (!ready) return null
  if (!session) return <SignIn />

  // Une fiche ouverte prend l'écran entière : les onglets ne s'affichent que
  // sur les deux listes, sans quoi le bouton « ‹ Activités » et un onglet
  // « Activités » diraient la même chose à deux endroits.
  const surUneFiche = ouverte !== null

  return (
    <>
      <header className="barre">
        <h1>Cairn</h1>
        <button className="lien" onClick={() => supabase.auth.signOut()}>
          Se déconnecter
        </button>
      </header>
      {!surUneFiche && (
        <nav className="onglets">
          <button
            className={section === "activites" ? "onglet actif" : "onglet"}
            onClick={() => setSection("activites")}
          >
            Activités
          </button>
          <button
            className={section === "journal" ? "onglet actif" : "onglet"}
            onClick={() => setSection("journal")}
          >
            Journal
          </button>
          <button
            className={section === "nutrition" ? "onglet actif" : "onglet"}
            onClick={() => setSection("nutrition")}
          >
            Repas
          </button>
        </nav>
      )}
      <main className="contenu">
        {surUneFiche ? (
          <ActivityDetail uuid={ouverte} onRetour={() => history.back()} />
        ) : section === "activites" ? (
          <ActivityList onOuvrir={ouvrir} />
        ) : section === "journal" ? (
          <Journal />
        ) : (
          <Nutrition />
        )}
      </main>
    </>
  )
}
