import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { App } from "./App"
import "./index.css"

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Relues au retour dans l'application, et seulement celles de l'écran
      // affiché, vieilles de plus d'une minute (`staleTime`). Coupé au départ
      // pour l'egress, ce retour laissait l'iPhone sur la note d'avant : une
      // PWA reste en mémoire, et revenir sur le journal déjà ouvert ne
      // relisait rien — la note écrite sur le Mac n'arrivait qu'en changeant
      // d'onglet. Signalé le 29 septembre 2026.
      refetchOnWindowFocus: true,
      staleTime: 60_000,
      // Gardées toute la session, et non cinq minutes : au-delà, revenir sur
      // la liste après un passage sur la carte la faisait repasser par la
      // roue d'attente. Elles restent affichées tout de suite, et la relecture
      // silencieuse — une fois la minute passée — les tient à jour. Rien ne
      // survit à la fermeture de l'application.
      gcTime: Infinity,
    },
  },
})

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </StrictMode>,
)
