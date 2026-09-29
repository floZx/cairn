import * as maplibregl from "maplibre-gl"
import adresseDuWorker from "maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url"

/// Où MapLibre trouve son worker, dit une fois pour toutes.
///
/// Depuis la version 6, MapLibre cherche `maplibre-gl-worker.mjs` à côté de
/// son propre module. Vite déplace ce module — dans `.vite/deps` en
/// développement, dans `assets/` au build — sans copier le fichier voisin : le
/// worker ne se chargeait jamais. Les tuiles raster, décodées sur le fil
/// principal, s'affichaient ; la trace, une source GeoJSON traitée dans le
/// worker, jamais — `loaded()` éternellement faux, sans la moindre erreur.
/// C'est ce qui avait fait épingler la 5 le 17 août : mesuré le 29 septembre,
/// la requête du worker partait vers `.vite/deps/` et n'aboutissait pas.
///
/// `?worker&url` et non `?url` : le worker importe `maplibre-gl-shared.mjs`,
/// et `?url` copiait le fichier seul — au build, il cherchait un voisin qui
/// n'existait pas. Ainsi, Vite le regroupe avec ses imports en un fichier, au
/// format module (`worker.format` dans `vite.config.ts`), celui que MapLibre
/// demande en premier.
/// Importé avant toute carte : par `cacheTuiles`, que `fonds` charge, et par
/// les deux cartes elles-mêmes.
maplibregl.setWorkerUrl(adresseDuWorker)
