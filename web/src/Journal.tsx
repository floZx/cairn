import { useEffect, useRef, useState } from "react"
import { useInfiniteQuery, useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { Markdown } from "./markdown"
import { dateLongue } from "./format"
import { NoteEditor, jourCourant, type NoteAEditer } from "./NoteEditor"

type Note = {
  uuid: string
  date_key_raw: string
  text: string
  tags_raw: string[] | null
}

const PAR_PAGE = 30

/// Les images des notes, résolues en une fois plutôt qu'une par une.
///
/// Le Markdown pointe sur `pieces-jointes/2026-08-12-1.jpg` : un chemin relatif
/// qui avait un sens dans un dossier et n'en a plus aucun ici. La table dit où
/// les octets sont dans Storage, et le seau est privé — il faut donc une URL
/// signée, que seul un jeton valide obtient.
///
/// Toutes d'un coup, et pour vingt-quatre heures : quelques centaines d'images
/// tiennent dans une requête, alors qu'une par image ferait autant d'allers-
/// retours que la note contient de photos, à chaque défilement.
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
          // Le nom de fichier seul, sans le dossier : c'est la clé que le
          // Markdown emploie, `pieces-jointes/` n'étant qu'un préfixe fixe.
          return url ? [[r.file_name, url] as [string, string]] : []
        }),
      )
    },
  })
}

export function Journal() {
  const images = useImagesDuJournal()
  const [enEdition, setEnEdition] = useState<NoteAEditer | null>(null)

  const { data, error, isPending, fetchNextPage, hasNextPage, isFetchingNextPage } =
    useInfiniteQuery({
      queryKey: ["journal"],
      initialPageParam: 0,
      queryFn: async ({ pageParam }) => {
        const { data, error } = await supabase
          .from("journal_note")
          .select("uuid, date_key_raw, text, tags_raw")
          .is("deleted_at", null)
          .order("date_key_raw", { ascending: false })
          .range(pageParam, pageParam + PAR_PAGE - 1)
        if (error) throw error
        return data as unknown as Note[]
      },
      getNextPageParam: (derniere, toutes) =>
        derniere.length < PAR_PAGE ? undefined : toutes.length * PAR_PAGE,
    })

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

  if (enEdition) {
    return <NoteEditor note={enEdition} onFerme={() => setEnEdition(null)} />
  }

  if (isPending) return <p className="attenue">Chargement…</p>
  if (error) return <p className="erreur">{(error as Error).message}</p>

  const notes = data.pages.flat()
  const aujourdhui = jourCourant()
  // Reprise plutôt que création quand la journée est déjà racontée : un
  // journal tient une note par jour, et un second bouton « nouvelle note »
  // qui en fabriquerait une deuxième trahirait ce que le Mac garantit.
  const noteDuJour = notes.find((n) => n.date_key_raw === aujourdhui)

  const boutonDuJour = (
    <button
      className="note-du-jour"
      onClick={() =>
        setEnEdition({
          uuid: noteDuJour?.uuid ?? null,
          dateKey: aujourdhui,
          texte: noteDuJour?.text ?? "",
        })
      }
    >
      {noteDuJour ? "Compléter la note du jour" : "Écrire la note du jour"}
    </button>
  )

  if (notes.length === 0) {
    return (
      <>
        {boutonDuJour}
        <p className="attenue">Aucune note pour l'instant.</p>
      </>
    )
  }

  const urlImage = (chemin: string) =>
    images.data?.get(chemin.replace(/^.*\//, ""))

  return (
    <>
      {boutonDuJour}
      {notes.map((note) => (
        <article className="note" key={note.uuid}>
          <h2 className="jour">
            {dateLongue(note.date_key_raw)}
            <button
              className="lien petit"
              onClick={() =>
                setEnEdition({
                  uuid: note.uuid,
                  dateKey: note.date_key_raw,
                  texte: note.text,
                })
              }
            >
              Modifier
            </button>
          </h2>
          {note.tags_raw && note.tags_raw.length > 0 && (
            <div className="etiquettes">
              {note.tags_raw.map((tag) => (
                <span className="etiquette-tag" key={tag}>
                  {tag}
                </span>
              ))}
            </div>
          )}
          <Markdown texte={note.text} imageURL={urlImage} />
        </article>
      ))}
      <div ref={sentinelle} />
      {isFetchingNextPage && <p className="attenue petit">Chargement…</p>}
    </>
  )
}
