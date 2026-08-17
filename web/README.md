# Cairn, côté web

L'application web de Cairn : une PWA qui lit — et plus tard alimente — le
miroir Supabase que l'application macOS tient à jour.

Elle ne parle jamais au Mac. Tout ce qu'elle affiche vient de Supabase, et
tout ce que Supabase contient y a été mis par le Mac.

## Démarrer

```bash
cp .env.example .env.local
```

Remplir les deux valeurs, prises dans **Settings → API** du projet Supabase :
l'URL du projet et la clé `anon`. `.env.local` n'est pas versionné.

```bash
npm install
npm run dev
```

Vite écoute aussi sur le réseau local (`host: true`), donc l'adresse
« Network » qu'il affiche s'ouvre depuis un téléphone sur le même Wi-Fi —
c'est le seul moyen d'essayer pour de vrai une interface faite pour un
téléphone.

## Sur la clé `anon`

Elle est **publique par construction** : elle finit dans le JavaScript de la
page, lisible par quiconque ouvre les outils de développement. Ce n'est pas
une fuite, c'est ainsi que Supabase est pensé. Ce qui protège les données,
c'est exclusivement **Row Level Security**, activée sur chacune des dix-huit
tables : une requête ne rend que les lignes dont `user_id` vaut `auth.uid()`,
quelle que soit la clé utilisée.

La clé `service_role`, elle, contourne RLS. Elle n'a rien à faire ici.

## La pile, et pourquoi

- **Vite + React + TypeScript** — rien d'exotique, et le typage protège les
  noms de colonnes, qui sont la seule chose que cette application partage avec
  le schéma Postgres.
- **`supabase-js`** — accès aux tables et à Storage, et la session gardée d'une
  ouverture à l'autre.
- **TanStack Query** — le cache de requêtes. Pas de refetch au retour d'onglet :
  les données ne changent que quand le Mac pousse, et l'egress du palier
  gratuit se dépense vite.
- **MapLibre GL JS** (à venir) — vectoriel, et il consomme les fonds tiers que
  l'application macOS gère déjà.
- **uPlot** (à venir) — sur des traces de plusieurs milliers de points, les
  bibliothèques à base de SVG s'effondrent.

## Mise en ligne

Hébergée sur Cloudflare Pages, en dépôt direct : le paquet est construit ici
puis téléversé. Pas de connexion entre le dépôt Git et l'hébergeur —
l'intégration continue coûterait une chaîne de plus à surveiller pour une
application qu'une seule personne déploie, et les identifiants Supabase sont
figés dans le paquet à la construction, donc c'est cette machine qui doit les
avoir, jamais un serveur de build.

Une seule fois, pour autoriser cette machine (ouvre le navigateur, c'est un
compte Cloudflare) :

```
npx wrangler login
```

Ensuite, à chaque fois :

```
npm run deploy
```

Ce que le paquet emporte : `VITE_SUPABASE_URL` et `VITE_SUPABASE_ANON_KEY`,
lus dans `.env.local`. La clé anonyme est faite pour être publique — c'est la
politique RLS de chaque table, et elle seule, qui protège les données. La clé
`service_role`, elle, ne doit jamais quitter le tableau de bord Supabase.

### Installer sur le téléphone

iOS : ouvrir l'adresse dans Safari, Partager → « Sur l'écran d'accueil ».
Android : Chrome propose « Installer l'application ».

Le service worker ne met en cache que la coquille — le JavaScript, le CSS, les
icônes. Rien de Supabase : une réponse d'API en cache serait un journal périmé
qu'on croit à jour. Le Mac est la copie qui fonctionne hors ligne ; ici, sans
réseau, l'application se lance et le dit.
