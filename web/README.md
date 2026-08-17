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
