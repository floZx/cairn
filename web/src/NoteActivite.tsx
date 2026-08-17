import { useState } from "react"
import { useMutation, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"

/// La description d'une sortie, écrite depuis le téléphone.
///
/// C'est la seule colonne d'`activity` que le navigateur touche, et la seule
/// que le Mac relit — tout le reste vient de Strava. Une phrase se tape après
/// coup, souvent le soir, et rarement devant un ordinateur.
export function NoteActivite({
  uuid,
  texte,
  champsEdites,
  onFerme,
}: {
  uuid: string
  texte: string
  /// Ce que le Mac protège déjà d'une réécriture par Strava.
  champsEdites: string[]
  onFerme: () => void
}) {
  const [valeur, setValeur] = useState(texte)
  const client = useQueryClient()

  const enregistrement = useMutation({
    mutationFn: async () => {
      const maintenant = new Date().toISOString()
      // `notes` ajouté aux champs protégés, et c'est indispensable :
      // `ImportMapper` sur le Mac ne réécrit `activityDescription` que si ce
      // drapeau manque. Sans lui, la phrase écrite ici serait reprise par
      // Strava à la synchronisation suivante — silencieusement.
      const champs = [...new Set([...champsEdites, "notes"])]
      const { error } = await supabase
        .from("activity")
        .update({
          activity_description: valeur.trim() ? valeur : null,
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
        <span className="jour">Note de sortie</span>
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
      <textarea
        className="saisie-note"
        value={valeur}
        onChange={(e) => setValeur(e.target.value)}
        placeholder="Comment ça s'est passé…"
        autoFocus
      />
    </>
  )
}
