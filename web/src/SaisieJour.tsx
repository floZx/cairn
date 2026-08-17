import { useState } from "react"
import { useMutation, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"

/// Ce qui s'écrit sur une journée sans être un aliment : le mot qu'on met sur
/// un repas, et le chiffre du matin.
///
/// Les deux vivent dans le même fichier parce qu'ils partagent tout : une
/// ligne par jour (par créneau pour l'un), reprise si elle existe et créée
/// sinon, vidée pour la supprimer. Deux fichiers auraient dupliqué cette
/// mécanique pour deux champs de texte.

async function identifiant(): Promise<string> {
  const { data } = await supabase.auth.getUser()
  const id = data.user?.id
  if (!id) throw new Error("Session expirée, reconnecte-toi.")
  return id
}

/// Une note de repas — celle qui apparaît aussi dans le journal du jour.
///
/// Une par couple (jour, créneau) : l'`uuid` existant est repris quand il y en
/// a un, sinon une seconde ligne se glisserait sous la première et le Mac en
/// afficherait deux pour le même déjeuner.
export function NoteRepas({
  dateKey,
  slotUUID,
  slotNom,
  noteUUID,
  texte,
  onFerme,
}: {
  dateKey: string
  slotUUID: string
  slotNom: string
  noteUUID: string | null
  texte: string
  onFerme: () => void
}) {
  const [valeur, setValeur] = useState(texte)
  const client = useQueryClient()

  const enregistrement = useMutation({
    mutationFn: async () => {
      const maintenant = new Date().toISOString()
      const vide = valeur.trim().length === 0
      const { error } = await supabase.from("meal_note").upsert({
        uuid: noteUUID ?? crypto.randomUUID(),
        user_id: await identifiant(),
        date_key_raw: dateKey,
        meal_slot_uuid: slotUUID,
        note: valeur,
        edited_at: maintenant,
        // Vider une note la supprime : une note blanche ferait paraître la
        // journée dans le journal sans avoir rien à y dire.
        deleted_at: vide ? maintenant : null,
      })
      if (error) throw error
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["nutrition-jour", dateKey] })
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
        <span className="jour">{slotNom}</span>
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
        className="saisie-note courte"
        value={valeur}
        onChange={(e) => setValeur(e.target.value)}
        placeholder={`Ce qu'il y a à dire du ${slotNom.toLowerCase()}…`}
        autoFocus
      />
    </>
  )
}

/// La pesée du jour : un chiffre, et un mot facultatif.
///
/// Le commentaire compte autant que le chiffre — c'est lui que le journal
/// reprend, le poids seul n'ayant rien à raconter.
export function Pesee({
  dateKey,
  peseeUUID,
  kilos,
  commentaire,
  onFerme,
}: {
  dateKey: string
  peseeUUID: string | null
  kilos: number | null
  commentaire: string
  onFerme: () => void
}) {
  const [poids, setPoids] = useState(kilos !== null ? String(kilos) : "")
  const [mot, setMot] = useState(commentaire)
  const [confirmeSuppression, setConfirmeSuppression] = useState(false)
  const client = useQueryClient()

  const rafraichir = () => {
    client.invalidateQueries({ queryKey: ["nutrition-jour", dateKey] })
    client.invalidateQueries({ queryKey: ["journal-journees"] })
    onFerme()
  }

  const enregistrement = useMutation({
    mutationFn: async () => {
      const valeur = Number(poids.replace(",", "."))
      if (!Number.isFinite(valeur) || valeur <= 0) throw new Error("Poids invalide.")
      const maintenant = new Date().toISOString()
      const { error } = await supabase.from("weight_entry").upsert({
        uuid: peseeUUID ?? crypto.randomUUID(),
        user_id: await identifiant(),
        date_key_raw: dateKey,
        weight_kg: valeur,
        note: mot.trim() || null,
        edited_at: maintenant,
        deleted_at: null,
      })
      if (error) throw error
    },
    onSuccess: rafraichir,
  })

  const suppression = useMutation({
    mutationFn: async () => {
      if (!peseeUUID) return
      const maintenant = new Date().toISOString()
      const { error } = await supabase
        .from("weight_entry")
        .update({ deleted_at: maintenant, edited_at: maintenant })
        .eq("uuid", peseeUUID)
      if (error) throw error
    },
    onSuccess: rafraichir,
  })

  const occupe = enregistrement.isPending || suppression.isPending
  const erreur = enregistrement.error ?? suppression.error

  return (
    <>
      <div className="barre-editeur">
        <button className="lien" onClick={onFerme} disabled={occupe}>
          Annuler
        </button>
        <span className="jour">Pesée</span>
        <button
          className="lien fort"
          onClick={() => enregistrement.mutate()}
          disabled={occupe || !poids.trim()}
        >
          {enregistrement.isPending ? "…" : "Enregistrer"}
        </button>
      </div>
      {erreur && <p className="erreur">{(erreur as Error).message}</p>}

      <label className="champ-quantite">
        <input
          type="number"
          inputMode="decimal"
          step="0.1"
          value={poids}
          onChange={(e) => setPoids(e.target.value)}
          placeholder="—"
          autoFocus
        />
        <span>kg</span>
      </label>
      <textarea
        className="saisie-note courte"
        value={mot}
        onChange={(e) => setMot(e.target.value)}
        placeholder="Un mot sur la forme du jour…"
      />

      {peseeUUID && (
        <div className="zone-suppression">
          {confirmeSuppression ? (
            <>
              <span className="attenue petit">Retirer cette pesée ?</span>
              <button
                className="lien danger"
                onClick={() => suppression.mutate()}
                disabled={occupe}
              >
                Oui, retirer
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
              Retirer la pesée
            </button>
          )}
        </div>
      )}
    </>
  )
}

/// Le type de journée, et donc son objectif calorique.
///
/// Le réglage le plus conséquent de la journée : il fixe la cible dont les
/// quatre jauges se déduisent. Listé avec ses calories, parce que c'est le
/// chiffre qui rend le choix parlant — « Qualité » ne dit rien, « Qualité,
/// 2400 kcal » dit tout.
export function TypeDeJournee({
  dateKey,
  jourUUID,
  typeChoisi,
  types,
  onFerme,
}: {
  dateKey: string
  /// L'identité de la ligne du jour, quand elle existe déjà.
  jourUUID: string | null
  typeChoisi: string | null
  types: { uuid: string; name: string; kcal_target: number }[]
  onFerme: () => void
}) {
  const client = useQueryClient()

  const choisir = useMutation({
    mutationFn: async (uuid: string | null) => {
      const maintenant = new Date().toISOString()
      const { error } = await supabase.from("nutrition_day").upsert({
        // Une ligne par jour, reprise si elle existe : deux lignes pour le
        // même jour donneraient deux objectifs, et le Mac en afficherait un
        // au hasard.
        uuid: jourUUID ?? crypto.randomUUID(),
        user_id: await identifiant(),
        date_key_raw: dateKey,
        day_type_uuid: uuid,
        edited_at: maintenant,
        deleted_at: null,
      })
      if (error) throw error
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["nutrition-jour", dateKey] })
      onFerme()
    },
  })

  return (
    <>
      <div className="barre-editeur">
        <button className="lien" onClick={onFerme} disabled={choisir.isPending}>
          Annuler
        </button>
        <span className="jour">Type de journée</span>
        <span />
      </div>
      {choisir.error && <p className="erreur">{(choisir.error as Error).message}</p>}

      <ul className="liste-actions">
        {types.map((t) => (
          <li key={t.uuid}>
            <button
              className={t.uuid === typeChoisi ? "option-jour active" : "option-jour"}
              onClick={() => choisir.mutate(t.uuid)}
              disabled={choisir.isPending}
            >
              <span>{t.name}</span>
              <span className="attenue">{t.kcal_target} kcal</span>
            </button>
          </li>
        ))}
        <li>
          {/* Aucun type est un choix, pas une absence : une journée sans
              objectif se lit alors comme telle plutôt que comme un oubli. */}
          <button
            className={typeChoisi === null ? "option-jour active" : "option-jour"}
            onClick={() => choisir.mutate(null)}
            disabled={choisir.isPending}
          >
            <span>Aucun</span>
            <span className="attenue">sans objectif</span>
          </button>
        </li>
      </ul>
    </>
  )
}
