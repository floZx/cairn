import { useMemo, useRef, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { nomDuSport } from "./sports"
import { IconeSport, couleurDuSport } from "./IconeSport"
import { allureOuVitesse, dateCourte, denivele, distance, duree, heure } from "./format"
import { traceDepuisBytea } from "./track"
import { Miniature } from "./Miniature"
import { NOMS, etiquettesDe, type SourceEtiquettes } from "./etiquettes"

/// Le fil : la même sélection que la liste, une activité par fiche.
///
/// Deux présentations plutôt qu'une améliorée, comme le Mac a son tableau et
/// ses fiches : la liste compacte tient dix sorties par écran et sert à
/// retrouver, le fil en montre une et sert à revoir — la forme de la trace, la
/// photo, les chiffres lus sans ouvrir. Aucune ne remplace l'autre, c'est
/// pourquoi c'est un choix et non une refonte.
///
/// La ressemblance avec le fil de Strava est voulue : c'est la disposition sous
/// laquelle on a l'habitude de relire ses sorties. Ce qu'elle n'emprunte pas,
/// ce sont les boutons — un pouce et une bulle de commentaire qui ne mèneraient
/// nulle part. Le miroir est en lecture, et cette application ne parle pas à
/// Strava (c'est le Mac qui s'en charge) : un bouton qui ne fait rien ment plus
/// qu'un bouton absent.

/// Ce qu'une fiche du fil demande en plus des colonnes de la liste.
export type ActiviteDuFil = SourceEtiquettes & {
  uuid: string
  name: string
  sport_type_raw: string
  start_local_date: string
  distance: number
  moving_time: number
  total_elevation_gain: number
  simplified_track: string | null
  device_name: string | null
  photo_count: number | null
  kudos_count: number
  achievement_count: number
}

/// Les colonnes que la fiche ajoute à celles de la liste compacte.
///
/// Demandées seulement quand le fil est à l'écran : la trace simplifiée pèse
/// deux kilo-octets par sortie, et la liste compacte, qui n'en dessine aucune,
/// n'a pas à les télécharger pour rien.
export const COLONNES_FIL =
  "simplified_track, device_name, photo_count, kudos_count, achievement_count"

/// Qui a fait ces sorties : une ligne, la même pour toutes les fiches.
///
/// Une seule personne dans ce miroir, donc une requête sans filtre et gardée
/// longtemps. L'en-tête n'apprend rien à celui qui regarde son propre fil —
/// c'est pourtant ce qui fait qu'une fiche se lit comme une carte postée
/// plutôt que comme une ligne de tableau, et le nom d'appareil qu'il porte,
/// lui, ne se lit nulle part ailleurs sur le téléphone.
function useAthlete() {
  return useQuery({
    queryKey: ["athlete"],
    staleTime: 12 * 3600 * 1000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("athlete")
        .select("first_name, last_name, profile_image_url")
        .is("deleted_at", null)
        .limit(1)
        .maybeSingle()
      if (error) throw error
      return data as {
        first_name: string
        last_name: string
        profile_image_url: string | null
      } | null
    },
  })
}

/// La première photo de chaque sortie qui en a une, en une fois.
///
/// Le seau est privé : il faut une URL signée par photo, et les signer une par
/// une ferait une requête par fiche affichée. Toutes ensemble, pour la journée,
/// comme le journal signe déjà ses pièces jointes.
///
/// `photo_count` sert de garde : il est dans la ligne, donc on sait avant de
/// demander quelles sorties ont quelque chose à montrer, et un fil de sorties
/// sans photo ne coûte aucune requête.
///
/// Ce qui a déjà été signé est gardé de côté et n'est plus redemandé, et le
/// reste part par lots : sans cela, chaque page chargée redemanderait les
/// photos de toutes les précédentes, et le `in.(…)` de PostgREST — qui voyage
/// dans l'adresse — finirait par dépasser ce qu'un serveur accepte, trois cents
/// sorties faisant onze kilo-octets d'uuid. Le lot suivant part de lui-même
/// quand celui-ci est résolu.

/// De l'ordre d'une page du fil : la requête garde ainsi la taille de celle qui
/// a amené les lignes.
const PAR_LOT = 60

function usePhotosDuFil(activites: ActiviteDuFil[]) {
  const connues = useRef(new Map<string, string>())
  const lot = activites
    .filter((a) => (a.photo_count ?? 0) > 0 && !connues.current.has(a.uuid))
    .map((a) => a.uuid)
    .slice(0, PAR_LOT)

  const { data } = useQuery({
    queryKey: ["photos-fil", lot.join(",")],
    enabled: lot.length > 0,
    staleTime: 12 * 3600 * 1000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("activity_photo")
        .select("activity_uuid, storage_path")
        .in("activity_uuid", lot)
        .is("deleted_at", null)
        .not("storage_path", "is", null)
        .order("sort_index")
      if (error) throw error
      const lignes = data as { activity_uuid: string; storage_path: string }[]

      // Une seule par sortie : la fiche n'en montre qu'une, et signer les six
      // photos d'une sortie pour n'en afficher qu'une gaspille la requête.
      // `order` a déjà mis la première en tête.
      const premiere = new Map<string, string>()
      for (const l of lignes) {
        if (!premiere.has(l.activity_uuid)) premiere.set(l.activity_uuid, l.storage_path)
      }

      // Toutes les sorties du lot sont inscrites, y compris celles qui n'ont
      // rien rendu : c'est ce qui les empêche de repartir dans le lot suivant
      // à chaque rendu. La chaîne vide dit « demandé, rien à montrer ».
      const resolues = new Map(lot.map((uuid) => [uuid, ""]))
      if (premiere.size > 0) {
        const { data: urls, error: erreurURL } = await supabase.storage
          .from("photos")
          .createSignedUrls([...premiere.values()], 24 * 3600)
        if (erreurURL) throw erreurURL
        const parChemin = new Map(urls.map((u) => [u.path ?? "", u.signedUrl]))
        for (const [uuid, chemin] of premiere) {
          const url = parChemin.get(chemin)
          if (url) resolues.set(uuid, url)
        }
      }
      return resolues
    },
  })

  // Versé au fil des lots. Écrire dans une `ref` pendant le rendu se justifie
  // ici : c'est le même contenu à chaque fois, et le passer par un effet
  // ferait un rendu de plus avant que la photo n'apparaisse.
  if (data) for (const [uuid, url] of data) connues.current.set(uuid, url)
  return connues.current
}

function Avatar({
  url,
  initiales,
}: {
  url: string | null | undefined
  initiales: string
}) {
  // L'image de profil vient du serveur de Strava, qui n'est pas le nôtre : elle
  // peut disparaître, et l'athlète a pu n'en jamais poser. Les initiales sont
  // alors le repli, jamais un carré vide.
  const [cassee, setCassee] = useState(false)
  if (!url || cassee) return <div className="avatar-fil vide">{initiales}</div>
  return (
    <img
      className="avatar-fil"
      src={url}
      alt=""
      loading="lazy"
      onError={() => setCassee(true)}
    />
  )
}

function Chiffre({ valeur, etiquette }: { valeur: string; etiquette: string }) {
  return (
    <div className="chiffre-fil">
      <div className="etiquette">{etiquette}</div>
      <div className="valeur">{valeur}</div>
    </div>
  )
}

/// Trois chiffres, jamais quatre.
///
/// C'est ce que Strava montre, et la raison tient à la largeur d'un téléphone :
/// au quatrième, les valeurs passent sous leurs libellés ou se coupent. Le
/// dénivelé prend la place de l'allure quand il y en a — sur un trail, 987 m
/// dit davantage de la sortie que la minute par kilomètre ; sur du plat, il n'y
/// a rien à en dire et l'allure reprend la colonne.
function chiffresDe(a: ActiviteDuFil) {
  const chiffres: { valeur: string; etiquette: string }[] = []
  if (a.distance > 0) chiffres.push({ valeur: distance(a.distance), etiquette: "Distance" })
  const rythme = allureOuVitesse(a.sport_type_raw, a.distance, a.moving_time)
  if (a.total_elevation_gain > 0) {
    chiffres.push({ valeur: denivele(a.total_elevation_gain), etiquette: "Dénivelé" })
  } else if (rythme) {
    chiffres.push(rythme)
  }
  if (a.moving_time > 0) chiffres.push({ valeur: duree(a.moving_time), etiquette: "Temps" })
  return chiffres
}

function Fiche({
  activite: a,
  athlete,
  photo,
  onOuvrir,
}: {
  activite: ActiviteDuFil
  athlete: { nom: string; initiales: string; image: string | null } | null
  photo: string | undefined
  onOuvrir: (uuid: string) => void
}) {
  const trace = useMemo(() => traceDepuisBytea(a.simplified_track), [a.simplified_track])
  const etiquettes = etiquettesDe(a)
  const couleur = couleurDuSport(a.sport_type_raw)

  // Le Mac inscrit le chemin de stockage d'une photo dès qu'il connaît la
  // photo, et téléverse les octets ensuite : une fiche peut donc désigner une
  // image qui n'est pas encore arrivée. Elle reprend alors la disposition
  // qu'elle aurait sans photo — la trace en grand — plutôt que de garder une
  // vignette brisée et un coin de trace.
  const [photoCassee, setPhotoCassee] = useState(false)
  const image = photo && !photoCassee ? photo : null

  return (
    <article
      className="fiche-fil"
      onClick={() => onOuvrir(a.uuid)}
      style={{ "--teinte-sport": couleur } as React.CSSProperties}
    >
      <header className="tete-fil">
        <Avatar url={athlete?.image} initiales={athlete?.initiales ?? "?"} />
        <div className="qui-fil">
          <div className="nom-athlete">{athlete?.nom ?? "Moi"}</div>
          <div className="attenue minuscule">
            {dateCourte(a.start_local_date)} à {heure(a.start_local_date)}
            {a.device_name ? ` · ${a.device_name}` : ""}
          </div>
          <div className="sport-fil minuscule">
            <IconeSport sport={a.sport_type_raw} taille={15} />
            <span>{nomDuSport(a.sport_type_raw)}</span>
            {etiquettes.map((m) => (
              <span className="etiquette-tag minuscule" key={m}>
                {NOMS[m]}
              </span>
            ))}
          </div>
        </div>
      </header>

      <h3 className="titre-fil">{a.name}</h3>

      <div className="chiffres-fil">
        {chiffresDe(a).map((c) => (
          <Chiffre key={c.etiquette} valeur={c.valeur} etiquette={c.etiquette} />
        ))}
      </div>

      {(image || trace.length > 1) && (
        <div className="media-fil">
          {image && (
            <img
              className="photo-fil"
              src={image}
              alt=""
              loading="lazy"
              decoding="async"
              onError={() => setPhotoCassee(true)}
            />
          )}
          {trace.length > 1 &&
            (image ? (
              // Les deux ensemble : la photo dit où l'on était, la trace dit
              // par où l'on est passé, et l'une n'est pas l'autre. Posée dans
              // un coin sur la même matière que les barres, comme le fil de
              // Strava pose sa carte sous sa photo.
              <div className="vignette-trace matiere">
                <Miniature trace={trace} couleur={couleur} epaisseur={2} />
              </div>
            ) : (
              <Miniature trace={trace} couleur={couleur} />
            ))}
        </div>
      )}

      {(a.kudos_count > 0 || a.achievement_count > 0) && (
        <footer className="pied-fil minuscule attenue">
          {a.kudos_count > 0 && (
            <span className="compte-fil">
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.7"
                strokeLinejoin="round"
                aria-hidden
              >
                <path d="M7 21V10l4.5-7a2 2 0 013 2.3L13.5 9H19a2 2 0 012 2.4l-1.6 7A2.5 2.5 0 0117 20.5H7z" />
                <path d="M7 10H4.5A1.5 1.5 0 003 11.5v8A1.5 1.5 0 004.5 21H7" />
              </svg>
              {a.kudos_count}
              {/* Le mot au singulier comme au pluriel : « kudos » est déjà un
                  pluriel, et Strava l'écrit ainsi en français. */}
              <span> kudos</span>
            </span>
          )}
          {a.achievement_count > 0 && (
            <span className="compte-fil">
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.7"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden
              >
                {/* Une coupe : les anses, la vasque, le pied. */}
                <path d="M7 4h10v4a5 5 0 01-10 0z" />
                <path d="M7 5.5H4.5V7a3 3 0 003 3M17 5.5h2.5V7a3 3 0 01-3 3" />
                <path d="M12 13v4M9 20h6M10 17h4l.5 3h-5z" />
              </svg>
              {a.achievement_count}
              <span> {a.achievement_count > 1 ? "performances" : "performance"}</span>
            </span>
          )}
        </footer>
      )}
    </article>
  )
}

export function Fil({
  activites,
  onOuvrir,
}: {
  activites: ActiviteDuFil[]
  onOuvrir: (uuid: string) => void
}) {
  const athlete = useAthlete()
  const photos = usePhotosDuFil(activites)


  const qui = athlete.data
    ? {
        // Un athlète sans nom reste possible — une ligne poussée avant que
        // le profil ne soit récupéré — et « Moi » vaut mieux qu'un en-tête
        // vide au-dessus de sa propre sortie.
        nom: `${athlete.data.first_name} ${athlete.data.last_name}`.trim() || "Moi",
        initiales:
          `${athlete.data.first_name[0] ?? ""}${athlete.data.last_name[0] ?? ""}`.toUpperCase() ||
          "?",
        image: athlete.data.profile_image_url,
      }
    : null

  return (
    <div className="fil">
      {activites.map((a) => (
        <Fiche
          key={a.uuid}
          activite={a}
          athlete={qui}
          // La chaîne vide — « demandé, rien à montrer » — vaut absence.
          photo={photos.get(a.uuid) || undefined}
          onOuvrir={onOuvrir}
        />
      ))}
    </div>
  )
}
