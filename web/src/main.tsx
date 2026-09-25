import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { App } from "./App"
import "./index.css"

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      // Les données changent quand le Mac pousse, pas pendant qu'on lit :
      // refetcher à chaque retour d'onglet ne ferait que dépenser de l'egress.
      refetchOnWindowFocus: false,
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
