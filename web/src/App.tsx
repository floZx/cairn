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
import { AUCUN, type Filtre } from "./criteres"
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

  // Le jour d'arrivée dans les repas, quand on y va depuis une citation du
  // journal. Effacé dès qu'on choisit un onglet à la main : sans quoi revenir
  // sur « Repas » trois jours plus tard rouvrirait la journée d'alors.
  const [jourRepas, setJourRepas] = useState<string | null>(null)
  const changerDeSection = (s: Section) => {
    setJourRepas(null)
    setSection(s)
  }

  // Le filtre et la vue carte vivent ici, et non dans la liste : ouvrir une
  // fiche démonte la liste, et son état partait avec elle. On filtrait, on
  // ouvrait un résultat, on revenait — et tout était à refaire.
  const [filtre, setFiltre] = useState<Filtre>(AUCUN)
  const [surLaCarte, setSurLaCarte] = useState(false)

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
      onSection={changerDeSection}
      masquerOnglets={surUneFiche}
      retour={surUneFiche ? () => history.back() : undefined}
      action={<BoutonCompte />}
    >
      {surUneFiche ? (
        <ActivityDetail uuid={ouverte} />
      ) : section === "activites" ? (
        <ActivityList
          onOuvrir={ouvrir}
          filtre={filtre}
          onFiltre={setFiltre}
          surLaCarte={surLaCarte}
          onCarte={setSurLaCarte}
        />
      ) : section === "journal" ? (
        <Journal
          onActivite={ouvrir}
          onRepas={(dateKey) => {
            setJourRepas(dateKey)
            setSection("nutrition")
          }}
        />
      ) : section === "nutrition" ? (
        // La clef force un remontage : le jour d'arrivée est lu à la
        // construction, et sans elle une seconde téléportation ne bougerait
        // rien.
        <Nutrition key={jourRepas ?? "aujourd'hui"} jourInitial={jourRepas ?? undefined} />
      ) : (
        <Stats />
      )}
    </Chrome>
  )
}
