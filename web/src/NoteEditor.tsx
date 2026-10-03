import { useEffect, useRef, useState } from "react"
import { createPortal } from "react-dom"
import { ZoneNote, type ChampNote } from "./ZoneNote"
import { BarreCitations } from "./BarreCitations"
import { useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { etiquettesDe } from "./tags"
import { estChiffre, sceller } from "./chiffre"
import { dateLongue } from "./format"
import { ajouterPhoto, enAjoutant } from "./photos"
import { Symbole } from "./IconeSport"

export type NoteAEditer = {
  /// nil pour une note qui n'existe pas encore ce jour-là.
  uuid: string | null
  dateKey: string
  texte: string
}

/// La clé du jour d'aujourd'hui, à l'heure locale.
///
/// Assemblée à la main plutôt que par `toISOString`, qui rend de l'UTC : une
/// note écrite à vingt-trois heures à Paris se rangerait au lendemain.
export function jourCourant(): string {
  const maintenant = new Date()
  const deuxChiffres = (n: number) => String(n).padStart(2, "0")
  return [
    maintenant.getFullYear(),
    deuxChiffres(maintenant.getMonth() + 1),
    deuxChiffres(maintenant.getDate()),
  ].join("-")
}

/// Le temps sans frappe au bout duquel la note s'enregistre d'elle-même.
const PAUSE = 1200

/// Écrire une note : une page entière, comme dans Notes.
///
/// Elle a remplacé une feuille, qui sur un téléphone couvrait déjà presque
/// tout l'écran mais se lisait comme une fenêtre posée dessus — poignée, bord
/// du journal en haut, texte enfermé dans un cadre — et demandait de choisir
/// entre « Annuler » et « Enregistrer ». Ici, plus de choix : la note
/// s'enregistre après chaque pause, et en partant.
///
/// On en part par le chevron ou par le geste de retour : la page est poussée
/// dans l'historique, comme une fiche.
///
/// Vider une note, c'est la supprimer — mais en partant seulement. Une pause
/// au milieu d'une réécriture complète effacerait la note du Mac le temps de
/// retaper la première ligne.
export function NoteEditor({
  note,
  onFerme,
}: {
  note: NoteAEditer
  onFerme: () => void
}) {
  const [texte, setTexte] = useState(note.texte)
  const [envoiPhoto, setEnvoiPhoto] = useState(false)
  const [erreur, setErreur] = useState<string | null>(null)
  const [enSaisie, setEnSaisie] = useState(false)
  const [entree, setEntree] = useState(false)
  const client = useQueryClient()
  const zone = useRef<ChampNote>(null)
  const page = useRef<HTMLDivElement>(null)

  /// Ce que la base a déjà : rien à renvoyer tant que le texte n'en diffère pas.
  const enregistre = useRef(note.texte)
  /// Fixé au premier enregistrement d'une note qui n'existait pas : les
  /// suivants doivent viser la même ligne, pas en créer une à chaque pause.
  const uuid = useRef(note.uuid)
  /// Les enregistrements à la file : le chiffrement est asynchrone, et deux
  /// envois croisés pourraient laisser en base le plus ancien des deux.
  const file = useRef<Promise<void>>(Promise.resolve())
  const dernier = useRef(texte)
  dernier.current = texte

  function enregistrer(enPartant: boolean): Promise<void> {
    const suite = file.current.then(async () => {
      const valeur = dernier.current
      if (valeur === enregistre.current) return
      const vide = valeur.trim().length === 0
      if (vide && !enPartant) return
      // Une note qui n'a jamais existé et qu'on laisse vide : rien à écrire.
      if (vide && !uuid.current) return

      const { data: session } = await supabase.auth.getUser()
      const userID = session.user?.id
      if (!userID) throw new Error("Session expirée, reconnecte-toi.")

      // `edited_at`, l'horloge de celui qui écrit, et non `updated_at`, que le
      // serveur pose lui-même et qui ne sert qu'à savoir ce qui a changé
      // depuis la dernière lecture. C'est celle-là que le Mac comparera pour
      // trancher entre deux versions d'une même note.
      const maintenant = new Date().toISOString()
      const scelle = await sceller(valeur)
      uuid.current ??= crypto.randomUUID()

      const { error } = await supabase.from("journal_note").upsert({
        uuid: uuid.current,
        user_id: userID,
        date_key_raw: note.dateKey,
        // Chiffré si le journal l'est, et ses étiquettes alors tues : tirées
        // du texte, elles en diraient une part en clair.
        text: scelle,
        tags_raw: estChiffre(scelle) ? [] : etiquettesDe(valeur),
        note_updated_at: maintenant,
        edited_at: maintenant,
        // Le Mac ne garde pas de note blanche non plus, et une ligne vide dans
        // la liste serait un jour qu'on croirait avoir raconté.
        deleted_at: vide ? maintenant : null,
      })
      if (error) throw error
      enregistre.current = valeur
      setErreur(null)
      // « journal-journees » et non « journal » : l'écran a été réécrit pour
      // assembler ses jours depuis quatre sources, sa clé a changé, et cette
      // invalidation est restée sur l'ancienne. Elle ne visait plus rien, donc
      // la liste gardait la note d'avant jusqu'au prochain chargement.
      //
      // Le préfixe suffit : les créneaux complètent la clé, et les nommer ici
      // ferait dépendre l'éditeur d'un détail de l'écran qui l'affiche.
      client.invalidateQueries({ queryKey: ["journal-journees"] })
      // Les pièces jointes aussi : une photo vient peut-être d'être ajoutée à
      // cette note, et son URL signée est mise en cache pour douze heures.
      client.invalidateQueries({ queryKey: ["pieces-jointes"] })
    })
    // La file continue même après un échec : le suivant réessaiera.
    file.current = suite.catch(() => {})
    return suite
  }

  // Après chaque pause dans la frappe.
  useEffect(() => {
    if (texte === enregistre.current) return
    const t = setTimeout(() => {
      enregistrer(false).catch((e) => setErreur((e as Error).message))
    }, PAUSE)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [texte])

  /// Partir : enregistrer d'abord, et ne refermer qu'une fois la note en base.
  /// Un échec garde la page ouverte, le texte sous les yeux, plutôt que de le
  /// perdre en silence.
  const partir = useRef<() => Promise<void>>(async () => {})
  partir.current = async () => {
    try {
      await enregistrer(true)
      onFerme()
    } catch (e) {
      setErreur((e as Error).message)
      // Le retour a déjà retiré l'entrée de la page : la remettre, pour que le
      // prochain geste de retour repasse par ici.
      history.pushState({ editeur: true }, "", location.search)
    }
  }

  // Poussée dans l'historique : le geste de retour est le premier réflexe sur
  // un téléphone, et il doit ramener au journal, pas quitter l'application.
  //
  // L'entrée de départ perd sa note à rouvrir : `App` la relit au retour, et
  // une note retenue là d'une visite précédente se serait rouverte aussitôt.
  //
  // Une seule fois par page : le mode strict de développement monte l'effet
  // deux fois. Une référence et non l'état de l'historique, qu'un
  // rechargement garde — la marque d'une ancienne page aurait empêché
  // celle-ci de pousser la sienne.
  const poussee = useRef(false)
  useEffect(() => {
    if (!poussee.current) {
      poussee.current = true
      history.replaceState({ ...history.state, note: null }, "", location.search)
      history.pushState({ editeur: true }, "", location.search)
    }
    const surRetour = () => partir.current()
    addEventListener("popstate", surRetour)
    return () => removeEventListener("popstate", surRetour)
  }, [])

  const retour = () => history.back()

  useEffect(() => {
    const surEchap = (e: KeyboardEvent) => e.key === "Escape" && history.back()
    addEventListener("keydown", surEchap)
    return () => removeEventListener("keydown", surEchap)
  }, [])

  // Glissée depuis la droite à l'ouverture, comme une page poussée : posée à
  // sa place au premier rendu, la transition n'aurait rien à animer.
  useEffect(() => {
    const t = requestAnimationFrame(() => setEntree(true))
    return () => cancelAnimationFrame(t)
  }, [])

  // Calée sur la fenêtre **visuelle**, comme le voile des feuilles : iOS pose
  // le clavier par-dessus la mise en page sans la rétrécir, et une page ancrée
  // en bas garderait sa barre d'outils derrière lui. Collée à ce qui reste
  // visible, la barre vient se poser sur le clavier.
  useEffect(() => {
    const vue = window.visualViewport
    if (!vue) return
    const suivre = () => {
      const boite = page.current
      if (!boite) return
      boite.style.top = `${vue.offsetTop}px`
      boite.style.height = `${vue.height}px`
    }
    suivre()
    vue.addEventListener("resize", suivre)
    vue.addEventListener("scroll", suivre)
    return () => {
      vue.removeEventListener("resize", suivre)
      vue.removeEventListener("scroll", suivre)
    }
  }, [])

  // Le curseur en fin de texte plutôt qu'au début : on rouvre une note du jour
  // pour y ajouter quelque chose, pas pour la relire depuis le haut.
  useEffect(() => {
    const cible = zone.current
    if (!cible) return
    cible.focus()
    cible.setSelectionRange(cible.value.length, cible.value.length)
    // Lu plutôt qu'attendu : un focus donné par programme n'émet pas toujours
    // son évènement, et « OK » manquait alors à l'ouverture.
    setEnSaisie(page.current?.contains(document.activeElement) ?? false)
  }, [])

  async function joindre(fichiers: FileList | null) {
    if (!fichiers?.length) return
    setErreur(null)
    setEnvoiPhoto(true)
    try {
      // Une à la fois, dans l'ordre choisi : les numéros du jour se suivent,
      // et deux envois simultanés se disputeraient le même.
      const liens: string[] = []
      for (const fichier of Array.from(fichiers)) {
        liens.push(await ajouterPhoto(fichier, note.dateKey))
      }
      setTexte((avant) => enAjoutant(liens, avant))
    } catch (e) {
      setErreur((e as Error).message)
    } finally {
      setEnvoiPhoto(false)
    }
  }

  // Rendue dans le corps du document, comme une feuille : un ancêtre à
  // `backdrop-filter` enfermerait un `position: fixed` dans sa propre boîte.
  return createPortal(
    <div
      className={["page-note", entree && "entree", enSaisie && "en-saisie"].filter(Boolean).join(" ")}
      ref={page}
      role="dialog"
      aria-label="Note"
      onFocus={() => setEnSaisie(true)}
      onBlur={() => setEnSaisie(false)}
    >
      {/* Le chevron seul dans la bande sous l'heure : iOS 27 y floute tout,
          et c'est la seule chose qu'on y tolère. */}
      <div className="tete-note">
        <button className="retour matiere" onClick={retour} aria-label="Retour au journal">
          <svg
            width="17"
            height="17"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.6"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden
          >
            <path d="M15.25 4.5L7.75 12l7.5 7.5" />
          </svg>
        </button>
      </div>

      <div className="corps-note">
        <p className="date-note">{dateLongue(note.dateKey)}</p>
        {erreur && <p className="erreur">{erreur}</p>}
        <ZoneNote
          ref={zone}
          className="texte-note"
          value={texte}
          onChange={setTexte}
          placeholder="Ce qu'il y a à dire d'aujourd'hui…"
        />
      </div>

      {/* Collée au clavier quand il est levé, au bas de l'écran sinon. Les
          citations y arrivent à la place de la photo : c'est là que le regard
          est quand on tape, et c'est là qu'iOS propose ses propres mots. */}
      <div className="outils-note">
        <div className="propositions-note">
          <BarreCitations aire={zone} texte={texte} onTexte={setTexte} />
        </div>
        {/* `accept="image/*"` sans `capture` : iOS propose alors l'appareil
            photo **et** la photothèque, là où `capture` forcerait la prise de
            vue et empêcherait de joindre une photo d'hier. */}
        <label className={envoiPhoto ? "outil-note envoi" : "outil-note"} aria-label="Ajouter une photo">
          <input
            type="file"
            accept="image/*"
            multiple
            disabled={envoiPhoto}
            onChange={(e) => {
              joindre(e.target.files)
              // Vidé tout de suite : rechoisir la même photo ne relancerait
              // aucun évènement si la valeur ne changeait pas.
              e.target.value = ""
            }}
          />
          <Symbole nom="photo" taille={22} />
        </label>
        {/* Baisser le clavier pour relire : un iPhone n'a pas de touche pour
            ça, et Notes met ce bouton au même endroit. */}
        {enSaisie && (
          <button
            className="outil-note ok"
            // `onMouseDown` : le champ perdrait la main avant le clic, et le
            // bouton disparaîtrait avec elle.
            onMouseDown={(e) => {
              e.preventDefault()
              ;(document.activeElement as HTMLElement | null)?.blur()
            }}
          >
            OK
          </button>
        )}
      </div>
    </div>,
    document.body,
  )
}
