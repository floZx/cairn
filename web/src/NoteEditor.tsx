import { useEffect, useRef, useState } from "react"
import { useMutation, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { etiquettesDe } from "./tags"
import { dateLongue } from "./format"

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
      client.invalidateQueries({ queryKey: ["journal"] })
      onFerme()
    },
  })

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
      <textarea
        ref={zone}
        className="saisie-note"
        value={texte}
        onChange={(e) => setTexte(e.target.value)}
        placeholder="Ce qu'il y a à dire d'aujourd'hui…"
      />
    </div>
  )
}
