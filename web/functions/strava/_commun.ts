/// Ce que les trois fonctions Strava partagent.
///
/// Elles existent pour une raison unique : **le secret client de Strava ne
/// peut pas vivre dans la PWA.** Tout ce qui est visible dans le JavaScript
/// d'une page est public, et l'échange du code contre un jeton l'exige. Une
/// fonction Cloudflare Pages est le plus court chemin — le même que celui
/// déjà pris pour Open Food Facts, et servi depuis le même domaine.
///
/// Ce qu'elles ne font **pas** : détenir de pouvoir sur tes données. Elles
/// n'ont pas la clé de service de Supabase ; elles reçoivent le jeton de la
/// session du navigateur et écrivent sous cette identité-là, donc la politique
/// RLS s'applique comme si la page écrivait elle-même.

export type Env = {
  STRAVA_CLIENT_ID: string
  STRAVA_CLIENT_SECRET: string
  VITE_SUPABASE_URL: string
  VITE_SUPABASE_ANON_KEY: string
}

export function json(corps: unknown, statut = 200): Response {
  return new Response(JSON.stringify(corps), {
    status: statut,
    headers: { "Content-Type": "application/json" },
  })
}

/// Qui parle, vérifié auprès de Supabase.
///
/// Le jeton de session est présenté à `/auth/v1/user` plutôt que décodé ici :
/// vérifier une signature demanderait le secret JWT du projet, et un jeton
/// expiré ou révoqué se lit de toute façon très bien.
export async function identifier(
  requete: Request, env: Env
): Promise<{ token: string; userID: string } | null> {
  const entete = requete.headers.get("Authorization") ?? ""
  const token = entete.startsWith("Bearer ") ? entete.slice(7) : ""
  if (!token) return null

  const reponse = await fetch(`${env.VITE_SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: env.VITE_SUPABASE_ANON_KEY },
  })
  if (!reponse.ok) return null
  const utilisateur = (await reponse.json()) as { id?: string }
  return utilisateur.id ? { token, userID: utilisateur.id } : null
}

/// Une requête PostgREST menée sous l'identité de la personne connectée.
export async function supabase(
  env: Env, token: string, chemin: string, init: RequestInit = {}
): Promise<Response> {
  return fetch(`${env.VITE_SUPABASE_URL}/rest/v1/${chemin}`, {
    ...init,
    headers: {
      apikey: env.VITE_SUPABASE_ANON_KEY,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  })
}

/// Le jeton d'accès Strava, rafraîchi si besoin.
///
/// Strava les périme en six heures et rend un nouveau jeton de
/// rafraîchissement à chaque échange — il faut donc réécrire les deux, sans
/// quoi la connexion se perd au bout d'une journée.
export async function jetonStrava(
  env: Env, token: string, userID: string
): Promise<string | null> {
  const lecture = await supabase(
    env, token, `strava_token?select=access_token,refresh_token,expires_at&user_id=eq.${userID}`
  )
  if (!lecture.ok) return null
  const lignes = (await lecture.json()) as {
    access_token: string
    refresh_token: string
    expires_at: number
  }[]
  const jeton = lignes[0]
  if (!jeton) return null

  // Une minute de marge : un jeton qui expire pendant la requête qu'il autorise
  // rendrait un 401 qu'on ne saurait pas relire.
  const maintenant = Math.floor(Date.now() / 1000)
  if (jeton.expires_at > maintenant + 60) return jeton.access_token

  const echange = await fetch("https://www.strava.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_id: env.STRAVA_CLIENT_ID,
      client_secret: env.STRAVA_CLIENT_SECRET,
      grant_type: "refresh_token",
      refresh_token: jeton.refresh_token,
    }),
  })
  if (!echange.ok) return null
  const neuf = (await echange.json()) as {
    access_token: string
    refresh_token: string
    expires_at: number
  }
  await enregistrerLeJeton(env, token, userID, neuf)
  return neuf.access_token
}

export async function enregistrerLeJeton(
  env: Env,
  token: string,
  userID: string,
  jeton: { access_token: string; refresh_token: string; expires_at: number },
): Promise<void> {
  await supabase(env, token, "strava_token", {
    method: "POST",
    headers: { Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify({
      user_id: userID,
      access_token: jeton.access_token,
      refresh_token: jeton.refresh_token,
      expires_at: jeton.expires_at,
    }),
  })
}
