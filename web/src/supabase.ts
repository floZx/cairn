import { createClient } from "@supabase/supabase-js"

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  // Échouer ici plutôt qu'à la première requête : sans ces deux valeurs
  // l'application ne peut rien faire, et un message clair au démarrage vaut
  // mieux qu'un 401 inexplicable trois écrans plus loin.
  throw new Error(
    "VITE_SUPABASE_URL et VITE_SUPABASE_ANON_KEY manquent — voir web/.env.example",
  )
}

export const supabase = createClient(url, anonKey, {
  auth: {
    // La session survit à la fermeture de l'onglet, et se rafraîchit toute
    // seule. C'est ce qui fait qu'on ne se reconnecte pas à chaque ouverture
    // depuis l'écran d'accueil du téléphone.
    persistSession: true,
    autoRefreshToken: true,
  },
})
