import { defineConfig } from "vite"
import react from "@vitejs/plugin-react"
import { VitePWA } from "vite-plugin-pwa"

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
  server: { host: true },
})
