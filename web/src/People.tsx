import { useMemo, useState, useRef} from "react"
import { ouvrir as dechiffrer, useChiffre } from "./chiffre"
import { ZoneNote, type ChampNote } from "./ZoneNote"
import { Chargement, Feuille } from "./Chrome"
import { BarreCitations } from "./BarreCitations"
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { Markdown } from "./markdown"
import {
  annuaire as annuaireDesFiches,
  index,
  lignes,
  trier,
  type Tri,
  personne,
  type Annuaire,
  type Citation,
  type Personne,
  type Source,
} from "./citations"
import { useImagesDuJournal } from "./Journal"
import { TuileDuJour, mois } from "./TuileDuJour"

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

type Fiche = { uuid: string; key: string; name: string; note: string; aliases: string[] | null }

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
        .select("uuid, key, name, note, aliases")
        .is("deleted_at", null)
      if (error) throw error
      return data as Fiche[]
    },
  })
}

export function People({
  tri,
  onSource,
  ouverte,
  onOuvrir,
  onFermer,
}: {
  tri: Tri
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

  // Chris et Chérie comptent pour Christèle : ils ne figurent pas dans la
  // liste, leurs notes s'ajoutent aux siennes.
  const qui = useMemo(() => annuaireDesFiches(fiches.data ?? []), [fiches.data])
  const table = useMemo(() => index(textes.data ?? [], qui), [textes.data, qui])
  const liste = useMemo(
    () =>
      trier(
        lignes(table, (fiches.data ?? []).map((f) => ({ key: f.key, name: f.name }))),
        tri,
      ),
    [table, fiches.data, tri],
  )

  if (textes.isPending) return <Chargement />
  if (textes.error) return <p className="erreur">{(textes.error as Error).message}</p>

  if (ouverte) {
    // Ouverte par un alias — « Chérie » touché dans une note —, c'est la
    // fiche de Christèle qui s'affiche.
    const cle = qui.parCle.get(ouverte)?.cle ?? ouverte
    const entree = table.get(cle)
    const ouvertePar = entree?.personne ?? liste.find((l) => l.personne.cle === cle)?.personne
    if (!ouvertePar) return null
    return (
      <FichePersonne
        personne={ouvertePar}
        annuaire={qui}
        fiches={fiches.data ?? []}
        citations={entree?.citations ?? []}
        fiche={(fiches.data ?? []).find((f) => f.key === cle) ?? null}
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

/// La page d'une personne : sa note, puis tout ce qui la cite.
///
/// La note se lit rendue et s'écrit dans une feuille, comme celle d'une
/// sortie : un champ toujours ouvert en tête de page se lisait comme un
/// formulaire, et son Markdown restait brut.
function FichePersonne({
  personne: qui,
  annuaire,
  fiches,
  citations,
  fiche,
  onFermer,
  onSource,
  urlImage,
}: {
  personne: Personne
  annuaire: Annuaire
  fiches: Fiche[]
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

      <AutresNoms personne={qui} annuaire={annuaire} fiches={fiches} />

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
        aliases: fiche?.aliases ?? [],
        edited_at: maintenant,
        // Vider la note supprime la fiche, sauf si des alias la retiennent :
        // une fiche vide laissée derrière ferait rester quelqu'un dans la
        // liste alors que plus rien ne le décrit. C'est la règle du Mac.
        deleted_at: vide && (fiche?.aliases ?? []).length === 0 ? maintenant : null,
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

/// « Autres noms » : les alias en pastilles, qu'on retire d'un toucher, et un
/// champ pour en ajouter. Ajouter un nom qui avait sa propre fiche la fond
/// dans celle-ci — note et alias compris —, comme sur le Mac : voir
/// `PersonAliases.fusionner`.
function AutresNoms({
  personne: qui,
  annuaire,
  fiches,
}: {
  personne: Personne
  annuaire: Annuaire
  fiches: Fiche[]
}) {
  const [saisie, setSaisie] = useState<string | null>(null)
  const client = useQueryClient()
  const alias = annuaire.alias.get(qui.cle) ?? []

  const ecriture = useMutation({
    mutationFn: async (lignes: Fiche[]) => {
      const { data } = await supabase.auth.getUser()
      const userID = data.user?.id
      if (!userID) throw new Error("Session expirée, reconnecte-toi.")
      const maintenant = new Date().toISOString()
      const { error } = await supabase.from("person").upsert(
        lignes.map((f) => ({
          uuid: f.uuid,
          user_id: userID,
          key: f.key,
          name: f.name,
          note: f.note,
          aliases: f.aliases ?? [],
          edited_at: maintenant,
          // Ni note ni alias : la fiche n'a plus rien à porter.
          deleted_at: !f.note.trim() && (f.aliases ?? []).length === 0 ? maintenant : null,
        })),
      )
      if (error) throw error
    },
    onSuccess: () => {
      client.invalidateQueries({ queryKey: ["people-fiches"] })
      client.invalidateQueries({ queryKey: ["annuaire-citations"] })
    },
  })

  const ajouter = () => {
    const tape = (saisie ?? "").replace(/^@+/, "").trim()
    setSaisie(null)
    const source = personne(tape)
    if (!source || source.cle === qui.cle) return
    ecriture.mutate(fusionner(source, qui, fiches))
  }

  const retirer = (nom: Personne) => {
    const fiche = fiches.find((f) => f.key === qui.cle)
    if (!fiche) return
    ecriture.mutate([
      { ...fiche, aliases: (fiche.aliases ?? []).filter((a) => personne(a)?.cle !== nom.cle) },
    ])
  }

  return (
    <div className="autres-noms">
      <span className="attenue petit">Autres noms</span>
      {alias.map((a) => (
        <span className="pastille-nom" key={a.cle}>
          {a.nom}
          <button
            className="retirer"
            onClick={() => retirer(a)}
            aria-label={`Ne plus compter « ${a.nom} » comme ${qui.nom}`}
          >
            ×
          </button>
        </span>
      ))}
      {saisie !== null ? (
        <input
          className="pastille-nom saisie"
          autoFocus
          value={saisie}
          placeholder="Autre nom"
          onChange={(e) => setSaisie(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") ajouter()
            if (e.key === "Escape") setSaisie(null)
          }}
          onBlur={() => (saisie.trim() ? ajouter() : setSaisie(null))}
        />
      ) : (
        <button className="pastille-nom ajouter" onClick={() => setSaisie("")} aria-label="Ajouter un autre nom">
          +
        </button>
      )}
      {ecriture.error && <p className="erreur">{(ecriture.error as Error).message}</p>}
    </div>
  )
}

/// Ramène `source` à `cible`, dont elle devient un alias. Porté de
/// `PersonAliases.fusionner` : la fiche de la source, si elle existe, se fond
/// dans celle de la cible — alias puis note —, et un nom quitte la fiche qui
/// le portait. Rend les lignes à écrire.
function fusionner(source: Personne, cible: Personne, fiches: Fiche[]): Fiche[] {
  const ecrites: Fiche[] = []
  const existante = fiches.find((f) => f.key === cible.cle)
  const ficheCible: Fiche = existante
    ? { ...existante, aliases: [...(existante.aliases ?? [])] }
    : { uuid: crypto.randomUUID(), key: cible.cle, name: cible.nom, note: "", aliases: [] }
  const alias = ficheCible.aliases ?? []
  const ajoute = (nom: string) => {
    const qui = personne(nom)
    if (!qui || qui.cle === cible.cle || alias.some((a) => personne(a)?.cle === qui.cle)) return
    alias.push(qui.nom)
  }
  ajoute(source.nom)
  for (const autre of fiches) {
    if (autre.key === cible.cle) continue
    if (autre.key === source.cle) {
      for (const a of autre.aliases ?? []) ajoute(a)
      if (autre.note.trim()) {
        ficheCible.note = ficheCible.note.trim() ? `${ficheCible.note}\n\n${autre.note}` : autre.note
      }
      // Ni note ni alias une fois vidée : `deleted_at` part à l'écriture.
      ecrites.push({ ...autre, note: "", aliases: [] })
    } else if ((autre.aliases ?? []).some((a) => personne(a)?.cle === source.cle)) {
      ecrites.push({
        ...autre,
        aliases: (autre.aliases ?? []).filter((a) => personne(a)?.cle !== source.cle),
      })
    }
  }
  ficheCible.aliases = alias
  return [ficheCible, ...ecrites]
}
