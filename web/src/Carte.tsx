import { useEffect, useRef, useState } from "react"
import * as maplibregl from "maplibre-gl"
import "maplibre-gl/dist/maplibre-gl.css"
import type { Coordonnee } from "./track"
import { ChoixFond } from "./ChoixFond"
import {
  FONDS,
  fondRetenu,
  reliefRetenu,
  retenirFond,
  retenirRelief,
  sourcesDuFond,
  type Fond,
} from "./fonds"

/// La trace d'une sortie, sur le fond choisi.
///
/// La trace est déclarée dans le style de départ plutôt qu'ajoutée après
/// l'évènement `load` : une source posée à la construction suit le même chemin
/// que le fond, sans dépendre du moment où la carte se déclare prête.
function styleAvec(trace: Coordonnee[], fond: Fond) {
  return {
    version: 8 as const,
    sources: {
      ...sourcesDuFond(fond),
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
      { id: "fond", type: "raster" as const, source: "fond" },
      {
        id: "trace",
        type: "line" as const,
        source: "trace",
        layout: { "line-cap": "round" as const, "line-join": "round" as const },
        paint: { "line-color": FONDS[fond].trace, "line-width": 3 },
      },
    ],
  }
}


/// Exécute une action sur la carte une fois son style prêt.
///
/// `setStyle` et `setTerrain` lèvent « Style is not done loading » si on les
/// appelle avant, et les effets de React partent bien avant que MapLibre ait
/// fini de charger le sien.
function quandPret(instance: maplibregl.Map, action: () => void) {
  if (instance.isStyleLoaded()) action()
  else instance.once("load", action)
}

/// `trace` doit être **stable d'un rendu à l'autre** : cet effet en dépend par
/// référence, et un tableau fabriqué dans le JSX de l'appelant en serait un
/// nouveau à chaque fois. La carte se détruirait alors avant d'avoir fini de
/// se dessiner. Voir le `useMemo` d'`ActivityDetail`.
export function Carte({ trace }: { trace: Coordonnee[] }) {
  const conteneur = useRef<HTMLDivElement>(null)
  const carte = useRef<maplibregl.Map | null>(null)
  const [fond, setFond] = useState<Fond>(fondRetenu)
  const [relief, setRelief] = useState(reliefRetenu)
  // Le constructeur a déjà posé le fond et le relief de départ ; les deux
  // effets ci-dessous ne servent qu'aux changements, et rejouer le premier
  // passage réécrirait un style à peine né.
  const premierFond = useRef(true)
  const premierRelief = useRef(true)

  useEffect(() => {
    if (!conteneur.current || trace.length === 0) return

    const limites = trace.reduce(
      (b, point) => b.extend(point),
      new maplibregl.LngLatBounds(trace[0], trace[0]),
    )

    const instance = new maplibregl.Map({
      container: conteneur.current,
      style: styleAvec(trace, fond),
      // Cadré dès la construction plutôt qu'après coup : `fitBounds` calcule
      // son zoom contre la taille du canevas, et celui-ci peut naître avant
      // que le conteneur ait la sienne.
      bounds: limites,
      fitBoundsOptions: { padding: 24, animate: false },
      // Le relief demande un point de vue oblique : vu d'aplomb, un terrain
      // en trois dimensions ressemble exactement à un terrain plat.
      pitch: relief ? 55 : 0,
      // Sans interaction au doigt tant qu'on est à plat : la fiche défile
      // verticalement, et une carte qui capture le geste empêche de lire ce
      // qu'il y a en dessous. En relief, on veut pouvoir tourner autour.
      interactive: relief,
    })
    carte.current = instance
    if (relief) {
      instance.on("load", () => {
        instance.setTerrain({ source: "relief", exaggeration: 1.3 })
      })
    }

    return () => {
      carte.current = null
      instance.remove()
    }
    // `fond` et `relief` sont exclus volontairement : ils se posent sur la
    // carte vivante juste en dessous, sans la reconstruire — la rebâtir
    // perdrait le cadrage à chaque changement.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [trace])

  // Changer de fond réécrit le style, ce qui emporte la trace : elle est
  // redéclarée avec lui.
  useEffect(() => {
    const instance = carte.current
    if (!instance || trace.length === 0) return
    if (premierFond.current) {
      premierFond.current = false
      return
    }
    quandPret(instance, () => {
      instance.setStyle(styleAvec(trace, fond))
      if (relief) {
        instance.once("styledata", () =>
          instance.setTerrain({ source: "relief", exaggeration: 1.3 }),
        )
      }
    })
    retenirFond(fond)
  }, [fond, trace, relief])

  useEffect(() => {
    const instance = carte.current
    if (!instance) return
    if (premierRelief.current) {
      premierRelief.current = false
      return
    }
    quandPret(instance, () => {
      instance.setTerrain(relief ? { source: "relief", exaggeration: 1.3 } : null)
      instance.easeTo({ pitch: relief ? 55 : 0, duration: 400 })
      // Le doigt sert à tourner autour d'un relief ; sur une carte plate il ne
      // servirait qu'à empêcher la fiche de défiler.
      if (relief) {
        instance.dragRotate.enable()
        instance.touchZoomRotate.enable()
      }
    })
    retenirRelief(relief)
  }, [relief])

  if (trace.length === 0) {
    return <p className="attenue petit">Pas de trace pour cette activité.</p>
  }
  return (
    <div className="carte-trace">
      <div className="toile-trace" ref={conteneur} />
      <ChoixFond fond={fond} onFond={setFond} relief={relief} onRelief={setRelief} />
    </div>
  )
}
