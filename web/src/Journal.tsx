import { useEffect, useRef, useState } from "react"
import { useInfiniteQuery, useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { Markdown } from "./markdown"
import { dateLongue } from "./format"
import { NoteEditor, jourCourant, type NoteAEditer } from "./NoteEditor"
import { Feuille } from "./Chrome"
import { IconeSport } from "./IconeSport"
import { nomDuSport } from "./sports"

/// Une journée du journal, telle que le Mac la compose.
///
/// Un jour paraît dès qu'il porte **quelque chose** : une note, une sortie,
/// une pesée, un mot sur un repas. C'est la règle de `JournalDaySources` du
/// Mac, portée — sans elle, le journal du navigateur ne montrait que les
/// jours dont une note existait déjà, et une journée entière de course
/// n'apparaissait nulle part.
type Journee = {
  dateKey: string
  /// La note du jour : son texte, et son identité si elle existe déjà.
  noteUUID: string | null
  texte: string
  tags: string[]
  /// Ce qui est écrit ailleurs, dans l'ordre où la journée a été vécue : les
  /// sorties d'abord, puis les repas dans l'ordre où on les mange, la pesée
  /// en dernier. L'ordre est celui de `elsewhereNotes`, et il compte : c'est
  /// ce qui fait qu'une journée se lit comme un récit.
  /// `sport` pour une sortie, `kg` pour une pesée : l'attribution se dessine
  /// alors au lieu de se lire. Un mot gris de plus dans une colonne de gris se
  /// perd ; une icône colorée et un poids se repèrent d'un coup d'œil.
  ///
  /// `activite` porte l'identité de la sortie citée, de quoi aller la voir.
  /// Les repas et la pesée n'en ont pas besoin : la date de la journée suffit
  /// à les retrouver, et c'est le même écran pour les deux.
  ailleurs: {
    source: string
    texte: string
    sport?: string
    kg?: number
    activite?: string
  }[]
  /// Les sports du jour, pour la pastille — une journée sans un mot mais avec
  /// une sortie doit tout de même se voir.
  sports: string[]
  pesee: boolean
}

const JOURS_PAR_PAGE = 45

function decale(dateKey: string, jours: number): string {
  const [a, m, j] = dateKey.split("-").map(Number)
  const d = new Date(a, m - 1, j + jours)
  const deux = (n: number) => String(n).padStart(2, "0")
  return `${d.getFullYear()}-${deux(d.getMonth() + 1)}-${deux(d.getDate())}`
}

/// Les créneaux de repas, pour ranger leurs notes dans l'ordre où on mange.
function useCreneaux() {
  return useQuery({
    queryKey: ["creneaux-journal"],
    staleTime: Infinity,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("meal_slot")
        .select("uuid, name, sort_order")
        .is("deleted_at", null)
        .order("sort_order")
      if (error) throw error
      return data as { uuid: string; name: string; sort_order: number }[]
    },
  })
}

/// Les images des notes, résolues en une fois plutôt qu'une par une.
///
/// Le Markdown pointe sur `pieces-jointes/2026-08-12-1.jpg` : un chemin
/// relatif qui avait un sens dans un dossier et n'en a plus ici. Le seau est
/// privé, il faut donc une URL signée — toutes d'un coup, et pour
/// vingt-quatre heures.
function useImagesDuJournal() {
  return useQuery({
    queryKey: ["pieces-jointes"],
    staleTime: 12 * 3600 * 1000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("journal_attachment")
        .select("file_name, storage_path")
        .is("deleted_at", null)
      if (error) throw error
      const rows = data as { file_name: string; storage_path: string }[]
      if (rows.length === 0) return new Map<string, string>()

      const { data: urls, error: erreurURL } = await supabase.storage
        .from("photos")
        .createSignedUrls(
          rows.map((r) => r.storage_path),
          24 * 3600,
        )
      if (erreurURL) throw erreurURL
      const parChemin = new Map(urls.map((u) => [u.path ?? "", u.signedUrl]))
      return new Map(
        rows.flatMap((r) => {
          const url = parChemin.get(r.storage_path)
          return url ? [[r.file_name, url] as [string, string]] : []
        }),
      )
    },
  })
}

/// Une fenêtre de jours, assemblée depuis les quatre sources.
///
/// Paginée par tranches de dates plutôt que par lignes : les sources n'ont
/// pas le même nombre de lignes par jour, et un « cinquante lignes de plus »
/// donnerait cinquante jours de notes ou deux jours de repas selon la table
/// interrogée.
function useJournees(creneaux: { uuid: string; name: string; sort_order: number }[]) {
  return useInfiniteQuery({
    // Les créneaux entrent dans la clé, et ce n'est pas décoratif : ils
    // donnent leur nom aux notes de repas et l'ordre dans lequel elles se
    // lisent. Sans eux dans la clé, la première fournée partait avant leur
    // arrivée, chaque note de repas s'affichait « Repas » et rien ne relançait
    // la requête.
    queryKey: ["journal-journees", creneaux.map((c) => c.uuid).join(",")],
    enabled: creneaux.length > 0,
    initialPageParam: jourCourant(),
    queryFn: async ({ pageParam }) => {
      const fin = pageParam as string
      const debut = decale(fin, -JOURS_PAR_PAGE)

      const [notes, activites, poids, repas] = await Promise.all([
        supabase
          .from("journal_note")
          .select("uuid, date_key_raw, text, tags_raw")
          .is("deleted_at", null)
          .gt("date_key_raw", debut)
          .lte("date_key_raw", fin),
        supabase
          .from("activity")
          .select("uuid, start_local_date, sport_type_raw, activity_description")
          .is("deleted_at", null)
          .gte("start_local_date", debut)
          .lte("start_local_date", fin + "T23:59:59")
          .order("start_local_date"),
        supabase
          .from("weight_entry")
          .select("date_key_raw, note, weight_kg")
          .is("deleted_at", null)
          .gt("date_key_raw", debut)
          .lte("date_key_raw", fin),
        supabase
          .from("meal_note")
          .select("date_key_raw, meal_slot_uuid, note")
          .is("deleted_at", null)
          .gt("date_key_raw", debut)
          .lte("date_key_raw", fin),
      ])
      for (const r of [notes, activites, poids, repas]) if (r.error) throw r.error

      const jours = new Map<string, Journee>()
      const obtenir = (dateKey: string) => {
        let j = jours.get(dateKey)
        if (!j) {
          j = {
            dateKey,
            noteUUID: null,
            texte: "",
            tags: [],
            ailleurs: [],
            sports: [],
            pesee: false,
          }
          jours.set(dateKey, j)
        }
        return j
      }
      // Un texte blanc n'entre jamais : une note de repas ouverte puis
      // refermée sans un mot ne doit pas faire apparaître une journée.
      const ajouter = (
        j: Journee,
        source: string,
        texte: string | null,
        extra?: { sport?: string; kg?: number; activite?: string },
      ) => {
        if (texte?.trim()) j.ailleurs.push({ source, texte, ...extra })
      }

      for (const n of notes.data as {
        uuid: string
        date_key_raw: string
        text: string
        tags_raw: string[] | null
      }[]) {
        const j = obtenir(n.date_key_raw)
        j.noteUUID = n.uuid
        j.texte = n.text
        j.tags = n.tags_raw ?? []
      }

      // Le jour d'une sortie est celui de son instant local, comme sur le Mac.
      for (const a of activites.data as {
        uuid: string
        start_local_date: string
        sport_type_raw: string
        activity_description: string | null
      }[]) {
        const j = obtenir(a.start_local_date.slice(0, 10))
        if (!j.sports.includes(a.sport_type_raw)) j.sports.push(a.sport_type_raw)
        ajouter(j, "Sortie", a.activity_description, {
          sport: a.sport_type_raw,
          activite: a.uuid,
        })
      }

      const rang = new Map(creneaux.map((c) => [c.uuid, c.sort_order]))
      const nom = new Map(creneaux.map((c) => [c.uuid, c.name]))
      const repasTries = [...(repas.data as {
        date_key_raw: string
        meal_slot_uuid: string | null
        note: string
      }[])].sort(
        (x, y) =>
          (rang.get(x.meal_slot_uuid ?? "") ?? Infinity) -
          (rang.get(y.meal_slot_uuid ?? "") ?? Infinity),
      )
      for (const r of repasTries) {
        ajouter(obtenir(r.date_key_raw), nom.get(r.meal_slot_uuid ?? "") ?? "Repas", r.note)
      }

      // La pesée en dernier : c'est le chiffre du matin qu'on commente le soir.
      for (const p of poids.data as {
        date_key_raw: string
        note: string | null
        weight_kg: number
      }[]) {
        const j = obtenir(p.date_key_raw)
        j.pesee = true
        ajouter(j, "Pesée", p.note, { kg: p.weight_kg })
      }

      // Les jours sans la moindre marque n'existent pas — un jour n'est né
      // ici que parce qu'une source l'a nommé, mais une sortie sans
      // description et sans note ne laisse qu'un sport, ce qui compte.
      return {
        jours: [...jours.values()]
          .filter((j) => j.texte.trim() || j.ailleurs.length || j.sports.length || j.pesee)
          .sort((x, y) => y.dateKey.localeCompare(x.dateKey)),
        suivante: debut,
      }
    },
    getNextPageParam: (derniere) =>
      // Une année et demie en arrière suffit largement ; au-delà on laisse la
      // liste finir plutôt que de descendre indéfiniment.
      derniere.suivante > "2024-01-01" ? derniere.suivante : undefined,
  })
}

export function Journal({
  onActivite,
  onRepas,
}: {
  /// Aller voir la sortie citée.
  onActivite: (uuid: string) => void
  /// Aller à la journée de repas — c'est là que se modifient une note de
  /// créneau comme une pesée.
  onRepas: (dateKey: string) => void
}) {
  const [enEdition, setEnEdition] = useState<NoteAEditer | null>(null)
  const images = useImagesDuJournal()
  const creneaux = useCreneaux()
  const { data, error, isPending, fetchNextPage, hasNextPage, isFetchingNextPage } =
    useJournees(creneaux.data ?? [])

  const sentinelle = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const cible = sentinelle.current
    if (!cible || !hasNextPage) return
    const observateur = new IntersectionObserver((entrees) => {
      if (entrees[0].isIntersecting && !isFetchingNextPage) fetchNextPage()
    })
    observateur.observe(cible)
    return () => observateur.disconnect()
  }, [hasNextPage, isFetchingNextPage, fetchNextPage])

  if (isPending) return <p className="attenue">Chargement…</p>
  if (error) return <p className="erreur">{(error as Error).message}</p>

  const journees = data.pages.flatMap((p) => p.jours)
  const urlImage = (chemin: string) => images.data?.get(chemin.replace(/^.*\//, ""))

  const ouvrir = (j: Journee) =>
    setEnEdition({ uuid: j.noteUUID, dateKey: j.dateKey, texte: j.texte })

  return (
    <>
      {enEdition && (
        <Feuille titre="Note" onFerme={() => setEnEdition(null)}>
          <NoteEditor note={enEdition} onFerme={() => setEnEdition(null)} />
        </Feuille>
      )}

      {/* Écrire un jour que rien n'a encore marqué — un dimanche sans sortie
          ni repas noté n'apparaît dans aucune source, et sans ce champ il
          n'existait aucun chemin pour y écrire depuis le téléphone. */}
      <div className="barre-jour">
        <button
          className="note-du-jour"
          onClick={() => {
            const aujourdhui = jourCourant()
            const j = journees.find((x) => x.dateKey === aujourdhui)
            setEnEdition({
              uuid: j?.noteUUID ?? null,
              dateKey: aujourdhui,
              texte: j?.texte ?? "",
            })
          }}
        >
          Écrire aujourd'hui
        </button>
        <label className="choix-jour bouton-date" aria-label="Écrire un autre jour">
          {/* Dessiné plutôt qu'un emoji : « 📅 » arrive en couleurs, avec le
              rendu de la police système, et jure à côté de traits monochromes
              réglés au demi-pixel. */}
          <svg
            width="22"
            height="22"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.8"
            strokeLinecap="round"
            aria-hidden
          >
            <rect x="3.5" y="5" width="17" height="15.5" rx="3" />
            <path d="M3.5 9.5h17M8 3.5v3M16 3.5v3" />
          </svg>
          <input
            type="date"
            max={jourCourant()}
            onChange={(e) => {
              if (!e.target.value) return
              const j = journees.find((x) => x.dateKey === e.target.value)
              setEnEdition({
                uuid: j?.noteUUID ?? null,
                dateKey: e.target.value,
                texte: j?.texte ?? "",
              })
            }}
          />
        </label>
      </div>

      {journees.length === 0 && <p className="attenue">Aucune note pour l'instant.</p>}

      {journees.map((j) => (
        <article className="note" key={j.dateKey}>
          <h2 className="jour">
            <span>
              {dateLongue(j.dateKey)}
              {j.pesee && <span className="pastille" title="Pesée" />}
            </span>
            <button className="lien petit" onClick={() => ouvrir(j)}>
              {j.noteUUID ? "Modifier" : "Écrire"}
            </button>
          </h2>

          {j.tags.length > 0 && (
            <div className="etiquettes">
              {j.tags.map((tag) => (
                <span className="etiquette-tag" key={tag}>
                  {tag}
                </span>
              ))}
            </div>
          )}

          {j.texte.trim() && <Markdown texte={j.texte} imageURL={urlImage} />}

          {/* Ce qui vient d'ailleurs, cité et attribué : une description de
              sortie et une note de repas ne se lisent pas comme la note du
              jour, et les fondre toutes ensemble ferait croire qu'on a écrit
              d'un seul trait. */}
          {j.ailleurs.map((a, i) => {
            // Une citation renvoie à l'endroit d'où elle vient : la fiche de
            // la sortie, ou la journée de repas. C'est la question que pose
            // une phrase reprise ailleurs — « c'était laquelle, celle-là ? ».
            const aller = a.activite
              ? () => onActivite(a.activite as string)
              : () => onRepas(j.dateKey)
            return (
              <blockquote
                className="ailleurs cliquable"
                key={i}
                role="button"
                tabIndex={0}
                onClick={aller}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault()
                    aller()
                  }
                }}
              >
                <span className="source">
                  {a.sport ? (
                    <>
                      <IconeSport sport={a.sport} taille={15} />
                      {nomDuSport(a.sport)}
                    </>
                  ) : (
                    a.source
                  )}
                  <span className="fin-source">
                    {a.kg !== undefined && (
                      <span className="poids-source">
                        {a.kg.toLocaleString("fr-FR")} kg
                      </span>
                    )}
                    <span aria-hidden>›</span>
                  </span>
                </span>
                <Markdown texte={a.texte} imageURL={urlImage} />
              </blockquote>
            )
          })}
        </article>
      ))}

      <div ref={sentinelle} />
      {isFetchingNextPage && <p className="attenue petit">Chargement…</p>}
    </>
  )
}
