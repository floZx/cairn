import { useEffect, useRef } from "react"
import * as maplibregl from "maplibre-gl"
import "maplibre-gl/dist/maplibre-gl.css"
import type { Coordonnee } from "./track"

/// Le même fond que l'application macOS emploie pour ses cartes
/// topographiques : Plan IGN v2, servi par la Géoplateforme, accessible sans
/// clé, jusqu'au zoom 19. Les fonds d'Apple n'existent pas dans un navigateur,
/// et c'est de toute façon celui-ci qui porte les courbes de niveau et les
/// sentiers. L'attribution est celle que sa licence exige.
const fond = {
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
  },
  layers: [{ id: "ign", type: "raster" as const, source: "ign" }],
}

export function Carte({ trace }: { trace: Coordonnee[] }) {
  const conteneur = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!conteneur.current || trace.length === 0) return

    const carte = new maplibregl.Map({
      container: conteneur.current,
      style: fond,
      // Sans interaction au doigt : la fiche défile verticalement, et une
      // carte qui capture le geste empêche de lire ce qu'il y a en dessous.
      // Un appui la réveille — voir plus bas.
      interactive: false,
    })

    carte.on("load", () => {
      carte.addSource("trace", {
        type: "geojson",
        data: {
          type: "Feature",
          properties: {},
          geometry: { type: "LineString", coordinates: trace },
        },
      })
      carte.addLayer({
        id: "trace",
        type: "line",
        source: "trace",
        layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-color": "#e5332a", "line-width": 3 },
      })

      const limites = trace.reduce(
        (b, point) => b.extend(point),
        new maplibregl.LngLatBounds(trace[0], trace[0]),
      )
      carte.fitBounds(limites, { padding: 24, animate: false })
    })

    return () => carte.remove()
  }, [trace])

  if (trace.length === 0) {
    return <p className="attenue petit">Pas de trace pour cette activité.</p>
  }
  return <div className="carte-trace" ref={conteneur} />
}
