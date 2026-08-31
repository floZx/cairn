import { useEffect, useRef, useState } from "react"
import type { Session } from "@supabase/supabase-js"
import { supabase } from "./supabase"
import { SignIn } from "./SignIn"
import { ActivityList } from "./ActivityList"
import { ActivityDetail } from "./ActivityDetail"
import { Journal } from "./Journal"
import { People } from "./People"
import { SelecteurJournal, type VueJournal } from "./SelecteurJournal"
import type { Citation } from "./citations"
import { Entrainement } from "./Entrainement"
import { Nutrition } from "./Nutrition"
import { Stats } from "./Stats"
import { Chrome, type Section } from "./Chrome"
import { AUCUN, type Filtre } from "./criteres"
import { presentationRetenue, type Vue } from "./vues"
import { SurUneMention } from "./markdown"
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

  /// La fiche d'une personne, dans l'historique elle aussi.
  ///
  /// Tenue ici et non dans People, et c'est ce qui répond au retour : ouverte
  /// depuis une note, elle est une page *poussée par-dessus cette note*, et le
  /// geste de retour doit ramener là. Sans historique, il ramenait sur la liste
  /// des gens — un endroit d'où l'on ne venait pas. Signalé.
  const [personneOuverte, setPersonneOuverte] = useState<string | null>(
    () => new URLSearchParams(location.search).get("personne"),
  )

  useEffect(() => {
    const onPop = () => {
      const params = new URLSearchParams(location.search)
      setOuverte(params.get("activite"))
      setPersonneOuverte(params.get("personne"))
      // L'entrée sur laquelle on retombe porte l'écran qu'on regardait en
      // partant — posé par `retenirLEcran` juste avant la poussée. Le lire
      // ici est ce qui ramène à la note plutôt qu'à l'onglet par défaut.
      if (retourProvoque.current) {
        retourProvoque.current = false
        return
      }
      const ecran = history.state as
        | { section?: Section; vueJournal?: VueJournal; note?: string | null }
        | null
      if (ecran?.section) setSection(ecran.section)
      if (ecran?.vueJournal) setVueJournal(ecran.vueJournal)
      if (ecran?.note !== undefined) setNoteAOuvrir(ecran.note)
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

  /// Amorcés sur l'adresse quand elle porte une personne : une application
  /// installée se recharge, et retomber sur l'onglet des activités avec une
  /// fiche dans l'adresse aurait montré la mauvaise chose.
  const surUnePersonne = new URLSearchParams(location.search).has("personne")
  const [section, setSection] = useState<Section>(
    surUnePersonne ? "journal" : "activites",
  )
  /// L'onglet Journal montre deux choses : les journées, et les gens qui y
  /// sont cités. Un sixième onglet ne tenait pas dans la capsule — c'est déjà
  /// pour ça qu'« Entraînement » s'y appelle « Plan » — et People est de toute
  /// façon une façon de lire le journal, pas un ailleurs.
  const [vueJournal, setVueJournal] = useState<VueJournal>(
    surUnePersonne ? "gens" : "journees",
  )

  // Le jour d'arrivée dans les repas, quand on y va depuis une citation du
  // journal. Effacé dès qu'on choisit un onglet à la main : sans quoi revenir
  // sur « Repas » trois jours plus tard rouvrirait la journée d'alors.
  const [jourRepas, setJourRepas] = useState<string | null>(null)
  /// Le jour d'arrivée dans le plan, et la note du journal à ouvrir — mêmes
  /// raisons que `jourRepas`, mêmes effacements à main levée.
  const [jourPlan, setJourPlan] = useState<string | null>(null)
  const [noteAOuvrir, setNoteAOuvrir] = useState<string | null>(null)
  /// Vrai le temps d'un retour qu'on a soi-même déclenché pour fermer une
  /// fiche. L'entrée retrouvée porte l'écran d'où l'on venait, et le restaurer
  /// annulerait l'onglet qu'on vient de choisir — on a demandé à partir, pas à
  /// revenir.
  const retourProvoque = useRef(false)

  const changerDeSection = (s: Section) => {
    setJourRepas(null)
    setJourPlan(null)
    setNoteAOuvrir(null)
    // Une fiche est une page poussée : partir vers un onglet la referme, comme
    // le chevron le ferait. Sans ça, la barre étant désormais visible depuis
    // une fiche, on changeait d'onglet sans rien voir changer — la fiche
    // restant devant.
    if (ouverte !== null || personneOuverte !== null) {
      retourProvoque.current = true
      history.back()
    }
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

  /// Marque l'entrée courante de l'historique avec l'écran qu'on regarde.
  ///
  /// À faire **avant** de pousser : c'est cette entrée-ci que le retour
  /// retrouvera, et sans cela il n'y aurait rien dedans pour dire où l'on
  /// était — le navigateur ne retient que l'adresse, et l'adresse ne dit pas
  /// quel onglet regardait celui qui l'a quittée.
  function retenirLEcran() {
    history.replaceState(
      { section, vueJournal, note: noteAOuvrir },
      "",
      location.search,
    )
  }

  /// Un clic sur une personne citée, dans n'importe quelle note : sa fiche.
  ///
  /// Poussée dans l'historique, comme une fiche d'activité : le geste de retour
  /// est le premier réflexe sur un téléphone, et il doit ramener à la note d'où
  /// l'on vient — pas à la liste des gens, où l'on n'est jamais passé.
  function ouvrirLaPersonne(cle: string) {
    retenirLEcran()
    history.pushState(null, "", `?personne=${encodeURIComponent(cle)}`)
    setPersonneOuverte(cle)
    // La fiche d'activité passe derrière : c'est une page poussée elle aussi,
    // et elle resterait devant. Le retour la remet, puisqu'elle est dans
    // l'adresse de l'entrée précédente.
    setOuverte(null)
    setVueJournal("gens")
    setSection("journal")
  }

  /// Va là d'où vient une citation de People.
  ///
  /// Les cinq sources, et pas seulement les sorties : une carte qui ne mène
  /// quelque part qu'une fois sur deux se lit comme une carte cassée.
  function allerALaSource(citation: Citation) {
    switch (citation.source.sorte) {
      case "sortie":
        if (citation.source.activite) ouvrir(citation.source.activite)
        return
      case "repas":
      case "pesee":
        // La journée des repas porte les deux : c'est là que se modifient une
        // note de créneau comme le commentaire d'une pesée.
        setJourRepas(citation.dateKey)
        setSection("nutrition")
        return
      case "seance":
        setJourPlan(citation.dateKey)
        setSection("plan")
        return
      case "journal":
        setVueJournal("journees")
        setNoteAOuvrir(citation.dateKey)
        setSection("journal")
        return
    }
  }

  if (!ready) return null
  if (!session) return <SignIn />

  /// Une fiche de personne en est une aussi : elle recouvre l'écran, elle se
  /// referme par le retour, et elle a son propre repère de défilement — sans
  /// quoi on arrivait là où la liste du journal en était restée, au milieu.
  const surUneFiche = ouverte !== null || personneOuverte !== null

  return (
    <SurUneMention.Provider value={ouvrirLaPersonne}>
    <Chrome
      section={section}
      onSection={changerDeSection}
      masquerOnglets={surUneFiche}
      titre={personneOuverte ? `@${personneOuverte}` : undefined}
      identite={personneOuverte ?? ouverte ?? undefined}
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
      {/* `ouverte` et non `surUneFiche` : une fiche de personne est une fiche
          aux yeux du châssis — onglets masqués, retour, repère de défilement —
          mais c'est People qui la rend, pas la fiche d'une sortie. */}
      {ouverte !== null ? (
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
        <Entrainement key={jourPlan ?? "aujourd'hui"} jourInitial={jourPlan ?? undefined} onOuvrir={ouvrir} />
      ) : section === "journal" ? (
        vueJournal === "gens" ? (
          <People
            onSource={allerALaSource}
            ouverte={personneOuverte}
            onOuvrir={(cle) => {
              // Depuis la liste : une page poussée aussi, pour que le retour
              // ramène à la liste. C'est le même geste, il mérite la même
              // mécanique.
              retenirLEcran()
              history.pushState(null, "", `?personne=${encodeURIComponent(cle)}`)
              setPersonneOuverte(cle)
            }}
            // « ‹ Tous » mène à la liste, puisque c'est ce qu'il annonce — le
            // chevron du châssis, lui, ramène d'où l'on vient. Deux gestes,
            // deux promesses tenues : depuis une note, ils ne mènent pas au
            // même endroit, et c'est exactement ce qu'on veut dire.
            //
            // L'entrée est remplacée plutôt qu'empilée : la liste n'est pas une
            // page de plus par-dessus la fiche, c'est celle qu'on regarde à sa
            // place.
            onFermer={() => {
              history.replaceState({ section, vueJournal }, "", location.pathname)
              setPersonneOuverte(null)
            }}
          />
        ) : (
        <Journal
          noteAOuvrir={noteAOuvrir}
          onNoteOuverte={() => setNoteAOuvrir(null)}
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
    </SurUneMention.Provider>
  )
}
