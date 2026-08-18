import { useEffect, useRef, useState } from "react"
import * as maplibregl from "maplibre-gl"
import "maplibre-gl/dist/maplibre-gl.css"
import type { Coordonnee } from "./track"
import { ChoixFond } from "./ChoixFond"
import {
  coucheDuDessous,
  FONDS,
  fondRetenu,
  peintureDuFond,
  reliefRetenu,
  retenirFond,
  retenirRelief,
  sourcesDuFond,
  styleMonte,
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
      coucheDuDessous(fond),
      {
        id: "fond",
        type: "raster" as const,
        source: "fond",
        paint: peintureDuFond(fond),
      },
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


/// Le rectangle qui contient toute la trace.
function cadrage(trace: Coordonnee[]) {
  return trace.reduce(
    (b, point) => b.extend(point),
    new maplibregl.LngLatBounds(trace[0], trace[0]),
  )
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
  const [plein, setPlein] = useState(false)
  // Le constructeur a déjà posé le fond de départ, et `style.load` le relief ;
  // les deux effets ci-dessous ne servent qu'aux changements, et rejouer le
  // premier passage réécrirait un style à peine né.
  const premierFond = useRef(true)
  const premierRelief = useRef(true)

  useEffect(() => {
    if (!conteneur.current || trace.length === 0) return

    const instance = new maplibregl.Map({
      container: conteneur.current,
      style: styleAvec(trace, fond),
      // Cadré dès la construction plutôt qu'après coup : `fitBounds` calcule
      // son zoom contre la taille du canevas, et celui-ci peut naître avant
      // que le conteneur ait la sienne.
      bounds: cadrage(trace),
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
    // Les drapeaux se remettent à neuf avec la carte : ils disent « premier
    // passage sur cette carte-ci », et non « premier passage du composant ».
    // En développement, React monte deux fois ; des drapeaux survivants
    // laissaient les effets d'en dessous attaquer un style à peine né.
    premierFond.current = true
    premierRelief.current = true
    // Reposé à chaque style — le premier comme celui d'après un changement de
    // fond : `setTerrain` n'a de sens qu'une fois la source d'altitude là.
    // L'attente se fait sur `style.load` et non sur `load`, qui ne se produit
    // qu'une fois dans la vie d'une carte.
    instance.on("style.load", () => {
      if (reliefRetenu()) instance.setTerrain({ source: "relief", exaggeration: 1.3 })
    })

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
    instance.setStyle(styleAvec(trace, fond))
    retenirFond(fond)
  }, [fond, trace])

  useEffect(() => {
    const instance = carte.current
    if (!instance) return
    if (premierRelief.current) {
      premierRelief.current = false
      return
    }
    // Retenu d'abord : c'est la préférence que relit le `style.load` ci-dessus
    // pour reposer le relief sur un style neuf.
    retenirRelief(relief)
    // Sans style monté, rien à poser : le `style.load` qui vient s'en
    // chargera, et `setTerrain` lèverait « Style is not done loading ».
    if (styleMonte(instance)) {
      instance.setTerrain(relief ? { source: "relief", exaggeration: 1.3 } : null)
    }
    instance.easeTo({ pitch: relief ? 55 : 0, duration: 400 })
    // Le doigt sert à tourner autour d'un relief ; sur une carte plate il ne
    // servirait qu'à empêcher la fiche de défiler.
    if (relief) {
      instance.dragRotate.enable()
      instance.touchZoomRotate.enable()
    }
  }, [relief])

  // Le plein écran change la taille de la toile sans que MapLibre le sache :
  // sans `resize`, il continue de dessiner dans l'ancien cadre et la carte
  // s'étire. Le geste s'ouvre en même temps — une carte qui prend l'écran
  // n'aurait aucun sens sans pouvoir s'y déplacer.
  useEffect(() => {
    const instance = carte.current
    if (!instance) return
    instance.resize()
    // Recadré : la trace tenait dans un aperçu de 260 pixels, et la garder au
    // même zoom sur tout l'écran laisserait la moitié de la place inutilisée —
    // c'est justement pour cette place qu'on agrandit.
    instance.fitBounds(cadrage(trace), {
      padding: plein ? 48 : 24,
      animate: false,
      // Le point de vue est conservé : sans lui, le recadrage remet la caméra
      // d'aplomb et le relief disparaît à l'instant même où on agrandit.
      pitch: instance.getPitch(),
      bearing: instance.getBearing(),
    })
    for (const geste of [
      instance.dragPan,
      instance.scrollZoom,
      instance.touchZoomRotate,
      instance.doubleClickZoom,
      instance.keyboard,
    ]) {
      if (plein) geste.enable()
      else geste.disable()
    }
    // Hors relief, la carte redevient un aperçu dans une fiche qui défile.
    if (!plein && relief) {
      instance.dragRotate.enable()
      instance.touchZoomRotate.enable()
    }
  }, [plein, relief, trace])

  // Échap referme, comme partout ailleurs.
  useEffect(() => {
    if (!plein) return
    const touche = (e: KeyboardEvent) => {
      if (e.key === "Escape") setPlein(false)
    }
    addEventListener("keydown", touche)
    // Ce qui défile derrière est figé le temps du plein écran. Trouvé en
    // remontant depuis la carte, et non par un sélecteur : le conteneur qui
    // défile appartient au châssis, pas à ce fichier, et le nommer ici ferait
    // dépendre la carte d'un détail d'ailleurs.
    let parent = conteneur.current?.parentElement ?? null
    while (parent && !/auto|scroll/.test(getComputedStyle(parent).overflowY)) {
      parent = parent.parentElement
    }
    const avant = parent?.style.overflow
    if (parent) parent.style.overflow = "hidden"
    return () => {
      removeEventListener("keydown", touche)
      if (parent) parent.style.overflow = avant ?? ""
    }
  }, [plein])

  if (trace.length === 0) {
    return <p className="attenue petit">Pas de trace pour cette activité.</p>
  }
  return (
    <div className={plein ? "carte-trace plein" : "carte-trace"}>
      <div className="toile-trace" ref={conteneur} />
      <ChoixFond
        fond={fond}
        onFond={setFond}
        relief={relief}
        onRelief={setRelief}
        plein={plein}
        onPlein={setPlein}
      />
    </div>
  )
}
