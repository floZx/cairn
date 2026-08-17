import { useState } from "react"
import { useMutation, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { macrosDe } from "./macros"

export type AlimentAModifier = {
  uuid: string
  nom: string
  grammes: number
  kcal100: number
  protein100: number
  carbs100: number
  fat100: number
}

/// Modifier ou retirer une ligne déjà consignée.
///
/// Le nom et la quantité, comme `EditEntrySheet` sur le Mac — les valeurs pour
/// 100 g ne sont pas modifiables ici non plus : elles ont été recopiées depuis
/// le catalogue au moment de la saisie, exprès, pour que l'historique reste
/// vrai même si la fiche du produit change. Les retoucher à la main ferait
/// mentir une journée passée.
///
/// La suppression est douce — `deleted_at`, jamais un DELETE. C'est ce que le
/// Mac lit pour savoir qu'une ligne a disparu ; effacée pour de bon, elle
/// reviendrait au prochain envoi depuis le Mac, qui l'a toujours.
export function ModifAliment({
  aliment,
  dateKey,
  onFerme,
}: {
  aliment: AlimentAModifier
  dateKey: string
  onFerme: () => void
}) {
  const [nom, setNom] = useState(aliment.nom)
  const [grammes, setGrammes] = useState(String(Math.round(aliment.grammes)))
  const [confirmeSuppression, setConfirmeSuppression] = useState(false)
  const client = useQueryClient()

  const rafraichir = () => {
    client.invalidateQueries({ queryKey: ["nutrition-jour", dateKey] })
    client.invalidateQueries({ queryKey: ["garde-manger"] })
    onFerme()
  }

  const enregistrement = useMutation({
    mutationFn: async () => {
      const poids = Number(grammes.replace(",", "."))
      if (!Number.isFinite(poids) || poids <= 0) throw new Error("Quantité invalide.")
      if (!nom.trim()) throw new Error("Un aliment a besoin d'un nom.")
      const { error } = await supabase
        .from("food_entry")
        .update({
          food_name: nom.trim(),
          grams: poids,
          edited_at: new Date().toISOString(),
        })
        .eq("uuid", aliment.uuid)
      if (error) throw error
    },
    onSuccess: rafraichir,
  })

  const suppression = useMutation({
    mutationFn: async () => {
      const maintenant = new Date().toISOString()
      const { error } = await supabase
        .from("food_entry")
        .update({ deleted_at: maintenant, edited_at: maintenant })
        .eq("uuid", aliment.uuid)
      if (error) throw error
    },
    onSuccess: rafraichir,
  })

  const occupe = enregistrement.isPending || suppression.isPending
  const apercu = macrosDe({
    ...aliment,
    grams: Number(grammes.replace(",", ".")) || 0,
  })
  const erreur = enregistrement.error ?? suppression.error

  return (
    <div className="feuille">
      <div className="barre-editeur">
        <button className="lien" onClick={onFerme} disabled={occupe}>
          Annuler
        </button>
        <span className="jour">Modifier</span>
        <button
          className="lien fort"
          onClick={() => enregistrement.mutate()}
          disabled={occupe}
        >
          {enregistrement.isPending ? "…" : "Enregistrer"}
        </button>
      </div>
      {erreur && <p className="erreur">{(erreur as Error).message}</p>}

      <input
        className="recherche"
        value={nom}
        onChange={(e) => setNom(e.target.value)}
        aria-label="Nom de l'aliment"
      />
      <label className="champ-quantite">
        <input
          type="number"
          inputMode="decimal"
          value={grammes}
          min={1}
          onChange={(e) => setGrammes(e.target.value)}
        />
        <span>g</span>
      </label>
      <p className="macros">
        {Math.round(apercu.kcal)} kcal · {Math.round(apercu.proteines)} P ·{" "}
        {Math.round(apercu.glucides)} G · {Math.round(apercu.lipides)} L
      </p>

      {/* En deux temps : le bouton est à portée de pouce, juste sous un champ
          qu'on vient de toucher, et une suppression partie par mégarde
          n'existe nulle part ailleurs pour être rattrapée. */}
      <div className="zone-suppression">
        {confirmeSuppression ? (
          <>
            <span className="attenue petit">Retirer cette ligne ?</span>
            <button
              className="lien danger"
              onClick={() => suppression.mutate()}
              disabled={occupe}
            >
              {suppression.isPending ? "…" : "Oui, retirer"}
            </button>
            <button
              className="lien"
              onClick={() => setConfirmeSuppression(false)}
              disabled={occupe}
            >
              Non
            </button>
          </>
        ) : (
          <button
            className="lien danger"
            onClick={() => setConfirmeSuppression(true)}
            disabled={occupe}
          >
            Retirer du repas
          </button>
        )}
      </div>
    </div>
  )
}
