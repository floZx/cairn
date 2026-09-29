import { useMemo, useState, useRef} from "react"
import { ouvrir as dechiffrer, useChiffre } from "./chiffre"
import { ZoneNote, type ChampNote } from "./ZoneNote"
import { Chargement, Feuille } from "./Chrome"
import { BarreCitations } from "./BarreCitations"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { Markdown } from "./markdown"
import { index, lignes, type Citation, type Personne, type Source } from "./citations"
import { useImagesDuJournal } from "./Journal"

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
  const chiffre = useChiffre()
  return useQuery({
    queryKey: ["people-textes", chiffre],
    staleTime: 60 * 1000,
    queryFn: async () => {
      const [notes, sorties, repas, pesees, creneaux] = await Promise.all([
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
        supabase.from("meal_slot").select("uuid, name").is("deleted_at", null),
      ])

      const nomDuCreneau = new Map(
        ((creneaux.data ?? []) as { uuid: string; name: string }[]).map((c) => [
          c.uuid,
          c.name,
        ]),
      )
      const textes: { dateKey: string; source: Source; contenu: string }[] = []

      for (const n of (notes.data ?? []) as { date_key_raw: string; text: string }[]) {
        // Chiffrée sans la clé : la note ne cite personne qu'on puisse lire.
        const contenu = await dechiffrer(n.text)
        if (contenu === null) continue
        textes.push({ dateKey: n.date_key_raw, source: { sorte: "journal", libelle: "Journal" }, contenu })
      }
      for (const a of (sorties.data ?? []) as {
        uuid: string
        name: string
        start_local_date: string
        activity_description: string
      }[]) {
        textes.push({
          dateKey: a.start_local_date.slice(0, 10),
          source: { sorte: "sortie", libelle: a.name, activite: a.uuid },
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
          source: {
            sorte: "repas",
            libelle: (m.meal_slot_uuid && nomDuCreneau.get(m.meal_slot_uuid)) || "Repas",
          },
          contenu: m.note,
        })
      }
      for (const p of (pesees.data ?? []) as { date_key_raw: string; note: string }[]) {
        textes.push({ dateKey: p.date_key_raw, source: { sorte: "pesee", libelle: "Pesée" }, contenu: p.note })
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

export function People({
  onSource,
  ouverte,
  onOuvrir,
  onFermer,
}: {
  onSource: (citation: Citation) => void
  /// La fiche ouverte, tenue par l'App : c'est une page poussée dans
  /// l'historique, et le geste de retour doit la refermer — depuis la liste
  /// comme depuis une note. Voir `App.ouvrirLaPersonne`.
  ouverte: string | null
  onOuvrir: (cle: string) => void
  onFermer: () => void
}) {
  const textes = useTextes()
  const fiches = useFiches()
  // Les mêmes URL signées que le journal : une citation venue d'une note
  // illustrée affichait sinon le chemin du fichier en toutes lettres.
  const images = useImagesDuJournal()

  const table = useMemo(() => index(textes.data ?? []), [textes.data])
  const liste = useMemo(
    () => lignes(table, (fiches.data ?? []).map((f) => ({ key: f.key, name: f.name }))),
    [table, fiches.data],
  )

  if (textes.isPending) return <Chargement />
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
        onFermer={onFermer}
        onSource={onSource}
        urlImage={(chemin) => images.data?.get(chemin.replace(/^.*\//, ""))}
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

  const notes = new Map((fiches.data ?? []).map((f) => [f.key, f.note]))
  return (
    <div className="liste-gens">
      {liste.map((ligne) => {
        const resume = apercu(notes.get(ligne.personne.cle))
        return (
          <button
            key={ligne.personne.cle}
            className="ligne-personne"
            onClick={() => onOuvrir(ligne.personne.cle)}
          >
            <Monogramme nom={ligne.personne.nom} />
            <span className="identite">
              <span className="pseudo">{ligne.personne.nom}</span>
              {/* La première ligne de ce qu'on a écrit sur elle, là où il n'y
                  avait qu'un point pour dire qu'il y avait quelque chose. */}
              {resume && <span className="resume">{resume}</span>}
            </span>
            {ligne.compte > 0 && <span className="compte">{ligne.compte}</span>}
          </button>
        )
      })}
    </div>
  )
}

/// L'initiale d'une personne dans un rond teinté — ce que la photo est à un
/// contact, pour quelqu'un qui n'en a pas. Le même que sur le Mac.
function Monogramme({ nom, grand = false }: { nom: string; grand?: boolean }) {
  return (
    <span className={grand ? "monogramme grand" : "monogramme"} aria-hidden>
      {nom.slice(0, 1).toUpperCase()}
    </span>
  )
}

/// La première ligne non vide d'une note, sans sa syntaxe de titre ni ses
/// arobases.
function apercu(note: string | undefined): string | null {
  const ligne = (note ?? "")
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l.length > 0)
  if (!ligne) return null
  const sansTitre = ligne.replace(/^#+\s*/, "")
  return sansTitre.replace(/(^|[\s([{«"'\-–—*>])@(?=[\p{L}\p{N}_])/gu, "$1") || null
}

const jourAbrege = new Intl.DateTimeFormat("fr-FR", { weekday: "short", timeZone: "UTC" })
const moisEtAnnee = new Intl.DateTimeFormat("fr-FR", {
  month: "long",
  year: "numeric",
  timeZone: "UTC",
})

/// « SAM » sur « 19 » : la tuile du journal, dimanche en rouge, aujourd'hui en
/// couleur d'accent.
function TuileDuJour({ dateKey }: { dateKey: string }) {
  const date = new Date(`${dateKey}T00:00:00Z`)
  const maintenant = new Date()
  const aujourdhui =
    date.getUTCFullYear() === maintenant.getFullYear() &&
    date.getUTCMonth() === maintenant.getMonth() &&
    date.getUTCDate() === maintenant.getDate()
  const classes = ["tuile-jour", "tuile-sortie"]
  if (aujourdhui) classes.push("aujourdhui")
  else if (date.getUTCDay() === 0) classes.push("dimanche")
  return (
    <span className={classes.join(" ")}>
      <span className="abrege">{jourAbrege.format(date).replace(".", "")}</span>
      <span className="numero">{date.getUTCDate()}</span>
    </span>
  )
}

/// « Septembre 2026 », au-dessus de l'extrait.
function mois(dateKey: string): string {
  const texte = moisEtAnnee.format(new Date(`${dateKey}T00:00:00Z`))
  return texte.charAt(0).toUpperCase() + texte.slice(1)
}

/// La page d'une personne : sa note, puis tout ce qui la cite.
///
/// La note se lit rendue et s'écrit dans une feuille, comme celle d'une
/// sortie : un champ toujours ouvert en tête de page se lisait comme un
/// formulaire, et son Markdown restait brut.
function FichePersonne({
  personne: qui,
  citations,
  fiche,
  onFermer,
  onSource,
  urlImage,
}: {
  personne: Personne
  citations: Citation[]
  fiche: Fiche | null
  onFermer: () => void
  onSource: (citation: Citation) => void
  urlImage: (chemin: string) => string | undefined
}) {
  const [enEdition, setEnEdition] = useState(false)
  const note = fiche?.note ?? ""

  return (
    <>
      <div className="barre-editeur">
        <button className="lien" onClick={onFermer}>
          ‹ Tous
        </button>
        <span className="jour" />
        <span />
      </div>

      {/* L'en-tête de sa carte, en grand : le rond, le nom, et combien de
          notes la citent. */}
      <div className="entete-personne">
        <Monogramme nom={qui.nom} grand />
        <div>
          <h2>{qui.nom}</h2>
          {citations.length > 0 && (
            <span className="attenue">
              {citations.length === 1 ? "1 note" : `${citations.length} notes`}
            </span>
          )}
        </div>
      </div>

      {/* Une note vide tient sur une ligne, qu'on touche pour écrire — comme
          celle d'une sortie. */}
      {note.trim() ? (
        <div className="description carte-groupe">
          <div className="tete-description">
            <span className="attenue petit">Note</span>
            <button className="lien petit" onClick={() => setEnEdition(true)}>
              Modifier
            </button>
          </div>
          <Markdown texte={note} imageURL={urlImage} />
        </div>
      ) : (
        <button className="ecrire-note carte-groupe" onClick={() => setEnEdition(true)}>
          Écrire une note
        </button>
      )}

      {citations.length === 0 ? (
        <p className="attenue petit">Aucune note ne la cite pour l'instant.</p>
      ) : (
        <>
          <h3 className="titre-groupe">Notes qui la citent</h3>
          {/* Une liste encartée, comme celle des gens : la tuile du jour, le
              mois et la source, puis le texte entier avec ses photos. Toutes
              ouvrables : les cinq sources ont leur destination. */}
          <div className="liste-citations">
            {citations.map((citation, rang) => (
              <div
                className="ligne-citation"
                key={rang}
                onClick={(e) => {
                  // Une personne citée dans l'extrait mène à sa fiche, pas
                  // à la note.
                  if ((e.target as Element).closest("a, button")) return
                  onSource(citation)
                }}
                title={`Aller à « ${citation.source.libelle} »`}
              >
                <TuileDuJour dateKey={citation.dateKey} />
                <div className="corps-citation">
                  <span className="provenance">
                    {mois(citation.dateKey)} · {citation.source.libelle}
                  </span>
                  <Markdown texte={citation.texte} imageURL={urlImage} />
                </div>
              </div>
            ))}
          </div>
        </>
      )}

      {enEdition && (
        <Feuille titre={qui.nom} onFerme={() => setEnEdition(false)}>
          <NotePersonne personne={qui} fiche={fiche} onFerme={() => setEnEdition(false)} />
        </Feuille>
      )}
    </>
  )
}

/// La note d'une personne en cours d'écriture : la feuille de la note d'une
/// sortie, Annuler et Enregistrer en tête.
function NotePersonne({
  personne: qui,
  fiche,
  onFerme,
}: {
  personne: Personne
  fiche: Fiche | null
  onFerme: () => void
}) {
  const [note, setNote] = useState(fiche?.note ?? "")
  const aire = useRef<ChampNote>(null)
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
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ["people-fiches"] })
      onFerme()
    },
  })

  return (
    <>
      <div className="barre-editeur">
        <button className="lien" onClick={onFerme} disabled={enregistrement.isPending}>
          Annuler
        </button>
        <span className="jour">{qui.nom}</span>
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
      <ZoneNote
        ref={aire}
        className="saisie-note"
        value={note}
        onChange={setNote}
        placeholder="Ce qu'il y a à retenir de cette personne…"
        autoFocus
      />
    </>
  )
}
