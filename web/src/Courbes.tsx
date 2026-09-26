import { useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { cadenceDuSport } from "./sports"
import { supabase } from "./supabase"

/// Les courbes d'une sortie, dessinées à la main.
///
/// En SVG plutôt qu'avec une bibliothèque de graphiques : il s'agit de trois
/// tracés à une seule série, sans axes interactifs ni légende, et le moindre
/// paquet du genre pèse plus que tout le reste de l'application — le même
/// raisonnement qui a sorti MapLibre du chargement initial.

/// Un flux, tel que le Mac le dépose : un objet JSON dont chaque valeur est du
/// base64. Tout est en 4 octets par point — `Float32` — sauf `latlng`, deux
/// `Float64` par point, dont les courbes n'ont que faire.
type Flux = Record<string, string>

function enFlottants(base64: string): Float32Array {
  const binaire = atob(base64)
  const octets = new Uint8Array(binaire.length)
  for (let i = 0; i < binaire.length; i++) octets[i] = binaire.charCodeAt(i)
  // Une vue plutôt qu'un `Float32Array(octets.buffer)` : rien ne garantit que
  // le tampon commence sur un multiple de quatre, et un `Float32Array` posé de
  // travers lève une exception. `DataView` lit à n'importe quelle adresse.
  const vue = new DataView(octets.buffer)
  const valeurs = new Float32Array(Math.floor(octets.length / 4))
  for (let i = 0; i < valeurs.length; i++) valeurs[i] = vue.getFloat32(i * 4, true)
  return valeurs
}

/// Ramène une série à `cible` points en moyennant par tranches.
///
/// Douze mille points pour trois cents pixels, c'est quarante valeurs par
/// pixel : le tracé serait le même et le SVG quarante fois plus lourd. La
/// moyenne plutôt qu'un point sur quarante — un échantillonnage laisserait le
/// dessin sauter d'un pic à un creux selon la tranche tirée.
function reduire(serie: Float32Array, cible: number): number[] {
  if (serie.length <= cible) return Array.from(serie)
  const pas = serie.length / cible
  const sortie: number[] = []
  for (let i = 0; i < cible; i++) {
    const debut = Math.floor(i * pas)
    const fin = Math.min(serie.length, Math.floor((i + 1) * pas))
    let somme = 0
    for (let k = debut; k < fin; k++) somme += serie[k]
    sortie.push(somme / Math.max(1, fin - debut))
  }
  return sortie
}

const LARGEUR = 320
const HAUTEUR = 72

/// Le chemin d'une série, en coordonnées d'un repère de 320 × 72.
///
/// `viewBox` et non des pixels : le SVG s'étire à la largeur qu'on lui donne,
/// et le tracé reste net quelle que soit la densité de l'écran.
function chemin(valeurs: number[], remplir: boolean): string {
  const min = Math.min(...valeurs)
  const max = Math.max(...valeurs)
  const amplitude = max - min || 1
  const x = (i: number) => (i / (valeurs.length - 1)) * LARGEUR
  const y = (v: number) => HAUTEUR - ((v - min) / amplitude) * (HAUTEUR - 4) - 2
  const trace = valeurs.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)} ${y(v).toFixed(1)}`)
  if (!remplir) return trace.join(" ")
  return `${trace.join(" ")} L${LARGEUR} ${HAUTEUR} L0 ${HAUTEUR} Z`
}

type Courbe = {
  clef: string
  titre: string
  unite: string
  couleur: string
  remplir: boolean
}

/// Ce qu'on regarde d'une sortie : le relief la raconte, puis l'effort — FC,
/// puissance, cadence —, chacun absent de lui-même quand son flux l'est. Les
/// couleurs du Mac : rouge pour la FC, orange la puissance, violet la cadence.
const COURBES: Courbe[] = [
  { clef: "altitude", titre: "Altitude", unite: "m", couleur: "#8e8e93", remplir: true },
  { clef: "heartrate", titre: "FC", unite: "bpm", couleur: "#ff3b30", remplir: false },
  { clef: "watts", titre: "Puissance", unite: "W", couleur: "#ff9500", remplir: false },
  { clef: "cadence", titre: "Cadence", unite: "", couleur: "#af52de", remplir: false },
]

const CLEF_CHOIX = "cairn.courbe-effort"

export function Courbes({ activiteUUID, sport }: { activiteUUID: string; sport: string }) {
  // La courbe d'effort montrée, retenue d'une sortie à l'autre sur cet appareil.
  const [choix, setChoix] = useState<string>(() => {
    try {
      return localStorage.getItem(CLEF_CHOIX) ?? "heartrate"
    } catch {
      return "heartrate"
    }
  })
  const choisir = (clef: string) => {
    setChoix(clef)
    try {
      localStorage.setItem(CLEF_CHOIX, clef)
    } catch {
      // Navigation privée : le choix vaut pour la séance.
    }
  }
  const { data, error, isPending } = useQuery({
    queryKey: ["courbes", activiteUUID],
    // Pour toujours quand on les a, tout de suite quand on ne les a pas.
    //
    // Les octets d'un flux ne changent jamais : les garder est gratuit et
    // juste. Mais l'**absence** de flux, elle, change — c'est exactement ce
    // qui arrive quand le téléphone importe une sortie que le Mac complétera
    // plus tard. Ouvrir la fiche avant son passage mettait « pas de flux » en
    // cache pour la session entière, et les courbes ne revenaient plus qu'au
    // redémarrage de l'application. Mesuré le 20 août 2026.
    staleTime: (requete) => (requete.state.data ? Infinity : 0),
    queryFn: async () => {
      const { data: ligne, error: erreurLigne } = await supabase
        .from("activity_streams")
        .select("storage_path, point_count")
        .eq("activity_uuid", activiteUUID)
        .is("deleted_at", null)
        .maybeSingle()
      if (erreurLigne) throw erreurLigne
      if (!ligne?.storage_path) return null

      // Une URL signée plutôt qu'un téléchargement par le client : le seau est
      // privé, et c'est le même chemin que les photos du journal empruntent.
      const { data: signee, error: erreurURL } = await supabase.storage
        .from("streams")
        .createSignedUrl(ligne.storage_path as string, 300)
      if (erreurURL) throw erreurURL

      const reponse = await fetch(signee.signedUrl)
      if (!reponse.ok) throw new Error(`Flux illisible : ${reponse.status}`)
      const flux = (await reponse.json()) as Flux

      const series: Record<string, number[]> = {}
      for (const courbe of COURBES) {
        const brut = flux[courbe.clef]
        if (!brut) continue
        const valeurs = enFlottants(brut)
        // Un flux tout à zéro est un flux que la montre n'a pas rempli : une
        // ligne plate au ras du cadre ne dit rien et occupe autant de place
        // qu'une vraie courbe.
        if (!valeurs.some((v) => v > 0)) continue
        series[courbe.clef] = reduire(valeurs, LARGEUR)
      }
      return series
    },
  })

  if (isPending) return <p className="attenue petit">Chargement des courbes…</p>
  if (error) return <p className="erreur">{(error as Error).message}</p>
  if (!data) return null

  // La cadence dans l'unité du sport : pas par minute à pied, tours à vélo.
  const { facteur, unite } = cadenceDuSport(sport)
  const presentes = COURBES.filter((c) => data[c.clef]?.length).map((c) =>
    c.clef === "cadence"
      ? { ...c, unite, valeurs: data[c.clef].map((v) => v * facteur) }
      : { ...c, valeurs: data[c.clef] },
  )
  if (presentes.length === 0) return null

  // L'altitude seule, puis une seule courbe d'effort et le choix entre elles :
  // trois courbes l'une sous l'autre prenaient deux écrans. Comme les zones.
  const relief = presentes.filter((c) => c.clef === "altitude")
  const effort = presentes.filter((c) => c.clef !== "altitude")
  const montree = effort.find((c) => c.clef === choix) ?? effort[0]
  const affichees = montree ? [...relief, montree] : relief

  return (
    <div className="courbes carte-groupe">
      {affichees.map((courbe) => {
        const valeurs = courbe.valeurs
        const min = Math.round(Math.min(...valeurs))
        const max = Math.round(Math.max(...valeurs))
        const avecChoix = courbe.clef !== "altitude" && effort.length > 1
        return (
          <div className="courbe" key={courbe.clef}>
            <div className="tete-courbe">
              {avecChoix ? (
                <div className="choix-zones" role="group" aria-label="Courbe">
                  {effort.map((c) => (
                    <button
                      key={c.clef}
                      className={c.clef === courbe.clef ? "actif" : ""}
                      onClick={() => choisir(c.clef)}
                    >
                      {c.titre}
                    </button>
                  ))}
                </div>
              ) : (
                <span>{courbe.titre}</span>
              )}
              <span className="attenue petit">
                {min}–{max} {courbe.unite}
              </span>
            </div>
            <svg
              viewBox={`0 0 ${LARGEUR} ${HAUTEUR}`}
              preserveAspectRatio="none"
              role="img"
              aria-label={`${courbe.titre}, de ${min} à ${max} ${courbe.unite}`}
            >
              <path
                d={chemin(valeurs, courbe.remplir)}
                fill={courbe.remplir ? courbe.couleur : "none"}
                fillOpacity={courbe.remplir ? 0.22 : undefined}
                stroke={courbe.couleur}
                strokeWidth={courbe.remplir ? 1 : 1.6}
                strokeLinejoin="round"
                // Sans cela, `preserveAspectRatio="none"` étirerait aussi
                // l'épaisseur du trait, épais à l'horizontale et fin à la
                // verticale.
                vectorEffect="non-scaling-stroke"
              />
            </svg>
          </div>
        )
      })}
    </div>
  )
}
