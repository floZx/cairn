import { useCallback, useEffect, useRef, useState } from "react"
import * as maplibregl from "maplibre-gl"
import "maplibre-gl/dist/maplibre-gl.css"
import { useQuery } from "@tanstack/react-query"
import { supabase } from "./supabase"
import { IconeSport } from "./IconeSport"
import { dateCourte, distance as formatDistance, duree as formatDuree } from "./format"
import { traceDepuisBytea, type Coordonnee } from "./track"
import { distanceEntre, memeParcours, signature } from "./parcours"
import { bornes, type Filtre, type Zone } from "./criteres"
import { ChoixFond } from "./ChoixFond"
import {
  coucheDuDessous,
  fondRetenu,
  peintureDuFond,
  reliefRetenu,
  retenirFond,
  retenirRelief,
  sourcesDuFond,
  styleMonte,
  type Fond,
} from "./fonds"

/// Toutes les traces sur une même carte.
///
/// Chargées par pages et dessinées au fur et à mesure : les 1150 sorties de
/// cette bibliothèque pèsent deux mégaoctets et demi de trace, et les attendre
/// toutes laisserait un écran vide plusieurs secondes sur un réseau mobile.
/// Une page arrivée est une page tracée.
const PAR_PAGE = 150

/// Les huit teintes qui tournent d'une trace à l'autre — le `TrackPalette` du
/// Mac, et pour la même raison que là-bas : distinguer les traces entre elles.
///
/// C'est le vrai service d'une carte d'ensemble. Deux trails voisins tracés de
/// la même couleur, partageant un bout de chemin, se lisent comme une seule
/// sortie ; deux teintes différentes les séparent d'un coup d'œil.
///
/// Huit et pas plus : au-delà, les teintes cessent d'être comparables à l'œil,
/// et deux verts presque semblables tromperaient davantage qu'une répétition,
/// qui elle est évidente et sans conséquence.
///
/// Lues dans la feuille de style plutôt que recopiées ici : chacune a une
/// valeur claire et une sombre, et MapLibre ne sait pas lire une variable CSS.
const TEINTES = 8

function teintesDesTraces(): string[] {
  const feuille = getComputedStyle(document.documentElement)
  return Array.from(
    { length: TEINTES },
    (_, i) => feuille.getPropertyValue(`--trace-${i}`).trim() || "#0a84ff",
  )
}

/// Le fond, celui-là même que la fiche emploie : c'est la même carte à une
/// autre échelle, et deux fonds différents pour un même pays se
/// remarqueraient. Le choix est d'ailleurs retenu en commun.
function styleAvec(fond: Fond) {
  return {
  version: 8 as const,
  sources: {
    ...sourcesDuFond(fond),
    traces: {
      type: "geojson" as const,
      data: { type: "FeatureCollection" as const, features: [] },
    },
    zone: {
      type: "geojson" as const,
      data: { type: "FeatureCollection" as const, features: [] },
    },
    // Les passages du parcours touché, et la trace touchée elle-même.
    //
    // Deux sources à part plutôt que deux filtres sur la source commune : un
    // filtre `["in", …]` posé sur les six cent soixante-treize traces empêchait
    // la carte entière de se peindre — écran noir, aucune erreur, les tuiles
    // pourtant reçues. Mesuré par bissection le 19 août 2026. Recopier une
    // poignée de lignes coûte moins cher que de filtrer les autres, de toute
    // façon.
    jumelles: {
      type: "geojson" as const,
      data: { type: "FeatureCollection" as const, features: [] },
    },
    touchee: {
      type: "geojson" as const,
      data: { type: "FeatureCollection" as const, features: [] },
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
    // Sous les traces : la zone est un cadre, pas un calque qui les couvre.
    {
      id: "zone-fond",
      type: "fill" as const,
      source: "zone",
      paint: { "fill-color": "#007aff", "fill-opacity": 0.08 },
    },
    {
      id: "zone-bord",
      type: "line" as const,
      source: "zone",
      paint: { "line-color": "#007aff", "line-width": 1.6, "line-dasharray": [3, 2] },
    },
    // Sous les traces et invisible : de quoi toucher une trace avec un doigt.
    //
    // Les traits font 1,6 px de large — c'est ce qui rend une carte de mille
    // sorties lisible — et viser 1,6 px sur un téléphone est un jeu d'adresse.
    // MapLibre teste le clic sur la géométrie **rendue**, donc élargir la
    // cible demande une couche large ; transparente, elle ne change rien à ce
    // qu'on voit. Vingt pixels : le doigt d'Apple fait 44 points, mais une
    // cible aussi large attraperait la voisine sur un massif dense.
    {
      id: "traces-touche",
      type: "line" as const,
      source: "traces",
      layout: { "line-cap": "round" as const, "line-join": "round" as const },
      paint: { "line-color": "#000", "line-width": 20, "line-opacity": 0 },
    },
    {
      id: "traces",
      type: "line" as const,
      source: "traces",
      layout: { "line-cap": "round" as const, "line-join": "round" as const },
      paint: {
        // Portée par la trace elle-même : la couleur dépend de son rang, que
        // seul le chargement connaît.
        "line-color": ["get", "couleur"] as maplibregl.ExpressionSpecification,
        // Fin et translucide : sur un massif parcouru cent fois, des traits
        // opaques feraient une tache. Superposées, les passes répétées
        // ressortent d'elles-mêmes — c'est ce qu'on vient lire sur une carte
        // d'ensemble.
        "line-width": 1.6,
        "line-opacity": 0.55,
      },
    },
    // Les passages sur le parcours touché, par-dessus tout le reste.
    //
    // Une couche à part plutôt qu'une couleur changée sur la couche des
    // traces : celle-ci en porte des centaines, et une expression qui teste
    // l'appartenance à une liste se réévalue pour chacune à chaque image. Ici
    // le filtre écarte tout sauf une poignée, et le reste ne coûte rien.
    //
    // Toutes de la même teinte, celle de la trace touchée : c'est ce qui les
    // donne à lire comme un seul itinéraire refait, là où la palette de la
    // carte sert justement à séparer les voisines.
    {
      id: "traces-jumelles",
      type: "line" as const,
      source: "jumelles",
      layout: { "line-cap": "round" as const, "line-join": "round" as const },
      paint: {
        "line-color": "#ffffff",
        "line-width": 2.6,
        "line-opacity": 0.9,
      },
    },
    // Celle qu'on a touchée, plus épaisse encore : dans un faisceau de
    // quarante passages, savoir laquelle on tient est la première chose.
    {
      id: "trace-touchee",
      type: "line" as const,
      source: "touchee",
      layout: { "line-cap": "round" as const, "line-join": "round" as const },
      paint: {
        "line-color": "#ffffff",
        "line-width": 4,
        "line-opacity": 1,
      },
    },
  ],
  }
}

/// Le filtre réduit à une chaîne, pour savoir s'il a vraiment changé.
///
/// `JSON.stringify` suffit ici : les champs sont des scalaires, un tableau de
/// sports et une zone rectangulaire, et l'objet se reconstruit toujours par
/// diffusion du précédent — l'ordre des clés ne bouge donc pas.
function empreinteDuFiltre(f: Filtre): string {
  return JSON.stringify(f)
}

/// La longueur d'une trace, en mètres.
///
/// Calculée sur la géométrie déjà chargée plutôt que demandée à la base :
/// la carte tient les mille traces en mémoire, et `memeParcours` n'a besoin
/// que d'un ordre de grandeur pour sa porte des 10 %.
function longueurDe(points: Coordonnee[]): number {
  let total = 0
  for (let i = 0; i < points.length - 1; i++) total += distanceEntre(points[i], points[i + 1])
  return total
}

type Trait = GeoJSON.Feature<GeoJSON.LineString, { uuid: string; couleur: string }>

/// Où la carte était quand on l'a quittée.
///
/// Hors de React, et hors du composant : ouvrir une sortie démonte la carte —
/// la fiche prend tout l'écran — et le retour en reconstruit une neuve, qui
/// repartait de la France entière. On dézoomait, on cherchait sa trace, on la
/// touchait, on revenait, et tout était à refaire.
///
/// Une variable de module plutôt que `sessionStorage` : ce cadrage vaut pour
/// la session en cours, pas pour la prochaine ouverture de l'application, où
/// repartir de la vue d'ensemble est ce qu'on veut.
let cadrageRetenu: {
  centre: [number, number]
  zoom: number
  pitch: number
  bearing: number
} | null = null

/// Les traces déjà chargées, par filtre, le temps de la session.
///
/// Sans elles, chaque passage sur la carte redemandait les sept cents traces
/// page par page, et la carte se remplissait sous les yeux à chaque fois —
/// signalé. Une variable de module comme `cadrageRetenu` : elle vaut pour la
/// session, pas pour la prochaine ouverture de l'application.
///
/// Montrées tout de suite, puis redemandées en silence : une sortie arrivée
/// entre-temps apparaît quand même, sans que la carte se vide pour autant.
/// Rien de persistant, et c'est la règle de `vite.config.ts` — une réponse de
/// Supabase gardée d'une ouverture à l'autre serait un journal périmé.
const tracesRetenues = new Map<string, { traits: Trait[]; total: number }>()

/// Ce qu'une sortie apporte à la carte : son identité et sa trace.
type Ligne = { uuid: string; simplified_track: string | null }

/// Le rectangle d'une zone, comme MapLibre l'attend : un anneau fermé, dont
/// le dernier point répète le premier.
function rectangle(z: Zone): GeoJSON.Feature<GeoJSON.Polygon> {
  return {
    type: "Feature",
    properties: {},
    geometry: {
      type: "Polygon",
      coordinates: [
        [
          [z.minLon, z.minLat],
          [z.maxLon, z.minLat],
          [z.maxLon, z.maxLat],
          [z.minLon, z.maxLat],
          [z.minLon, z.minLat],
        ],
      ],
    },
  }
}

/// Le cadrage d'ouverture : là où l'on sort le plus, pas tout ce qu'on a fait.
///
/// Sur le centre de chaque sortie, on garde celles qui tombent entre le 10ᵉ
/// et le 90ᵉ centile en longitude comme en latitude — le cœur de la
/// bibliothèque, quatre sorties sur cinq environ —, puis on cadre sur leurs
/// traces entières, pour qu'aucune ne sorte du bord.
///
/// Compté par sortie et non par point : une longue sortie de montagne pèse
/// autant qu'un footing, et c'est la fréquence qu'on veut voir, pas la
/// distance parcourue.
///
/// Ce que ça écarte du cadre, et c'est voulu : les vacances, la Bretagne, et
/// les douze séances Zwift plantées aux îles Salomon par 166° est, que rien ne
/// permet de reconnaître autrement (`is_trainer` est à faux sur les douze).
/// Tout reste tracé : un pincement de doigt les retrouve. Le cadrage précédent
/// gardait tout ce qui tenait dans vingt degrés autour de la médiane, et
/// ouvrait sur la moitié de la France pour une masse de traces autour de
/// Saint-Étienne — signalé, et c'est ce choix-ci qui a été retenu.
function cadrageUtile(traits: Trait[]): maplibregl.LngLatBounds | null {
  const centres = traits
    .map((trait) => {
      const points = trait.geometry.coordinates
      if (points.length === 0) return null
      let lon = 0
      let lat = 0
      for (const [x, y] of points) {
        lon += x
        lat += y
      }
      return { trait, lon: lon / points.length, lat: lat / points.length }
    })
    .filter((c): c is NonNullable<typeof c> => c !== null)
  if (centres.length === 0) return null

  const centile = (valeurs: number[], q: number) => {
    const tries = [...valeurs].sort((x, y) => x - y)
    return tries[Math.min(tries.length - 1, Math.floor(q * tries.length))]
  }
  const lons = centres.map((c) => c.lon)
  const lats = centres.map((c) => c.lat)
  const [lonMin, lonMax] = [centile(lons, 0.1), centile(lons, 0.9)]
  const [latMin, latMax] = [centile(lats, 0.1), centile(lats, 0.9)]

  const limites = new maplibregl.LngLatBounds()
  let retenues = 0
  for (const c of centres) {
    if (c.lon < lonMin || c.lon > lonMax || c.lat < latMin || c.lat > latMax) continue
    for (const point of c.trait.geometry.coordinates) limites.extend(point as [number, number])
    retenues++
  }
  return retenues > 0 ? limites : null
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
  /// Les traces déjà chargées, gardées hors de React.
  ///
  /// Un changement de fond réécrit le style, sources comprises, et les emporte
  /// avec lui ; c'est d'ici qu'elles reviennent, sans rappeler le réseau pour
  /// deux mégaoctets et demi déjà reçus.
  const traits = useRef<Trait[]>([])
  const [chargees, setChargees] = useState(0)
  const [total, setTotal] = useState<number | null>(null)
  const [erreur, setErreur] = useState<string | null>(null)
  /// La trace touchée et tous ses autres passages.
  const [choisi, setChoisi] = useState<{ uuid: string; passages: string[] } | null>(null)

  // Toute la hauteur qui reste, jusqu'au bord de l'écran : la carte passe sous
  // la barre d'onglets comme sous celle de Plans, au lieu de s'arrêter dans une
  // carte aux coins arrondis avec un vide dessous. Mesurée plutôt qu'écrite en
  // CSS : ce qui la précède — titre, recherche, résumé d'un filtre — n'a pas
  // de hauteur fixe. La page, elle, ne défile plus : la carte prend le doigt.
  useEffect(() => {
    const toile = conteneur.current
    if (!toile) return
    const poser = () => {
      const haut = toile.getBoundingClientRect().top
      toile.style.height = `${Math.max(240, innerHeight - haut)}px`
      carte.current?.resize()
    }
    poser()
    const image = requestAnimationFrame(poser)
    addEventListener("resize", poser)
    return () => {
      cancelAnimationFrame(image)
      removeEventListener("resize", poser)
    }
  }, [])
  /// Lisible depuis les rappels de la carte, montés une fois pour toutes.
  const choisiRef = useRef(choisi)
  choisiRef.current = choisi
  /// Les signatures déjà calculées, une par sortie.
  ///
  /// Reconnaître un parcours parmi mille demande de rééchantillonner chaque
  /// trace ; le refaire à chaque doigt posé se sentirait. Elles ne bougent
  /// jamais — une trace enregistrée ne change plus.
  const signatures = useRef(new Map<string, { forme: Coordonnee[]; longueur: number }>())
  const [fond, setFond] = useState<Fond>(fondRetenu)
  const [relief, setRelief] = useState(reliefRetenu)
  const premierFond = useRef(true)
  const premierRelief = useRef(true)
  /// Vrai quand cette carte-ci a rouvert là où on l'avait laissée — et qu'il
  /// ne faut donc pas la recadrer sous le doigt.
  ///
  /// Retombe à faux quand le filtre change, et à ce moment-là seulement :
  /// filtrer sur le trail doit recadrer sur ce qu'il reste, comme avant.
  const cadreRestaure = useRef(cadrageRetenu !== null)
  const filtrePrecedent = useRef(empreinteDuFiltre(filtre))
  // La zone du filtre, lisible depuis le rhabillage sans le redéfinir.
  const zoneCourante = useRef(filtre.zone)
  zoneCourante.current = filtre.zone

  /// Les autres passages sur le parcours d'une trace, elle comprise.
  ///
  /// Cherché parmi les traces déjà chargées, sans un aller-retour de plus : la
  /// carte les tient toutes, et c'est précisément ce qu'il faut pour comparer
  /// des formes — ce que Postgres, lui, ne sait pas faire.
  const jumellesDe = useCallback((uuid: string): string[] => {
    const formeDe = (trait: Trait) => {
      const connue = signatures.current.get(trait.properties.uuid)
      if (connue) return connue
      const points = trait.geometry.coordinates as Coordonnee[]
      const calculee = {
        forme: signature(points) ?? [],
        longueur: longueurDe(points),
      }
      signatures.current.set(trait.properties.uuid, calculee)
      return calculee
    }

    const source = traits.current.find((t) => t.properties.uuid === uuid)
    if (!source) return [uuid]
    const reference = formeDe(source)
    if (reference.forme.length === 0) return [uuid]

    const trouves = [uuid]
    for (const trait of traits.current) {
      if (trait.properties.uuid === uuid) continue
      const candidate = formeDe(trait)
      if (candidate.forme.length === 0) continue
      if (memeParcours(reference.forme, candidate.forme, reference.longueur, candidate.longueur)) {
        trouves.push(trait.properties.uuid)
      }
    }
    return trouves
  }, [])

  /// Applique la mise en avant : les jumelles allumées, le reste en retrait.
  ///
  /// Séparée du `setState` pour servir aussi au rhabillage — un changement de
  /// fond réécrit le style, filtres compris.
  const eclairer = useCallback(
    (selection: { uuid: string; passages: string[] } | null) => {
      const instance = carte.current
      const jumelles = instance?.getSource("jumelles") as maplibregl.GeoJSONSource | undefined
      const touchee = instance?.getSource("touchee") as maplibregl.GeoJSONSource | undefined
      if (!instance || !jumelles || !touchee) return

      const retenus = new Set(selection?.passages ?? [])
      jumelles.setData({
        type: "FeatureCollection",
        features: traits.current.filter((t) => retenus.has(t.properties.uuid)),
      })
      touchee.setData({
        type: "FeatureCollection",
        features: selection
          ? traits.current.filter((t) => t.properties.uuid === selection.uuid)
          : [],
      })
      // Le reste s'efface sans disparaître : ce qui compte est de voir où le
      // parcours choisi passe **par rapport** aux autres.
      instance.setPaintProperty("traces", "line-opacity", selection ? 0.16 : 0.55)
    },
    [],
  )

  /// Repose sur un style neuf tout ce qu'il n'apporte pas lui-même : le
  /// relief, les traces déjà chargées, le cadre de la zone.
  ///
  /// Branché sur `style.load`, qui se produit à chaque style — le premier
  /// comme celui d'après un changement de fond — et qui est le seul moment où
  /// les sources existent à coup sûr. `isStyleLoaded()` ne convenait pas : il
  /// tient compte des tuiles en vol, et celles du relief n'arrêtent jamais
  /// d'arriver, si bien qu'il restait faux et que rien ne se reposait.
  const rehabiller = useCallback(() => {
    const instance = carte.current
    if (!instance) return
    if (reliefRetenu()) instance.setTerrain({ source: "relief", exaggeration: 1.3 })
    const traces = instance.getSource("traces") as maplibregl.GeoJSONSource | undefined
    traces?.setData({ type: "FeatureCollection", features: traits.current })
    const zone = instance.getSource("zone") as maplibregl.GeoJSONSource | undefined
    zone?.setData({
      type: "FeatureCollection",
      features: zoneCourante.current ? [rectangle(zoneCourante.current)] : [],
    })
    eclairer(choisiRef.current)
  }, [eclairer])

  useEffect(() => {
    if (!conteneur.current) return
    const instance = new maplibregl.Map({
      container: conteneur.current,
      style: styleAvec(fondRetenu()),
      // Là où on avait laissé la carte, sinon la France entière : le premier
      // cadrage, avant que la moindre trace ne dise où regarder. Il sera
      // resserré dès la première page.
      center: cadrageRetenu?.centre ?? [2.5, 46.6],
      zoom: cadrageRetenu?.zoom ?? 4.6,
      bearing: cadrageRetenu?.bearing ?? 0,
      // Le relief demande un point de vue oblique : vu d'aplomb, un terrain en
      // trois dimensions ressemble exactement à un terrain plat. Posé dès la
      // construction, sans quoi revenir sur la carte la rendait plate alors
      // que « Relief » restait coché.
      pitch: cadrageRetenu?.pitch ?? (reliefRetenu() ? 55 : 0),
    })
    carte.current = instance
    // Les drapeaux se remettent à neuf avec la carte : ils disent « premier
    // passage sur cette carte-ci », et non « premier passage du composant ».
    // En développement, React monte deux fois ; des drapeaux survivants
    // laissaient les effets d'en dessous attaquer un style à peine né.
    premierFond.current = true
    premierRelief.current = true
    // Une carte qui échoue en silence est le pire des cas : l'écran reste
    // noir, la console vide, et on cherche du côté du réseau. MapLibre sait
    // ce qui ne va pas — un style refusé, une source introuvable — encore
    // faut-il le lui demander.
    instance.on("error", (e) => {
      setErreur(e.error?.message ?? "La carte n'a pas pu se construire.")
    })
    instance.on("style.load", rehabiller)

    // Retenu à chaque mouvement fini, y compris le cadrage automatique de la
    // première page : ce que l'écran montre est ce qu'on doit retrouver.
    const retenirLeCadrage = () => {
      const centre = instance.getCenter()
      cadrageRetenu = {
        centre: [centre.lng, centre.lat],
        zoom: instance.getZoom(),
        pitch: instance.getPitch(),
        bearing: instance.getBearing(),
      }
    }
    instance.on("moveend", retenirLeCadrage)
    instance.on("zoomend", retenirLeCadrage)

    // Toucher une trace ouvre sa sortie — c'est la question qu'on pose à une
    // carte d'ensemble : « c'était laquelle, celle-là ? »
    // Toucher choisit, retoucher ouvre.
    //
    // Ouvrir du premier coup coûtait cher pour rien : sur un massif parcouru
    // cent fois on tombe rarement sur la bonne trace du premier essai, et la
    // fiche s'ouvrait pour être aussitôt refermée. Le premier doigt allume le
    // parcours et ses autres passages — ce qu'on venait voir la plupart du
    // temps — et le second, ou la carte du bas, ouvre la sortie.
    instance.on("click", "traces-touche", (e) => {
      const uuid = e.features?.[0]?.properties?.uuid
      if (typeof uuid !== "string") return
      if (choisiRef.current?.uuid === uuid) {
        onOuvrir(uuid)
        return
      }
      const selection = { uuid, passages: jumellesDe(uuid) }
      choisiRef.current = selection
      setChoisi(selection)
      eclairer(selection)
    })

    // Toucher ailleurs éteint : sans quoi la mise en avant survivrait à
    // l'intérêt qu'on lui porte, et la carte resterait à moitié effacée.
    instance.on("click", (e) => {
      const dessus = instance.queryRenderedFeatures(e.point, { layers: ["traces-touche"] })
      if (dessus.length > 0) return
      choisiRef.current = null
      setChoisi(null)
      eclairer(null)
    })
    instance.on("mouseenter", "traces-touche", () => {
      instance.getCanvas().style.cursor = "pointer"
    })
    instance.on("mouseleave", "traces-touche", () => {
      instance.getCanvas().style.cursor = ""
    })

    return () => {
      carte.current = null
      instance.remove()
    }
    // Monté une fois : le filtre change ce qu'on charge, jamais la carte
    // elle-même, et la reconstruire perdrait le cadrage à chaque frappe.
  }, [onOuvrir, rehabiller, jumellesDe, eclairer])

  // La zone, dessinée dès qu'elle change — et au montage, ce qui est le cas
  // qui manquait : revenir sur la carte après avoir filtré ne la montrait pas.
  useEffect(() => {
    // Sans source, c'est que le style n'est pas encore là : le rhabillage la
    // posera. Écrire dans le vide serait sans effet et sans erreur, ce qui est
    // le pire des deux.
    const source = carte.current?.getSource("zone") as maplibregl.GeoJSONSource | undefined
    source?.setData({
      type: "FeatureCollection",
      features: filtre.zone ? [rectangle(filtre.zone)] : [],
    })
  }, [filtre.zone])

  // Changer de fond réécrit le style, ce qui emporte le relief, les traces et
  // la zone ; `rehabiller` les repose au `style.load` qui suit.
  useEffect(() => {
    const instance = carte.current
    if (!instance) return
    if (premierFond.current) {
      premierFond.current = false
      return
    }
    instance.setStyle(styleAvec(fond))
    retenirFond(fond)
  }, [fond])

  useEffect(() => {
    const instance = carte.current
    if (!instance) return
    if (premierRelief.current) {
      premierRelief.current = false
      return
    }
    // Retenu d'abord : `rehabiller` relit la préférence pour reposer le relief
    // sur un style neuf, et la lui laisser périmée le poserait à l'envers.
    retenirRelief(relief)
    // Sans style monté, rien à poser : le `style.load` qui vient s'en
    // chargera, et `setTerrain` lèverait « Style is not done loading ».
    if (styleMonte(instance)) {
      instance.setTerrain(relief ? { source: "relief", exaggeration: 1.3 } : null)
    }
    instance.easeTo({ pitch: relief ? 55 : 0, duration: 400 })
  }, [relief])

  // Le chargement, relancé à chaque changement de filtre.
  useEffect(() => {
    let annule = false
    // Comparé plutôt que consommé : en développement React monte deux fois,
    // et un drapeau lu-puis-effacé laissait le second passage recadrer — le
    // cadrage retrouvé tenait une fraction de seconde. Mesuré.
    //
    // Et comparé **par valeur**, pas par identité. La liste republie un filtre
    // au même contenu trois cents millisecondes après son montage — le délai
    // de la saisie de recherche, qui repart sur `{ ...f, recherche }` — donc
    // au retour d'une fiche l'objet était neuf sans que rien n'ait changé, et
    // la carte se recadrait. C'est ce que le journal a montré :
    // « restaure=false filtreNeuf=true » sur le chemin du retour, là où un
    // changement d'onglet donnait « filtreNeuf=false ».
    const empreinte = empreinteDuFiltre(filtre)
    if (filtrePrecedent.current !== empreinte) {
      filtrePrecedent.current = empreinte
      cadreRestaure.current = false
    }
    const teintes = teintesDesTraces()
    const enMemoire = tracesRetenues.get(empreinte)
    setErreur(null)
    if (enMemoire) {
      traits.current = enMemoire.traits
      setTotal(enMemoire.total)
      setChargees(enMemoire.traits.length)
      const source = carte.current?.getSource("traces") as maplibregl.GeoJSONSource | undefined
      source?.setData({ type: "FeatureCollection", features: traits.current })
      if (carte.current && !cadreRestaure.current && traits.current.length > 0) {
        const limites = filtre.zone
          ? new maplibregl.LngLatBounds(
              [filtre.zone.minLon, filtre.zone.minLat],
              [filtre.zone.maxLon, filtre.zone.maxLat],
            )
          : cadrageUtile(traits.current)
        if (limites) carte.current.fitBounds(limites, { padding: 32, animate: false })
      }
    } else {
      traits.current = []
      setChargees(0)
      setTotal(null)
    }
    /// Ce que ce passage-ci charge. Sans rien en mémoire, c'est la carte
    /// elle-même qui se remplit au fil des pages ; avec, le lot se prépare à
    /// part et ne remplace ce qui est affiché qu'une fois complet.
    const charges: Trait[] = enMemoire ? [] : traits.current

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
        if (!enMemoire) setTotal(count ?? 0)

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

          for (const ligne of data as Ligne[]) {
            const points = traceDepuisBytea(ligne.simplified_track)
            // Deux points au moins : une trace d'un seul point n'est pas une
            // ligne, et MapLibre refuse la géométrie.
            if (points.length < 2) continue
            charges.push({
              type: "Feature",
              properties: {
                uuid: ligne.uuid,
                // Le rang de la trace, pas son sport : la palette sert à
                // séparer des voisines, et deux sorties du même sport sont
                // justement celles qu'on risque de confondre.
                couleur: teintes[charges.length % teintes.length],
              },
              geometry: { type: "LineString", coordinates: points },
            })
          }
          const source = carte.current?.getSource("traces") as
            | maplibregl.GeoJSONSource
            | undefined
          if (!enMemoire) {
            source?.setData({ type: "FeatureCollection", features: traits.current })
            setChargees(traits.current.length)
          }

          // Au premier passage seulement : une fois la carte cadrée, elle
          // appartient au doigt, et la recadrer sous lui serait la lui
          // reprendre.
          //
          // Et jamais quand on revient d'une fiche : le cadrage retrouvé est
          // précisément celui qu'on ne veut pas voir remplacé.
          if (!enMemoire && depuis === 0 && traits.current.length > 0 && carte.current && !cadreRestaure.current) {
            // Sur la zone quand il y en a une : c'est elle qu'on revient voir,
            // et cadrer sur les traces qu'elle a retenues donnerait un cadre
            // plus serré qu'elle, dont le bord sortirait de l'écran.
            const limites = filtre.zone
              ? new maplibregl.LngLatBounds(
                  [filtre.zone.minLon, filtre.zone.minLat],
                  [filtre.zone.maxLon, filtre.zone.maxLat],
                )
              : cadrageUtile(traits.current)
            if (limites) carte.current.fitBounds(limites, { padding: 32, animate: false })
          }
          if (data.length < PAR_PAGE) break
        }
        if (annule) return
        tracesRetenues.set(empreinte, { traits: charges, total: count ?? charges.length })
        if (enMemoire) {
          // La relecture silencieuse est finie : elle remplace d'un coup ce
          // qui était affiché, sans passer par une carte vide.
          traits.current = charges
          const source = carte.current?.getSource("traces") as
            | maplibregl.GeoJSONSource
            | undefined
          source?.setData({ type: "FeatureCollection", features: traits.current })
          setChargees(charges.length)
          setTotal(count ?? charges.length)
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
      <div className="toile-carte" ref={conteneur}>
        <ChoixFond fond={fond} onFond={setFond} relief={relief} onRelief={setRelief} />
        {choisi && (
          <FicheTouchee
            uuid={choisi.uuid}
            passages={choisi.passages.length}
            onOuvrir={() => onOuvrir(choisi.uuid)}
            onFermer={() => {
              choisiRef.current = null
              setChoisi(null)
              eclairer(null)
            }}
          />
        )}
      </div>
      {/* Une capsule de verre au-dessus des onglets, et non une ligne sous la
          carte : la carte va maintenant jusqu'en bas. Cachée quand une trace
          est touchée, sa fiche prend la même place. */}
      <div className={choisi ? "pied-carte matiere cache" : "pied-carte matiere"}>
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

/// La carte de la trace touchée, posée au bas de la carte.
///
/// Elle dit trois choses et pas une de plus : de quelle sortie il s'agit,
/// combien de fois ce parcours a été fait, et comment l'ouvrir. Le reste est
/// dans la fiche, à un doigt de là.
function FicheTouchee({
  uuid,
  passages,
  onOuvrir,
  onFermer,
}: {
  uuid: string
  passages: number
  onOuvrir: () => void
  onFermer: () => void
}) {
  const { data } = useQuery({
    queryKey: ["activite-touchee", uuid],
    staleTime: 5 * 60 * 1000,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("activity")
        .select("name, sport_type_raw, start_local_date, distance, moving_time")
        .eq("uuid", uuid)
        .single()
      if (error) throw error
      return data as {
        name: string
        sport_type_raw: string
        start_local_date: string
        distance: number
        moving_time: number
      }
    },
  })

  return (
    <div className="fiche-touchee matiere">
      <button className="fermer-fiche" onClick={onFermer} aria-label="Ne plus montrer">
        ×
      </button>
      <button className="corps-fiche" onClick={onOuvrir}>
        <span className="tete-touchee">
          {data && <IconeSport sport={data.sport_type_raw} taille={20} />}
          <span className="nom-touchee">{data?.name ?? "…"}</span>
        </span>
        {data && (
          <span className="attenue petit">
            {dateCourte(data.start_local_date)} · {formatDistance(data.distance)} ·{" "}
            {formatDuree(data.moving_time)}
          </span>
        )}
        <span className="petit passages">
          {passages > 1
            ? `${passages} passages sur ce tracé`
            : "Seul passage sur ce tracé"}
        </span>
      </button>
    </div>
  )
}
