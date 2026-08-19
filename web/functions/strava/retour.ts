import { enregistrerLeJeton, type Env } from "./_commun"

/// Le retour de Strava, code en main.
///
/// Strava renvoie le navigateur ici, sans jeton de session Supabase — c'est
/// une navigation, pas un appel de la page. On ne peut donc pas écrire dans
/// Supabase depuis cette fonction : elle échange le code contre un jeton, puis
/// rend la main à l'application avec le jeton dans le fragment de l'URL.
///
/// Le fragment et non la requête : ce qui suit le `#` n'est jamais envoyé au
/// serveur ni écrit dans les journaux, et c'est la seule partie d'une URL dont
/// on puisse dire ça. La page le lit, l'enregistre sous son identité, et
/// l'efface de la barre d'adresse.
export const onRequestGet: PagesFunction<Env> = async ({ request, env }) => {
  const url = new URL(request.url)
  const code = url.searchParams.get("code")
  if (!code) {
    // Strava dit pourquoi quand on refuse : « access_denied », le plus
    // souvent. Le transmettre plutôt que de le perdre — un retour muet est ce
    // qui a coûté le plus de temps sur ce projet.
    const cause = url.searchParams.get("error") ?? "sans code"
    return Response.redirect(
      `${url.origin}/?strava=refus&cause=${encodeURIComponent(cause)}`, 302
    )
  }

  const echange = await fetch("https://www.strava.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: env.STRAVA_CLIENT_ID,
      client_secret: env.STRAVA_CLIENT_SECRET,
      grant_type: "authorization_code",
      code,
    }),
  })
  if (!echange.ok) {
    // Le corps de la réponse porte la vraie cause : identifiant client faux,
    // domaine de retour non déclaré, code déjà consommé. Tronqué, parce qu'il
    // voyage dans une URL.
    const dit = (await echange.text()).slice(0, 300)
    return Response.redirect(
      `${url.origin}/?strava=echec&cause=${encodeURIComponent(dit)}`, 302
    )
  }
  const jeton = (await echange.json()) as {
    access_token: string
    refresh_token: string
    expires_at: number
  }

  const fragment = new URLSearchParams({
    strava_access: jeton.access_token,
    strava_refresh: jeton.refresh_token,
    strava_expire: String(jeton.expires_at),
  })
  return Response.redirect(`${url.origin}/#${fragment}`, 302)
}

/// Écrire le jeton reçu, sous l'identité du navigateur.
///
/// Appelée par la page une fois qu'elle a lu le fragment : c'est elle qui a la
/// session Supabase, pas la redirection.
export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const { identifier, json } = await import("./_commun")
  const qui = await identifier(request, env)
  if (!qui) return json({ erreur: "Session expirée." }, 401)

  const jeton = (await request.json()) as {
    access_token: string
    refresh_token: string
    expires_at: number
  }
  await enregistrerLeJeton(env, qui.token, qui.userID, jeton)
  return json({ ok: true })
}
