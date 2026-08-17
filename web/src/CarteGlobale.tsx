import { useEffect, useRef, useState } from "react"
import * as maplibregl from "maplibre-gl"
import "maplibre-gl/dist/maplibre-gl.css"
import { supabase } from "./supabase"
import { traceDepuisBytea } from "./track"
import { bornes, type Filtre, type Zone } from "./criteres"

/// Toutes les traces sur une même carte.
///
/// Chargées par pages et dessinées au fur et à mesure : les 1150 sorties de
/// cette bibliothèque pèsent deux mégaoctets et demi de trace, et les attendre
/// toutes laisserait un écran vide plusieurs secondes sur un réseau mobile.
/// Une page arrivée est une page tracée.
const PAR_PAGE = 150

/// Le fond, identique à celui d'une fiche : c'est la même carte, à une autre
/// échelle, et deux fonds différents pour un même pays se remarqueraient.
const FOND = {
  version: 8 as const,
  sources: {
    ign: {
      type: "raster" as const,
      tiles: [
        "https://data.geopf.fr/wmts?SERVICE=WMTS&VERSION=1.0.0&REQUEST=GetTile" +
          "&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&TILEMATRIXSET=PM" +
          "&FORMAT=image/png&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}",
      ],
      tileSize: 256,
      maxzoom: 19,
      attribution: "© IGN — Géoplateforme",
    },
    traces: {
      type: "geojson" as const,
      data: { type: "FeatureCollection" as const, features: [] },
    },
  },
  layers: [
    { id: "ign", type: "raster" as const, source: "ign" },
    {
      id: "traces",
      type: "line" as const,
      source: "traces",
      layout: { "line-cap": "round" as const, "line-join": "round" as const },
      paint: {
        "line-color": "#e5332a",
        // Fin et translucide : sur un massif parcouru cent fois, des traits
        // opaques feraient une tache rouge. Superposées, les passes répétées
        // ressortent d'elles-mêmes — c'est ce qu'on vient lire sur une carte
        // d'ensemble.
        "line-width": 1.6,
        "line-opacity": 0.55,
      },
    },
  ],
}

type Trait = GeoJSON.Feature<GeoJSON.LineString, { uuid: string }>

/// Le cadrage sur la masse des traces, et non sur leurs extrêmes.
///
/// Douze sorties de cette bibliothèque se trouvent aux îles Salomon, par
/// 166° est : ce sont des séances Zwift, dont le monde virtuel de Watopia y
/// est planté. Les coordonnées sont vraies, Strava ne les marque pas comme
/// intérieures — `is_trainer` est à faux sur les douze, vérifié — et rien ne
/// permet donc de les écarter par un drapeau.
///
/// Les inclure dans le cadrage donnait une carte allant de l'Afrique à
/// l'Australie pour montrer un point rouge sur la France.
///
/// Écartés sur leur distance à la médiane, et non par un centile ni par
/// l'écart interquartile — deux pistes essayées et mesurées avant celle-ci :
///
/// - Les centiles échouent : ces points font 1,75 % du total, donc un centile
///   à 1 % les garde et le 99ᵉ vaut 166,96°.
/// - L'écart interquartile est trop serré : les sorties se concentrant autour
///   de Saint-Étienne, il vaut 0,10°, et trois écarts s'arrêtent à 4,56° —
///   ce qui jetterait la Bretagne, pourtant bien réelle à −1,4°.
///
/// Vingt degrés font deux mille kilomètres : de quoi garder les Alpes et la
/// côte atlantique, pas de quoi garder les îles Salomon. Les traces lointaines
/// restent tracées, il suffit de dézoomer pour les retrouver — c'est le
/// cadrage d'ouverture qu'on choisit ici, pas ce qu'on montre.
const RAYON_DEGRES = 20

function cadrageUtile(traits: Trait[]): maplibregl.LngLatBounds | null {
  const lons: number[] = []
  const lats: number[] = []
  for (const trait of traits) {
    for (const [lon, lat] of trait.geometry.coordinates) {
      lons.push(lon)
      lats.push(lat)
    }
  }
  if (lons.length === 0) return null
  const mediane = (v: number[]) => [...v].sort((a, b) => a - b)[Math.floor(v.length / 2)]
  const centreLon = mediane(lons)
  const centreLat = mediane(lats)

  const limites = new maplibregl.LngLatBounds()
  let retenus = 0
  for (const trait of traits) {
    for (const [lon, lat] of trait.geometry.coordinates) {
      if (Math.abs(lon - centreLon) > RAYON_DEGRES) continue
      if (Math.abs(lat - centreLat) > RAYON_DEGRES) continue
      limites.extend([lon, lat])
      retenus++
    }
  }
  return retenus > 0 ? limites : null
}

/// Applique au chargement les mêmes restrictions que la liste.
///
/// Écrit ici plutôt qu'importé d'`ActivityList` : celui-là est privé à son
/// fichier, et l'exporter ferait dépendre la carte d'un détail de la liste.
/// Deux copies de six lignes valent mieux qu'un couplage.
function restreindre<T>(requete: T, f: Filtre): T {
  let q = requete as any
  const texte = f.recherche.trim()
  if (texte) q = q.ilike("name", `%${texte}%`)
  if (f.sports.length) q = q.in("sport_type_raw", f.sports)
  const { debut, fin } = bornes(f)
  if (debut) q = q.gte("start_local_date", debut.toISOString())
  if (fin) q = q.lt("start_local_date", fin.toISOString())
  if (f.distanceMin != null) q = q.gte("distance", f.distanceMin * 1000)
  if (f.distanceMax != null) q = q.lte("distance", f.distanceMax * 1000)
  if (f.deniveleMin != null) q = q.gte("total_elevation_gain", f.deniveleMin)
  if (f.deniveleMax != null) q = q.lte("total_elevation_gain", f.deniveleMax)
  return q as T
}

export function CarteGlobale({
  filtre,
  onZone,
  onOuvrir,
}: {
  filtre: Filtre
  /// Poser ou retirer la zone du filtre, depuis le cadrage courant.
  onZone: (zone: Zone | null) => void
  onOuvrir: (uuid: string) => void
}) {
  const conteneur = useRef<HTMLDivElement>(null)
  const carte = useRef<maplibregl.Map | null>(null)
  const [chargees, setChargees] = useState(0)
  const [total, setTotal] = useState<number | null>(null)
  const [erreur, setErreur] = useState<string | null>(null)

  useEffect(() => {
    if (!conteneur.current) return
    const instance = new maplibregl.Map({
      container: conteneur.current,
      style: structuredClone(FOND),
      // La France entière : le premier cadrage, avant que la moindre trace ne
      // dise où regarder. Il sera resserré dès la première page.
      center: [2.5, 46.6],
      zoom: 4.6,
    })
    carte.current = instance
    instance.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right")

    // Toucher une trace ouvre sa sortie — c'est la question qu'on pose à une
    // carte d'ensemble : « c'était laquelle, celle-là ? »
    instance.on("click", "traces", (e) => {
      const uuid = e.features?.[0]?.properties?.uuid
      if (typeof uuid === "string") onOuvrir(uuid)
    })
    instance.on("mouseenter", "traces", () => {
      instance.getCanvas().style.cursor = "pointer"
    })
    instance.on("mouseleave", "traces", () => {
      instance.getCanvas().style.cursor = ""
    })

    return () => {
      carte.current = null
      instance.remove()
    }
    // Monté une fois : le filtre change ce qu'on charge, jamais la carte
    // elle-même, et la reconstruire perdrait le cadrage à chaque frappe.
  }, [onOuvrir])

  // Le chargement, relancé à chaque changement de filtre.
  useEffect(() => {
    let annule = false
    const traits: Trait[] = []
    setChargees(0)
    setTotal(null)
    setErreur(null)

    const poser = () => {
      const source = carte.current?.getSource("traces") as maplibregl.GeoJSONSource | undefined
      source?.setData({ type: "FeatureCollection", features: traits })
    }

    ;(async () => {
      try {
        const { count } = await restreindre(
          supabase
            .from("activity")
            .select("uuid", { count: "exact", head: true })
            .is("deleted_at", null)
            .eq("has_track", true),
          filtre,
        )
        if (annule) return
        setTotal(count ?? 0)

        for (let depuis = 0; ; depuis += PAR_PAGE) {
          const { data, error } = await restreindre(
            supabase
              .from("activity")
              .select("uuid, simplified_track")
              .is("deleted_at", null)
              .eq("has_track", true),
            filtre,
          )
            .order("start_local_date", { ascending: false })
            .range(depuis, depuis + PAR_PAGE - 1)
          if (error) throw error
          if (annule) return

          for (const ligne of data as { uuid: string; simplified_track: string | null }[]) {
            const points = traceDepuisBytea(ligne.simplified_track)
            // Deux points au moins : une trace d'un seul point n'est pas une
            // ligne, et MapLibre refuse la géométrie.
            if (points.length < 2) continue
            traits.push({
              type: "Feature",
              properties: { uuid: ligne.uuid },
              geometry: { type: "LineString", coordinates: points },
            })
          }
          poser()
          setChargees(traits.length)

          // Au premier passage seulement : une fois la carte cadrée, elle
          // appartient au doigt, et la recadrer sous lui serait la lui
          // reprendre.
          if (depuis === 0 && traits.length > 0 && carte.current) {
            const limites = cadrageUtile(traits)
            if (limites) carte.current.fitBounds(limites, { padding: 32, animate: false })
          }
          if (data.length < PAR_PAGE) break
        }
      } catch (e) {
        if (!annule) setErreur((e as Error).message)
      }
    })()

    return () => {
      annule = true
    }
  }, [filtre])

  const poserLaZone = () => {
    const limites = carte.current?.getBounds()
    if (!limites) return
    onZone({
      minLat: limites.getSouth(),
      maxLat: limites.getNorth(),
      minLon: limites.getWest(),
      maxLon: limites.getEast(),
    })
  }

  return (
    <div className="carte-globale">
      <div className="toile-carte" ref={conteneur} />
      <div className="pied-carte">
        <span className="attenue petit">
          {erreur
            ? erreur
            : total === null
              ? "Chargement…"
              : chargees < total
                ? `${chargees} / ${total} tracées…`
                : `${chargees} sortie${chargees > 1 ? "s" : ""}`}
        </span>
        {filtre.zone ? (
          <button className="lien" onClick={() => onZone(null)}>
            Retirer la zone
          </button>
        ) : (
          <button className="lien fort" onClick={poserLaZone}>
            Filtrer sur cette zone
          </button>
        )}
      </div>
    </div>
  )
}
