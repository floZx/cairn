import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import { VitePWA } from "vite-plugin-pwa"

/// Le même filtre que `functions/off.ts`, qui porte l'explication de sa forme.
const FILTRE_PAYS = 'countries_tags:"en:france"'

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: ["icone-180.png"],
      manifest: {
        name: "Cairn",
        short_name: "Cairn",
        description: "Le journal et les sorties, dans le navigateur",
        lang: "fr",
        // `standalone` : lancée depuis l'écran d'accueil, elle s'ouvre sans
        // la barre d'adresse. C'est toute la différence entre un marque-page
        // et quelque chose qu'on ouvre pour écrire une note.
        display: "standalone",
        start_url: "/",
        // Les deux fonds de `index.css`, à la valeur près : l'écran de
        // lancement d'Android est peint avec ceux-ci, et un blanc éclatant
        // avant une application sombre est un éclair dans les yeux le soir.
        background_color: "#141414",
        theme_color: "#141414",
        icons: [
          { src: "/icone-192.png", sizes: "192x192", type: "image/png" },
          { src: "/icone-512.png", sizes: "512x512", type: "image/png" },
        ],
      },
      workbox: {
        // Uniquement la coquille : le JavaScript, le CSS, les icônes.
        //
        // Rien de Supabase, et c'est une décision, pas un oubli. Une réponse
        // d'API mise en cache est un journal périmé qu'on croit à jour — le
        // pire des deux mondes, puisqu'on ne saurait même pas qu'on lit
        // vieux. Le Mac est la copie qui fonctionne hors ligne ; le
        // navigateur demande le réseau, et le dit quand il ne l'a pas.
        globPatterns: ["**/*.{js,css,html,png,svg,woff2}"],
        navigateFallbackDenylist: [/^\/api/],
      },
      devOptions: { enabled: false },
    }),
  ],
  server: {
    host: true,
    // Le pendant en développement de `functions/off.ts` : Vite n'exécute pas
    // les fonctions Cloudflare, et sans cela `/off` rendrait la page d'accueil.
    // Mandaté par le serveur, donc pas de CORS ici non plus — c'est bien le
    // navigateur, et lui seul, que les serveurs d'Open Food Facts écartent.
    proxy: {
      "/off": {
        target: "https://search.openfoodfacts.org",
        changeOrigin: true,
        rewrite: (chemin: string) => {
          const q = new URL(chemin, "http://x").searchParams.get("q") ?? ""
          const params = new URLSearchParams({
            q: `${q} ${FILTRE_PAYS}`,
            page_size: "25",
          })
          return `/search?${params}`
        },
      },
    },
  },
})
