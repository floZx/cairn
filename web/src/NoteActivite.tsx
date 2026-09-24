import { useState, useRef} from "react"
import { BarreCitations } from "./BarreCitations"
import { useMutation, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"

/// Les deux notes d'une sortie : la description, et la note privée de Strava.
/// Chacune dit sa colonne et le drapeau qui la protège sur le Mac.
const NOTES = {
  publique: { colonne: "activity_description", champ: "notes", titre: "Note de sortie" },
  privee: { colonne: "private_note", champ: "privateNote", titre: "Note privée" },
} as const

export type SorteDeNote = keyof typeof NOTES

/// Une note de sortie, écrite depuis le téléphone.
///
/// Ce sont les seules colonnes d'`activity` que le navigateur touche, et les
/// seules que le Mac relit — tout le reste vient de Strava. Une phrase se tape
/// après coup, souvent le soir, et rarement devant un ordinateur. Rien ne
/// repart vers Strava, pas plus d'ici que du Mac.
export function NoteActivite({
  uuid,
  sorte = "publique",
  texte,
  champsEdites,
  onFerme,
}: {
  uuid: string
  sorte?: SorteDeNote
  texte: string
  /// Ce que le Mac protège déjà d'une réécriture par Strava.
  champsEdites: string[]
  onFerme: () => void
}) {
  const note = NOTES[sorte]
  const [valeur, setValeur] = useState(texte)
  const aire = useRef<HTMLTextAreaElement>(null)
  const client = useQueryClient()

  const enregistrement = useMutation({
    mutationFn: async () => {
      const maintenant = new Date().toISOString()
      // Le drapeau ajouté aux champs protégés, et c'est indispensable :
      // `ImportMapper` sur le Mac ne réécrit la note que s'il manque. Sans
      // lui, la phrase écrite ici serait reprise par Strava à la
      // synchronisation suivante — silencieusement. Pour la note privée, il
      // est aussi ce qui dit au Mac de la relire d'ici.
      const champs = [...new Set([...champsEdites, note.champ])]
      const { error } = await supabase
        .from("activity")
        .update({
          [note.colonne]: valeur.trim() ? valeur : null,
          edited_fields: champs,
          edited_at: maintenant,
        })
        .eq("uuid", uuid)
      if (error) throw error
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["activite", uuid] })
      // La description paraît aussi dans le journal du jour, cité sous
      // « Sortie ».
      client.invalidateQueries({ queryKey: ["journal-journees"] })
      onFerme()
    },
  })

  return (
    <>
      <div className="barre-editeur">
        <button className="lien" onClick={onFerme} disabled={enregistrement.isPending}>
          Annuler
        </button>
        <span className="jour">{note.titre}</span>
        <button
          className="lien fort"
          onClick={() => enregistrement.mutate()}
          disabled={enregistrement.isPending || valeur === texte}
        >
          {enregistrement.isPending ? "…" : "Enregistrer"}
        </button>
      </div>
      {enregistrement.error && (
        <p className="erreur">{(enregistrement.error as Error).message}</p>
      )}
      <BarreCitations aire={aire} texte={valeur} onTexte={setValeur} />
      <textarea
        ref={aire}
        className="saisie-note"
        value={valeur}
        onChange={(e) => setValeur(e.target.value)}
        placeholder="Comment ça s'est passé…"
        autoFocus
      />
    </>
  )
}
