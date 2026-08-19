import { useMemo, useRef, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { IconeSport, couleurDuSport } from "./IconeSport"
import { allureOuVitesse, dateCourte, denivele, distance, duree, heure } from "./format"
import { traceDepuisBytea } from "./track"
import { CarteStatique } from "./CarteStatique"
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
/// c'est tout ce qui n'a de sens qu'à plusieurs.
///
/// **L'en-tête d'athlète.** Chez Strava, un fil mélange les sorties de
/// plusieurs personnes, et il faut donc dire de qui est celle-ci. Ce miroir
/// n'en contient qu'une, la sienne : sa photo et son nom répétés vingt fois
/// n'apprennent rien et prennent la place de ce qu'on est venu lire. La fiche
/// s'annonce donc par la sortie — son nom là où était celui de l'athlète, et le
/// sport dans la pastille où était le portrait.
///
/// **Les boutons.** Un pouce et une bulle de commentaire ne mèneraient nulle
/// part : le miroir est en lecture, et cette application ne parle pas à Strava
/// — c'est le Mac qui s'en charge. Un bouton qui ne fait rien ment plus qu'un
/// bouton absent.
///
/// **Les kudos et les performances.** Les colonnes existent — le Mac les
/// recopie de Strava — mais un compte de pouces reçus ne dit rien de la sortie,
/// et il n'y a personne ici pour en envoyer. C'est le décompte d'une audience
/// qu'un journal personnel n'a pas.

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
  photo_count: number | null
}

/// Les colonnes que la fiche ajoute à celles de la liste compacte.
///
/// Demandées seulement quand le fil est à l'écran : la trace simplifiée pèse
/// deux kilo-octets par sortie, et la liste compacte, qui n'en dessine aucune,
/// n'a pas à les télécharger pour rien.
export const COLONNES_FIL = "simplified_track, photo_count"

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
  photo,
  onOuvrir,
}: {
  activite: ActiviteDuFil
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
        {/* La pastille du sport occupe la place du portrait, et rend le service
            qu'il ne rendait pas : elle dit d'un coup d'œil, en couleur, de
            quelle sorte de sortie il s'agit. */}
        <span className="rond-sport">
          <IconeSport sport={a.sport_type_raw} taille={22} />
        </span>
        <div className="quoi-fil">
          <h3 className="titre-fil">{a.name}</h3>
          {/* Après la date, l'étiquette plutôt que le sport.
              Le sport est déjà dit deux fois par la pastille — son dessin et sa
              couleur — et l'écrire une troisième ne renseignait personne. Les
              étiquettes, elles, occupaient une ligne à elles seules alors
              qu'une sortie en porte rarement plus d'une : elles tiennent dans
              celle-ci, et la fiche gagne la hauteur d'une ligne par sortie
              étiquetée.
              Sans étiquette, la date reste seule — pas de point d'attente pour
              quelque chose qui ne vient pas. */}
          <div className="repere-fil minuscule attenue">
            <span>
              {dateCourte(a.start_local_date)} à {heure(a.start_local_date)}
            </span>
            {etiquettes.map((m) => (
              <span className="etiquette-tag minuscule" key={m}>
                {NOMS[m]}
              </span>
            ))}
          </div>
        </div>
      </header>

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
              // un coin, comme le fil de Strava pose sa carte sous sa photo.
              //
              // Une carte ici aussi, et pas seulement une trace nue : sur
              // quatre-vingt-dix pixels de large, un trait rouge sans sol ne
              // dit ni où ni dans quoi. Trois ou quatre tuiles suffisent à
              // couvrir la vignette, ce qui ne coûte rien de plus que
              // l'aplat qu'elles remplacent.
              <div className="vignette-trace matiere">
                <CarteStatique
                  trace={trace}
                  couleur={couleur}
                  marge={7}
                  epaisseur={2}
                  voile
                />
              </div>
            ) : (
              // Sans photo, la bande est à la carte : c'est la même que la
              // fiche montre, mêmes tuiles et même fond retenu, pour qu'on ne
              // passe pas d'un plan à une photo aérienne en ouvrant la sortie.
              <CarteStatique trace={trace} couleur={couleur} />
            ))}
        </div>
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
  const photos = usePhotosDuFil(activites)

  return (
    <div className="fil">
      {activites.map((a) => (
        <Fiche
          key={a.uuid}
          activite={a}
          // La chaîne vide — « demandé, rien à montrer » — vaut absence.
          photo={photos.get(a.uuid) || undefined}
          onOuvrir={onOuvrir}
        />
      ))}
    </div>
  )
}
