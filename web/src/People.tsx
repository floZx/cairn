import { useMemo, useState, useRef} from "react"
import { BarreCitations } from "./BarreCitations"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { Markdown } from "./markdown"
import { dateLongue } from "./format"
import { index, lignes, type Citation, type Personne } from "./citations"

/// Les gens cités dans les notes.
///
/// Rien ne s'y ajoute à la main : une personne y entre parce qu'on l'a citée
/// quelque part, et en sort quand plus aucune note ne la nomme — sauf si on a
/// écrit quelque chose sur elle, auquel cas elle reste en bas. C'est la règle
/// du Mac, portée avec le reste : voir `PeopleIndex.lignes`.
///
/// Les textes viennent d'une requête par table plutôt que d'une seule : le
/// miroir n'a pas de vue qui les réunisse, et une jointure faite à la main
/// coûterait plus cher que quatre requêtes que le navigateur lance ensemble.

type Fiche = { uuid: string; key: string; name: string; note: string }

function useTextes() {
  return useQuery({
    queryKey: ["people-textes"],
    staleTime: 60 * 1000,
    queryFn: async () => {
      const [notes, sorties, repas, pesees, seances, creneaux] = await Promise.all([
        supabase
          .from("journal_note")
          .select("date_key_raw, text")
          .is("deleted_at", null),
        supabase
          .from("activity")
          .select("uuid, name, start_local_date, activity_description")
          .is("deleted_at", null)
          .not("activity_description", "is", null),
        supabase
          .from("meal_note")
          .select("date_key_raw, meal_slot_uuid, note")
          .is("deleted_at", null),
        supabase
          .from("weight_entry")
          .select("date_key_raw, note")
          .is("deleted_at", null)
          .not("note", "is", null),
        supabase
          .from("planned_session")
          .select("date_key_raw, title, sport_type_raw, notes")
          .is("deleted_at", null),
        supabase.from("meal_slot").select("uuid, name").is("deleted_at", null),
      ])

      const nomDuCreneau = new Map(
        ((creneaux.data ?? []) as { uuid: string; name: string }[]).map((c) => [
          c.uuid,
          c.name,
        ]),
      )
      const textes: { dateKey: string; source: { libelle: string; activite?: string }; contenu: string }[] = []

      for (const n of (notes.data ?? []) as { date_key_raw: string; text: string }[]) {
        textes.push({ dateKey: n.date_key_raw, source: { libelle: "Journal" }, contenu: n.text })
      }
      for (const a of (sorties.data ?? []) as {
        uuid: string
        name: string
        start_local_date: string
        activity_description: string
      }[]) {
        textes.push({
          dateKey: a.start_local_date.slice(0, 10),
          source: { libelle: a.name, activite: a.uuid },
          contenu: a.activity_description,
        })
      }
      for (const m of (repas.data ?? []) as {
        date_key_raw: string
        meal_slot_uuid: string | null
        note: string
      }[]) {
        textes.push({
          dateKey: m.date_key_raw,
          source: { libelle: (m.meal_slot_uuid && nomDuCreneau.get(m.meal_slot_uuid)) || "Repas" },
          contenu: m.note,
        })
      }
      for (const p of (pesees.data ?? []) as { date_key_raw: string; note: string }[]) {
        textes.push({ dateKey: p.date_key_raw, source: { libelle: "Pesée" }, contenu: p.note })
      }
      for (const s of (seances.data ?? []) as {
        date_key_raw: string
        title: string
        notes: string
      }[]) {
        if (!s.notes) continue
        textes.push({
          dateKey: s.date_key_raw,
          source: { libelle: s.title || "Séance" },
          contenu: s.notes,
        })
      }
      return textes
    },
  })
}

function useFiches() {
  return useQuery({
    queryKey: ["people-fiches"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("person")
        .select("uuid, key, name, note")
        .is("deleted_at", null)
      if (error) throw error
      return data as Fiche[]
    },
  })
}

export function People({ onOuvrir }: { onOuvrir: (uuid: string) => void }) {
  const [ouverte, setOuverte] = useState<string | null>(null)
  const textes = useTextes()
  const fiches = useFiches()

  const table = useMemo(() => index(textes.data ?? []), [textes.data])
  const liste = useMemo(
    () => lignes(table, (fiches.data ?? []).map((f) => ({ key: f.key, name: f.name }))),
    [table, fiches.data],
  )

  if (textes.isPending) return <p className="attenue">Chargement…</p>
  if (textes.error) return <p className="erreur">{(textes.error as Error).message}</p>

  if (ouverte) {
    const entree = table.get(ouverte)
    const qui = entree?.personne ?? liste.find((l) => l.personne.cle === ouverte)?.personne
    if (!qui) return null
    return (
      <FichePersonne
        personne={qui}
        citations={entree?.citations ?? []}
        fiche={(fiches.data ?? []).find((f) => f.key === ouverte) ?? null}
        onFermer={() => setOuverte(null)}
        onOuvrir={onOuvrir}
      />
    )
  }

  if (liste.length === 0) {
    return (
      <p className="attenue">
        Citez quelqu'un dans une note avec « @prénom » et il apparaîtra ici.
      </p>
    )
  }

  return (
    <div className="liste-gens">
      {liste.map((ligne) => (
        <button
          key={ligne.personne.cle}
          className="ligne-personne"
          onClick={() => setOuverte(ligne.personne.cle)}
        >
          <span className="pseudo">@{ligne.personne.nom}</span>
          {ligne.aUneNote && <span className="marque-note">·</span>}
          <span className="attenue petit compte">
            {ligne.compte > 0 ? `${ligne.compte}` : "—"}
          </span>
        </button>
      ))}
    </div>
  )
}

/// La page d'une personne : sa note, puis tout ce qui la cite.
function FichePersonne({
  personne: qui,
  citations,
  fiche,
  onFermer,
  onOuvrir,
}: {
  personne: Personne
  citations: Citation[]
  fiche: Fiche | null
  onFermer: () => void
  onOuvrir: (uuid: string) => void
}) {
  const [note, setNote] = useState(fiche?.note ?? "")
  const aire = useRef<HTMLTextAreaElement>(null)
  const client = useQueryClient()

  const enregistrement = useMutation({
    mutationFn: async () => {
      const { data } = await supabase.auth.getUser()
      const userID = data.user?.id
      if (!userID) throw new Error("Session expirée, reconnecte-toi.")
      const maintenant = new Date().toISOString()
      const vide = note.trim().length === 0
      const { error } = await supabase.from("person").upsert({
        uuid: fiche?.uuid ?? crypto.randomUUID(),
        user_id: userID,
        key: qui.cle,
        name: qui.nom,
        note,
        edited_at: maintenant,
        // Vider la note supprime la fiche : une fiche vide laissée derrière
        // ferait rester quelqu'un dans la liste alors que plus rien ne le cite
        // ni ne le décrit. C'est la règle du Mac.
        deleted_at: vide ? maintenant : null,
      })
      if (error) throw error
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["people-fiches"] })
    },
  })

  return (
    <>
      <div className="barre-editeur">
        <button className="lien" onClick={onFermer}>
          ‹ Tous
        </button>
        <span className="jour">@{qui.nom}</span>
        <button
          className="lien fort"
          onClick={() => enregistrement.mutate()}
          disabled={enregistrement.isPending || note === (fiche?.note ?? "")}
        >
          {enregistrement.isPending ? "…" : "Enregistrer"}
        </button>
      </div>
      {enregistrement.error && (
        <p className="erreur">{(enregistrement.error as Error).message}</p>
      )}

      <BarreCitations aire={aire} texte={note} onTexte={setNote} />

      <textarea
        ref={aire}
        className="saisie-note courte"
        value={note}
        onChange={(e) => setNote(e.target.value)}
        placeholder="Ce qu'il y a à retenir de cette personne…"
      />

      {citations.length === 0 ? (
        <p className="attenue petit">Aucune note ne la cite pour l'instant.</p>
      ) : (
        <>
          <h3 className="titre-section">Citée {citations.length} fois</h3>
          {citations.map((citation, rang) => (
            <div
              className={citation.source.activite ? "citation-carte ouvrable" : "citation-carte"}
              key={rang}
              onClick={() =>
                citation.source.activite && onOuvrir(citation.source.activite)
              }
            >
              <span className="attenue petit">
                {dateLongue(citation.dateKey)} · {citation.source.libelle}
              </span>
              <Markdown texte={citation.texte} />
            </div>
          ))}
        </>
      )}
    </>
  )
}
