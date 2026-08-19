import { useEffect, useRef, useState } from "react"
import { BarreCitations } from "./BarreCitations"
import { useMutation, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { etiquettesDe } from "./tags"
import { dateLongue } from "./format"
import { ajouterPhoto, enAjoutant } from "./photos"

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

export function NoteEditor({
  note,
  onFerme,
}: {
  note: NoteAEditer
  onFerme: () => void
}) {
  const [texte, setTexte] = useState(note.texte)
  const [envoiPhoto, setEnvoiPhoto] = useState(false)
  const [erreurPhoto, setErreurPhoto] = useState<string | null>(null)
  const client = useQueryClient()
  const zone = useRef<HTMLTextAreaElement>(null)

  // Le curseur en fin de texte plutôt qu'au début : on rouvre une note du jour
  // pour y ajouter quelque chose, pas pour la relire depuis le haut.
  useEffect(() => {
    const cible = zone.current
    if (!cible) return
    cible.focus()
    cible.setSelectionRange(cible.value.length, cible.value.length)
  }, [])

  const enregistrement = useMutation({
    mutationFn: async () => {
      const { data: session } = await supabase.auth.getUser()
      const userID = session.user?.id
      if (!userID) throw new Error("Session expirée, reconnecte-toi.")

      const vide = texte.trim().length === 0
      // `edited_at`, l'horloge de celui qui écrit, et non `updated_at`, que le
      // serveur pose lui-même et qui ne sert qu'à savoir ce qui a changé
      // depuis la dernière lecture. C'est celle-là que le Mac comparera pour
      // trancher entre deux versions d'une même note.
      const maintenant = new Date().toISOString()

      const ligne = {
        uuid: note.uuid ?? crypto.randomUUID(),
        user_id: userID,
        date_key_raw: note.dateKey,
        text: texte,
        tags_raw: etiquettesDe(texte),
        note_updated_at: maintenant,
        edited_at: maintenant,
        // Vider une note, c'est la supprimer : le Mac ne garde pas de note
        // blanche non plus, et une ligne vide dans la liste serait un jour
        // qu'on croirait avoir raconté.
        deleted_at: vide ? maintenant : null,
      }

      const { error } = await supabase.from("journal_note").upsert(ligne)
      if (error) throw error
    },
    onSuccess: () => {
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
      onFerme()
    },
  })

  async function joindre(fichiers: FileList | null) {
    if (!fichiers?.length) return
    setErreurPhoto(null)
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
      setErreurPhoto((e as Error).message)
    } finally {
      setEnvoiPhoto(false)
    }
  }

  return (
    <div className="editeur">
      <div className="barre-editeur">
        <button className="lien" onClick={onFerme} disabled={enregistrement.isPending}>
          Annuler
        </button>
        <span className="jour">{dateLongue(note.dateKey)}</span>
        <button
          className="lien fort"
          onClick={() => enregistrement.mutate()}
          disabled={enregistrement.isPending || texte === note.texte}
        >
          {enregistrement.isPending ? "…" : "Enregistrer"}
        </button>
      </div>
      {enregistrement.error && (
        <p className="erreur">{(enregistrement.error as Error).message}</p>
      )}
      {erreurPhoto && <p className="erreur">{erreurPhoto}</p>}
      <BarreCitations aire={zone} texte={texte} onTexte={setTexte} />
      <textarea
        ref={zone}
        className="saisie-note"
        value={texte}
        onChange={(e) => setTexte(e.target.value)}
        placeholder="Ce qu'il y a à dire d'aujourd'hui…"
      />

      {/* Sous la zone de texte plutôt que dans la barre : la barre porte les
          deux issues — annuler, enregistrer — et y glisser une troisième
          action fait hésiter sur laquelle referme la feuille.

          `accept="image/*"` sans `capture` : iOS propose alors l'appareil
          photo **et** la photothèque, là où `capture` forcerait la prise de
          vue et empêcherait de joindre une photo d'hier. */}
      <label className="joindre">
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
        <span>{envoiPhoto ? "Envoi…" : "Ajouter une photo"}</span>
      </label>
    </div>
  )
}
