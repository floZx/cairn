import { useEffect, useRef, useState } from "react"
import { POIDS_MASQUE } from "./masquees"
import { useInfiniteQuery, useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { Markdown } from "./markdown"
import { chiffresDeLaLigne } from "./format"
import { NoteEditor, jourCourant, type NoteAEditer } from "./NoteEditor"
import { Feuille, Chargement } from "./Chrome"
import { Symbole, couleurDuSport, symboleDuSport } from "./IconeSport"

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
    /// Pour une sortie : son nom et ses chiffres, le titre et la ligne de
    /// sa carte.
    nom?: string
    chiffres?: string
  }[]
  /// Les sports du jour, pour la pastille — une journée sans un mot mais avec
  /// une sortie doit tout de même se voir.
  sports: string[]
  pesee: boolean
}

const JOURS_PAR_PAGE = 45

/// La borne haute de la première page.
///
/// Elle valait « aujourd'hui », et une note écrite pour demain — le Mac les
/// accepte — n'était donc jamais demandée : elle n'existait nulle part sur le
/// téléphone. Signalé. Les pages suivantes, elles, descendent bien depuis
/// aujourd'hui.
const FUTUR = "9999-12-31"

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
export function useImagesDuJournal() {
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
    initialPageParam: FUTUR,
    queryFn: async ({ pageParam }) => {
      const fin = pageParam as string
      // La première page part d'aujourd'hui pour son bord bas, même si son
      // bord haut est ouvert : sans quoi elle couvrirait quarante-cinq jours
      // de l'an 9999.
      const debut = decale(fin === FUTUR ? jourCourant() : fin, -JOURS_PAR_PAGE)

      const [notes, activites, poids, repas] = await Promise.all([
        supabase
          .from("journal_note")
          .select("uuid, date_key_raw, text, tags_raw")
          .is("deleted_at", null)
          .gt("date_key_raw", debut)
          .lte("date_key_raw", fin),
        supabase
          .from("activity")
          .select(
            "uuid, name, start_local_date, sport_type_raw, activity_description, distance, moving_time, total_elevation_gain, average_heartrate, calories",
          )
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
        extra?: { sport?: string; kg?: number; activite?: string; nom?: string; chiffres?: string },
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
      // Chaque sortie a sa carte, même sans un mot : son nom et ses chiffres
      // disent déjà ce que la journée a été.
      for (const a of activites.data as {
        uuid: string
        name: string
        start_local_date: string
        sport_type_raw: string
        activity_description: string | null
        distance: number
        moving_time: number
        total_elevation_gain: number
        average_heartrate: number | null
        calories: number | null
      }[]) {
        const j = obtenir(a.start_local_date.slice(0, 10))
        if (!j.sports.includes(a.sport_type_raw)) j.sports.push(a.sport_type_raw)
        j.ailleurs.push({
          source: "Sortie",
          texte: a.activity_description?.trim() ? a.activity_description : "",
          sport: a.sport_type_raw,
          activite: a.uuid,
          nom: a.name,
          chiffres: chiffresDeLaLigne(a),
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
  noteAOuvrir,
  onNoteOuverte,
  onActivite,
  onRepas,
}: {
  /// Le jour dont la note doit s'ouvrir en arrivant — la citation d'une note
  /// dans People. Le journal se déroule par pages, et la journée visée peut
  /// être hors de celles qui sont chargées : elle est donc demandée
  /// directement plutôt que cherchée dans la liste.
  noteAOuvrir?: string | null
  /// Prévenir qu'elle est ouverte, pour que le signal ne se rejoue pas.
  onNoteOuverte?: () => void
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

  // La note visée, cherchée en base : la journée peut être hors des pages
  // déroulées, et la trouver dans la liste demanderait de la dérouler jusque-là.
  useEffect(() => {
    if (!noteAOuvrir) return
    let annule = false
    ;(async () => {
      const { data } = await supabase
        .from("journal_note")
        .select("uuid, text")
        .eq("date_key_raw", noteAOuvrir)
        .is("deleted_at", null)
        .maybeSingle()
      if (annule) return
      const ligne = data as { uuid: string; text: string } | null
      setEnEdition({
        uuid: ligne?.uuid ?? null,
        dateKey: noteAOuvrir,
        texte: ligne?.text ?? "",
      })
      onNoteOuverte?.()
    })()
    return () => {
      annule = true
    }
  }, [noteAOuvrir, onNoteOuverte])

  /// Amène la liste sur le jour qu'on édite, derrière la feuille.
  ///
  /// Ouvrir une note depuis le calendrier laissait la liste où elle était :
  /// on refermait la feuille et l'on se retrouvait à cent jours de ce qu'on
  /// venait d'écrire.
  ///
  /// Dans un effet et non au moment du clic : la journée visée peut n'être
  /// rendue qu'après, et une image demandée trop tôt ne trouvait rien à
  /// atteindre — mesuré, le défilement ne bougeait pas d'un pixel.
  useEffect(() => {
    if (!enEdition) return
    document
      .getElementById(`jour-${enEdition.dateKey}`)
      ?.scrollIntoView({ block: "start" })
  }, [enEdition?.dateKey])

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

  if (isPending) return <Chargement />
  if (error) return <p className="erreur">{(error as Error).message}</p>

  const journees = data.pages.flatMap((p) => p.jours)
  const urlImage = (chemin: string) => images.data?.get(chemin.replace(/^.*\//, ""))

  const ouvrir = (j: Journee) =>
    setEnEdition({ uuid: j.noteUUID, dateKey: j.dateKey, texte: j.texte })

  // La carte du jour toujours en tête, même vide : c'est elle qu'on touche
  // pour écrire, à la place du bouton « Écrire aujourd'hui ».
  const aujourdhui = jourCourant()
  const avecAujourdhui = journees.some((j) => j.dateKey === aujourdhui)
    ? journees
    : [
        {
          dateKey: aujourdhui,
          noteUUID: null,
          texte: "",
          tags: [],
          ailleurs: [],
          sports: [],
          pesee: false,
        } satisfies Journee,
        ...journees,
      ].sort((x, y) => y.dateKey.localeCompare(x.dateKey))

  return (
    <>
      {enEdition && (
        <Feuille titre="Note" onFerme={() => setEnEdition(null)}>
          <NoteEditor note={enEdition} onFerme={() => setEnEdition(null)} />
        </Feuille>
      )}

      {parMois(avecAujourdhui).map((mois) => (
        <section key={mois.cle}>
          {/* Le mois dit une fois, et collé en haut en défilant : les cartes
              n'ont plus à porter la date longue. */}
          <h2 className="mois-journal">{mois.titre}</h2>
          {mois.jours.map((j) => (
            <CarteJour
              key={j.dateKey}
              j={j}
              aujourdhui={aujourdhui}
              urlImage={urlImage}
              onEcrire={() => ouvrir(j)}
              onActivite={onActivite}
              onRepas={onRepas}
            />
          ))}
        </section>
      ))}

      <div ref={sentinelle} />
      {isFetchingNextPage && <Chargement petit />}
    </>
  )
}

const nomDuMois = new Intl.DateTimeFormat("fr-FR", { month: "long", year: "numeric" })
const jourAbrege = new Intl.DateTimeFormat("fr-FR", { weekday: "short" })
const jourEnToutes = new Intl.DateTimeFormat("fr-FR", { weekday: "long" })
const jourEtMois = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short" })

/// Une clé de jour en date locale — découpée à la main, voir `dateLongue`.
function enDate(dateKey: string): Date {
  const [a, m, j] = dateKey.split("-").map(Number)
  return new Date(a, m - 1, j)
}

function capitale(texte: string): string {
  return texte.charAt(0).toUpperCase() + texte.slice(1)
}

/// Les journées rangées par mois, dans l'ordre où elles viennent.
function parMois(jours: Journee[]) {
  const mois: { cle: string; titre: string; jours: Journee[] }[] = []
  for (const j of jours) {
    const cle = j.dateKey.slice(0, 7)
    const dernier = mois[mois.length - 1]
    if (dernier?.cle === cle) dernier.jours.push(j)
    else mois.push({ cle, titre: nomDuMois.format(enDate(j.dateKey)), jours: [j] })
  }
  return mois
}

/// « Aujourd'hui », « Hier », le jour dans la semaine, puis « 18 sept. » —
/// les mots de la liste du Mac.
export function jourRelatif(dateKey: string, aujourdhui: string): string {
  const ecart = Math.round(
    (enDate(aujourdhui).getTime() - enDate(dateKey).getTime()) / 86_400_000,
  )
  if (ecart === 0) return "Aujourd'hui"
  if (ecart === 1) return "Hier"
  if (ecart >= 2 && ecart <= 6) return capitale(jourEnToutes.format(enDate(dateKey)))
  return jourEtMois.format(enDate(dateKey))
}

/// Le sport en pastille : le symbole blanc sur sa couleur, comme sur le Mac.
function PastilleSport({ sport, taille }: { sport: string; taille: number }) {
  return (
    <span
      className="rond-sport"
      style={{ width: taille, height: taille, background: couleurDuSport(sport) }}
    >
      <Symbole nom={symboleDuSport(sport)} taille={Math.round(taille * 0.6)} couleur="#fff" />
    </span>
  )
}

function CarteJour({
  j,
  aujourdhui,
  urlImage,
  onEcrire,
  onActivite,
  onRepas,
}: {
  j: Journee
  aujourdhui: string
  urlImage: (chemin: string) => string | undefined
  onEcrire: () => void
  onActivite: (uuid: string) => void
  onRepas: (dateKey: string) => void
}) {
  const estAujourdhui = j.dateKey === aujourdhui
  const date = enDate(j.dateKey)
  return (
    <article
      className={estAujourdhui ? "note aujourdhui" : "note"}
      id={`jour-${j.dateKey}`}
      // Toucher la carte, c'est écrire ce jour-là — sauf sur ce qui mène
      // ailleurs : une sortie, un repas, une personne citée, un lien.
      onClick={(e) => {
        if ((e.target as Element).closest("a, button, .carte-ailleurs")) return
        onEcrire()
      }}
    >
      <h2 className="jour">
        <span className="tuile-jour">
          <span className="abrege">{jourAbrege.format(date).replace(".", "")}</span>
          <span className="numero">{date.getDate()}</span>
        </span>
        <span className="relatif">{jourRelatif(j.dateKey, aujourdhui)}</span>
        <span className="marques">
          {j.tags.map((tag) => (
            <span className="etiquette-tag" key={tag}>
              {tag}
            </span>
          ))}
          {/* Rien du poids tant qu'il est masqué : ce point bleu n'avait
              plus d'écran où se dire. */}
          {j.pesee && !POIDS_MASQUE && <span className="pastille" title="Pesée" />}
          {j.sports.map((sport) => (
            <PastilleSport key={sport} sport={sport} taille={20} />
          ))}
        </span>
      </h2>

      {j.texte.trim() ? (
        <div className="texte-jour">
          <Markdown texte={j.texte} imageURL={urlImage} premierePhrase />
        </div>
      ) : (
        estAujourdhui && (
          <p className="invite-jour">Qu'est-ce qui s'est passé aujourd'hui ?</p>
        )
      )}

      {/* Ce qui vient d'ailleurs, en cartes : une sortie et une note de repas
          ne se lisent pas comme la note du jour, et les fondre toutes
          ensemble ferait croire qu'on a écrit d'un seul trait. Chacune mène
          là d'où elle vient. */}
      {j.ailleurs.length > 0 && (
        <div className="cartes-ailleurs">
          {j.ailleurs.map((a, i) => {
            const aller = a.activite
              ? () => onActivite(a.activite as string)
              : () => onRepas(j.dateKey)
            return (
              <div
                className="carte-ailleurs"
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
                {a.sport ? (
                  <PastilleSport sport={a.sport} taille={28} />
                ) : (
                  <span className="rond-icone">
                    <Symbole nom={a.kg !== undefined ? "scalemass" : "fork.knife"} taille={15} />
                  </span>
                )}
                <div className="corps">
                  <b>{a.nom ?? a.source}</b>
                  {a.chiffres && <small>{a.chiffres}</small>}
                  {a.kg !== undefined && <small>{a.kg.toLocaleString("fr-FR")} kg</small>}
                  {a.texte && (
                    <div className="texte">
                      <Markdown texte={a.texte} imageURL={urlImage} />
                    </div>
                  )}
                </div>
                <span className="chevron" aria-hidden>
                  ›
                </span>
              </div>
            )
          })}
        </div>
      )}
    </article>
  )
}
