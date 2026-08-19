import { useEffect, useState } from "react"
import type { Session } from "@supabase/supabase-js"
import { supabase } from "./supabase"
import { SignIn } from "./SignIn"
import { ActivityList } from "./ActivityList"
import { ActivityDetail } from "./ActivityDetail"
import { Journal } from "./Journal"
import { People } from "./People"
import { SelecteurJournal, type VueJournal } from "./SelecteurJournal"
import { Entrainement } from "./Entrainement"
import { Nutrition } from "./Nutrition"
import { Stats } from "./Stats"
import { Chrome, type Section } from "./Chrome"
import { AUCUN, type Filtre } from "./criteres"
import { presentationRetenue, type Vue } from "./vues"
import { SelecteurVue } from "./SelecteurVue"
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

  /// Ce que le retour de Strava a donné, quand il a quelque chose à dire.
  ///
  /// Une connexion qui échoue en silence renvoie sur la liste d'activités, et
  /// rien ne distingue ce cas-là d'une connexion réussie : c'est exactement
  /// l'ambiguïté rencontrée au premier essai.
  const [motStrava, setMotStrava] = useState<string | null>(null)

  useEffect(() => {
    const params = new URLSearchParams(location.search)
    const issue = params.get("strava")
    if (!issue) return
    const cause = params.get("cause")
    history.replaceState(null, "", location.pathname)
    setMotStrava(
      issue === "refus"
        ? `Autorisation refusée chez Strava${cause ? ` (${cause})` : ""}.`
        : `Strava a refusé l'échange${cause ? ` : ${cause}` : ""}.`,
    )
  }, [])

  // Le retour de Strava dépose son jeton dans le fragment de l'URL — la seule
  // partie qui ne part jamais au serveur ni dans les journaux. La page le
  // range sous son identité, puis l'efface de la barre d'adresse.
  useEffect(() => {
    if (!location.hash.includes("strava_access")) return
    const recu = new URLSearchParams(location.hash.slice(1))
    const jeton = {
      access_token: recu.get("strava_access") ?? "",
      refresh_token: recu.get("strava_refresh") ?? "",
      expires_at: Number(recu.get("strava_expire") ?? 0),
    }
    history.replaceState(null, "", location.pathname)
    if (!jeton.access_token) return
    supabase.auth.getSession().then(({ data }) => {
      const session = data.session?.access_token
      if (!session) {
        // Le cas qui guette sur iPhone : l'autorisation s'est faite dans
        // Safari, où l'application n'a pas de session, et le jeton arrive dans
        // une fenêtre qui ne peut rien en faire. Mieux vaut le dire que de le
        // perdre sans bruit.
        setMotStrava(
          "Jeton reçu, mais cette fenêtre n'est pas connectée à Cairn. "
            + "Refais « Connecter Strava » depuis l'application.",
        )
        return
      }
      fetch("/strava/retour", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${session}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(jeton),
      })
        .then((r) => {
          setMotStrava(r.ok ? "Strava connecté." : "Le jeton n'a pas pu être rangé.")
        })
        .catch(() => setMotStrava("Le jeton n'a pas pu être rangé."))
    })
  }, [])

  const [section, setSection] = useState<Section>("activites")
  /// L'onglet Journal montre deux choses : les journées, et les gens qui y
  /// sont cités. Un sixième onglet ne tenait pas dans la capsule — c'est déjà
  /// pour ça qu'« Entraînement » s'y appelle « Plan » — et People est de toute
  /// façon une façon de lire le journal, pas un ailleurs.
  const [vueJournal, setVueJournal] = useState<VueJournal>("journees")

  // Le jour d'arrivée dans les repas, quand on y va depuis une citation du
  // journal. Effacé dès qu'on choisit un onglet à la main : sans quoi revenir
  // sur « Repas » trois jours plus tard rouvrirait la journée d'alors.
  const [jourRepas, setJourRepas] = useState<string | null>(null)
  const changerDeSection = (s: Section) => {
    setJourRepas(null)
    // Une fiche est une page poussée : partir vers un onglet la referme, comme
    // le chevron le ferait. Sans ça, la barre étant désormais visible depuis
    // une fiche, on changeait d'onglet sans rien voir changer — la fiche
    // restant devant.
    if (ouverte !== null) history.back()
    setSection(s)
  }

  // Le filtre et la vue choisie vivent ici, et non dans la liste : ouvrir une
  // fiche démonte la liste, et son état partait avec elle. On filtrait, on
  // ouvrait un résultat, on revenait — et tout était à refaire.
  const [filtre, setFiltre] = useState<Filtre>(AUCUN)
  // Amorcée sur la présentation retenue de la dernière fois — jamais sur la
  // carte, qui est un endroit où l'on va et non une préférence.
  const [vue, setVue] = useState<Vue>(presentationRetenue)

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
      // Seulement sur les activités : c'est la seule section qui se regarde de
      // trois façons.
      entete={
        surUneFiche ? undefined : section === "activites" ? (
          <SelecteurVue vue={vue} onVue={setVue} />
        ) : section === "journal" ? (
          <SelecteurJournal vue={vueJournal} onVue={setVueJournal} />
        ) : undefined
      }
      action={<BoutonCompte />}
    >
      {motStrava && (
        <p className="mot-strava" onClick={() => setMotStrava(null)}>
          {motStrava}
        </p>
      )}
      {surUneFiche ? (
        <ActivityDetail uuid={ouverte} onOuvrir={ouvrir} />
      ) : section === "activites" ? (
        <ActivityList
          onOuvrir={ouvrir}
          filtre={filtre}
          onFiltre={setFiltre}
          vue={vue}
          onVue={setVue}
        />
      ) : section === "plan" ? (
        <Entrainement onOuvrir={ouvrir} />
      ) : section === "journal" ? (
        vueJournal === "gens" ? (
          <People onOuvrir={ouvrir} />
        ) : (
        <Journal
          onActivite={ouvrir}
          onRepas={(dateKey) => {
            setJourRepas(dateKey)
            setSection("nutrition")
          }}
        />
        )
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
