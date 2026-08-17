import { useEffect, useRef } from "react"
import * as maplibregl from "maplibre-gl"
import "maplibre-gl/dist/maplibre-gl.css"
import type { Coordonnee } from "./track"

/// Le même fond que l'application macOS emploie pour ses cartes
/// topographiques : Plan IGN v2, servi par la Géoplateforme, accessible sans
/// clé, jusqu'au zoom 19. Les fonds d'Apple n'existent pas dans un navigateur,
/// et c'est de toute façon celui-ci qui porte les courbes de niveau et les
/// sentiers. L'attribution est celle que sa licence exige.
///
/// La trace est déclarée ici, dans le style de départ, plutôt qu'ajoutée après
/// l'évènement `load` : une source posée à la construction suit le même chemin
/// que le fond, sans dépendre du moment où la carte se déclare prête. C'est
/// aussi ce qui évite d'avoir à recopier le style à chaque montage — MapLibre
/// modifie l'objet qu'on lui donne, et une fonction qui en rend un neuf règle
/// la question par construction.
function styleAvec(trace: Coordonnee[]) {
  return {
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
      trace: {
        type: "geojson" as const,
        data: {
          type: "Feature" as const,
          properties: {},
          geometry: { type: "LineString" as const, coordinates: trace },
        },
      },
    },
    layers: [
      { id: "ign", type: "raster" as const, source: "ign" },
      {
        id: "trace",
        type: "line" as const,
        source: "trace",
        layout: { "line-cap": "round" as const, "line-join": "round" as const },
        paint: { "line-color": "#e5332a", "line-width": 3 },
      },
    ],
  }
}

/// `trace` doit être **stable d'un rendu à l'autre** : cet effet en dépend par
/// référence, et un tableau fabriqué dans le JSX de l'appelant en serait un
/// nouveau à chaque fois. La carte se détruirait alors avant d'avoir fini de
/// se dessiner — le fond apparaîtrait, la trace jamais. Voir le `useMemo` de
/// `ActivityDetail`, qui existe pour cette seule raison.
export function Carte({ trace }: { trace: Coordonnee[] }) {
  const conteneur = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!conteneur.current || trace.length === 0) return

    const limites = trace.reduce(
      (b, point) => b.extend(point),
      new maplibregl.LngLatBounds(trace[0], trace[0]),
    )

    const carte = new maplibregl.Map({
      container: conteneur.current,
      style: styleAvec(trace),
      // Cadré dès la construction plutôt qu'après coup : `fitBounds` calcule
      // son zoom contre la taille du canevas, et celui-ci peut naître avant
      // que le conteneur ait la sienne.
      bounds: limites,
      fitBoundsOptions: { padding: 24, animate: false },
      // Sans interaction au doigt : la fiche défile verticalement, et une
      // carte qui capture le geste empêche de lire ce qu'il y a en dessous.
      interactive: false,
    })

    return () => carte.remove()
  }, [trace])

  if (trace.length === 0) {
    return <p className="attenue petit">Pas de trace pour cette activité.</p>
  }
  return <div className="carte-trace" ref={conteneur} />
}
