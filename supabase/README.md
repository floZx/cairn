# Le miroir Supabase

Ce dossier contient le schéma Postgres du miroir web de Cairn : une copie de
la bibliothèque, tenue à jour par le Mac, que la future PWA lira. Le Mac ne
dépend jamais de ce miroir — son échec n'a d'autre effet qu'un indicateur
dans les réglages.

## Mettre en place le projet

1. **Créer un projet sur [supabase.com](https://supabase.com).** Un compte
   gratuit suffit pour un usage personnel. Choisir une région proche, un mot
   de passe de base de données (à ranger de côté, il ne ressert pas ici), et
   attendre que le projet finisse de se provisionner.

2. **Appliquer le schéma.** Dans le tableau de bord du projet, ouvrir
   **SQL Editor** → **New query**, coller l'intégralité de `schema.sql`, et
   exécuter (**Run**). Ça crée les seize tables du miroir, leurs déclencheurs,
   leurs index, leur politique RLS, ainsi que les deux buckets de Storage
   (`streams`, `photos`) et leur politique.

   Le script est écrit pour tourner une seule fois sur un projet neuf. Il ne
   contient pas de garde `if not exists` sur les tables ni les buckets ; le
   rejouer sur un projet déjà provisionné échouera sur les objets déjà créés.

3. **Créer l'utilisateur unique.** Dans **Authentication** → **Users**,
   **Add user** → **Create new user**, avec une adresse et un mot de passe.
   Cairn est un usage personnel : un seul compte suffit, et c'est celui que
   le Mac utilisera pour s'authentifier avant d'écrire.

4. **Relever les identifiants du projet.** Dans **Settings** → **API** :
   - l'**URL du projet** (`https://xxxxx.supabase.co`) ;
   - la clé **`anon` / `public`**.

   Ces deux valeurs sont ce que `MirrorCredentials` demandera au trousseau,
   plus l'adresse et le mot de passe créés à l'étape 3.

## Sur la clé `anon`

La clé `anon` est **publique par construction** : elle finira dans le
JavaScript de la PWA, visible de quiconque ouvre les outils de développement
de son navigateur. Ce n'est pas une fuite — c'est ainsi que Supabase est
pensé. Ce qui protège les données, c'est exclusivement **Row Level Security**
(RLS), activée sur chacune des seize tables par ce schéma : une requête ne
peut lire ou écrire que les lignes dont `user_id` vaut `auth.uid()`, quelle
que soit la clé utilisée pour s'authentifier. Sans cette politique, la clé
`anon` donnerait accès à toute la base à quiconque la trouverait — et
n'importe qui la trouverait.

Ne jamais utiliser la clé `service_role` (qui, elle, contourne RLS) en dehors
du tableau de bord Supabase lui-même.

## Vérifier que RLS mord

Une fois le schéma appliqué et la clé `anon` en main, une requête anonyme
(sans jeton d'utilisateur) doit renvoyer un tableau vide plutôt qu'une erreur
ou des données :

```bash
curl -s "https://VOTRE-PROJET.supabase.co/rest/v1/activity?select=uuid" \
  -H "apikey: VOTRE_CLE_ANON"
```

- `[]` : la table existe et la politique refuse les lignes d'autrui — c'est
  l'attendu.
- une erreur `42P01` : la table n'a pas été créée — reprendre l'étape 2.
- un tableau non vide : la politique n'a pas pris — revérifier que RLS est
  bien activée sur `activity` (`alter table activity enable row level
  security;`) et que la policy existe.

## Lire les flux depuis le web

Les onze flux d'une activité — trace, fréquence cardiaque, puissance… — ne
traversent pas en colonnes : la ligne `activity_streams` ne porte qu'un
`storage_path`, et les octets vivent dans le bucket `streams`. Un objet par
activité, pas onze : une fiche d'activité les lit toujours ensemble, et onze
objets voudraient dire onze requêtes.

L'objet est un **JSON**, une clé par flux présent (les flux absents sont
simplement omis) :

| clé | contenu | encodage binaire |
| --- | --- | --- |
| `latlng` | la trace | `Float64` par paires — latitude, longitude |
| `time` | secondes depuis le départ | `Int32` |
| `distance` | mètres cumulés | `Float32` |
| `altitude` | mètres | `Float32` |
| `heartrate` | battements par minute | `Float32` |
| `cadence` | tours ou pas par minute | `Float32` |
| `watts` | puissance | `Float32` |
| `velocitySmooth` | vitesse lissée, m/s | `Float32` |
| `temp` | degrés Celsius | `Float32` |
| `grade` | pente, en pourcent | `Float32` |
| `moving` | en mouvement, 0 ou 1 | `Float32` |

Chaque valeur est le **base64** d'un empaquetage binaire **sans en-tête** et
**petit-boutiste** : rien que les nombres, bout à bout. Le type est donc porté
par le nom de la clé, pas par les octets, et le nombre de points se déduit de
la longueur — 4 octets par valeur `Float32` ou `Int32`, 16 par point de
`latlng` (deux `Float64`). La ligne `activity_streams` en donne d'ailleurs le
compte dans `point_count`.

De quoi les lire, dans un navigateur :

```js
const bytes = (b64) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));

const streams = await (await fetch(url)).json();
const latlng = new Float64Array(bytes(streams.latlng).buffer);   // [lat, lon, lat, lon, …]
const time = new Int32Array(bytes(streams.time).buffer);         // secondes
const heartrate = new Float32Array(bytes(streams.heartrate).buffer);
```

`Float64Array`, `Int32Array` et `Float32Array` lisent en petit-boutiste sur
toutes les plateformes qui font tourner un navigateur, ce qui est exactement
pourquoi le Mac écrit dans cet ordre-là.

Le chemin de l'objet est celui que la ligne annonce : `storage_path`, de la
forme `<user_id>/<uuid de la ligne activity_streams>`. Les photos suivent la
même règle dans le bucket `photos`, à ceci près que leur chemin est bâti sur
l'identifiant Strava de la photo et que l'objet est le JPEG lui-même.
