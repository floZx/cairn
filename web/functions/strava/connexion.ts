import type { Env } from "./_commun"

/// L'adresse où envoyer le navigateur pour autoriser Cairn chez Strava.
///
/// Rendue par une fonction plutôt qu'écrite dans la page pour une seule
/// raison : l'identifiant client vit dans les variables de Cloudflare, à côté
/// du secret, et non dans le dépôt.
///
/// `approval_prompt=auto` : on ne redemande pas l'autorisation à quelqu'un qui
/// l'a déjà donnée. `activity:read_all` couvre les sorties privées, que Cairn
/// affiche comme les autres.
export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const origine = new URL(request.url).origin
  const adresse = new URL("https://www.strava.com/oauth/authorize")
  adresse.searchParams.set("client_id", env.STRAVA_CLIENT_ID)
  adresse.searchParams.set("redirect_uri", `${origine}/strava/retour`)
  adresse.searchParams.set("response_type", "code")
  adresse.searchParams.set("approval_prompt", "auto")
  adresse.searchParams.set("scope", "activity:read_all")
  return Response.redirect(adresse.toString(), 302)
}
