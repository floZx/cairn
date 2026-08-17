import { useEffect, useState } from "react"
import type { Session } from "@supabase/supabase-js"
import { supabase } from "./supabase"
import { SignIn } from "./SignIn"
import { ActivityList } from "./ActivityList"
import { ActivityDetail } from "./ActivityDetail"
import { Journal } from "./Journal"
import { Nutrition } from "./Nutrition"
import { Stats } from "./Stats"
import { Chrome, type Section } from "./Chrome"
import { BoutonCompte } from "./Compte"

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

  const [section, setSection] = useState<Section>("activites")

  function ouvrir(uuid: string) {
    history.pushState(null, "", `?activite=${uuid}`)
    setOuverte(uuid)
  }

  if (!ready) return null
  if (!session) return <SignIn />

  const surUneFiche = ouverte !== null

  return (
    <Chrome
      section={section}
      onSection={setSection}
      masquerOnglets={surUneFiche}
      action={<BoutonCompte />}
    >
      {surUneFiche ? (
        <ActivityDetail uuid={ouverte} onRetour={() => history.back()} />
      ) : section === "activites" ? (
        <ActivityList onOuvrir={ouvrir} />
      ) : section === "journal" ? (
        <Journal />
      ) : section === "nutrition" ? (
        <Nutrition />
      ) : (
        <Stats />
      )}
    </Chrome>
  )
}
