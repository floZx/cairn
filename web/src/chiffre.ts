import { useSyncExternalStore } from "react"
import { supabase } from "./supabase"

/// Le chiffrement des notes du journal, côté téléphone — le pendant de
/// `JournalCipher` sur le Mac, au format près.
///
/// La clé vient d'une phrase secrète, par PBKDF2-SHA256 avec le sel et le
/// nombre d'itérations rangés dans `journal_crypto`. Le chiffre est
/// AES-256-GCM, le texte chiffré précédé de `cairn-chiffre:v1:` puis, en
/// base64, le nonce de douze octets suivi du texte et de l'étiquette — l'ordre
/// de `AES.GCM.SealedBox.combined` sur le Mac.
///
/// La clé se garde sur cet appareil, dans IndexedDB, **non extractible** : le
/// navigateur s'en sert pour chiffrer et déchiffrer, mais aucun script ne peut
/// en relire les octets. La phrase, elle, n'est jamais gardée.

export const PREFIXE = "cairn-chiffre:v1:"
const TEXTE_VERIFICATEUR = "cairn-journal"

type Config = { salt: string; iterations: number; verifier: string }

/// `inconnu` le temps de demander ; `clair` quand le journal n'est pas
/// chiffré ; `ouvert` quand il l'est et que la clé est ici ; `ferme` quand il
/// l'est sans elle.
export type EtatChiffre = "inconnu" | "clair" | "ouvert" | "ferme"

let etat: EtatChiffre = "inconnu"
let cle: CryptoKey | null = null
let config: Config | null = null
const abonnes = new Set<() => void>()

function publier(nouveau: EtatChiffre) {
  etat = nouveau
  abonnes.forEach((f) => f())
}

export function useChiffre(): EtatChiffre {
  return useSyncExternalStore(
    (f) => {
      abonnes.add(f)
      return () => abonnes.delete(f)
    },
    () => etat,
  )
}

// --- Stockage de la clé ----------------------------------------------------

const BASE = "cairn-chiffre"
const MAGASIN = "cles"

function base(): Promise<IDBDatabase> {
  return new Promise((resoudre, rejeter) => {
    const demande = indexedDB.open(BASE, 1)
    demande.onupgradeneeded = () => demande.result.createObjectStore(MAGASIN)
    demande.onsuccess = () => resoudre(demande.result)
    demande.onerror = () => rejeter(demande.error)
  })
}

async function lireCle(): Promise<{ cle: CryptoKey; salt: string } | null> {
  try {
    const db = await base()
    return await new Promise((resoudre) => {
      const lecture = db.transaction(MAGASIN).objectStore(MAGASIN).get("journal")
      lecture.onsuccess = () => resoudre(lecture.result ?? null)
      lecture.onerror = () => resoudre(null)
    })
  } catch {
    return null
  }
}

async function ecrireCle(valeur: { cle: CryptoKey; salt: string }) {
  const db = await base()
  await new Promise<void>((resoudre, rejeter) => {
    const tx = db.transaction(MAGASIN, "readwrite")
    tx.objectStore(MAGASIN).put(valeur, "journal")
    tx.oncomplete = () => resoudre()
    tx.onerror = () => rejeter(tx.error)
  })
}

// --- Le chiffre ------------------------------------------------------------

function enOctets(b64: string): Uint8Array<ArrayBuffer> {
  const brut = atob(b64)
  return Uint8Array.from(brut, (c) => c.charCodeAt(0))
}

function enBase64(octets: Uint8Array): string {
  let brut = ""
  for (const o of octets) brut += String.fromCharCode(o)
  return btoa(brut)
}

async function deriver(phrase: string, c: Config): Promise<CryptoKey> {
  const materiau = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(phrase),
    "PBKDF2",
    false,
    ["deriveKey"],
  )
  return crypto.subtle.deriveKey(
    { name: "PBKDF2", salt: enOctets(c.salt), iterations: c.iterations, hash: "SHA-256" },
    materiau,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  )
}

async function ouvrirAvec(k: CryptoKey, texte: string): Promise<string> {
  const octets = enOctets(texte.slice(PREFIXE.length))
  const clair = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: octets.slice(0, 12) },
    k,
    octets.slice(12),
  )
  return new TextDecoder().decode(clair)
}

export function estChiffre(texte: string): boolean {
  return texte.startsWith(PREFIXE)
}

/// Le texte en clair d'une note. Sans préfixe, il passe tel quel ; chiffré
/// sans la clé, il rend `null` — à l'appelant de ne rien afficher plutôt que
/// du charabia.
export async function ouvrir(texte: string): Promise<string | null> {
  if (!estChiffre(texte)) return texte
  if (!cle) return null
  try {
    return await ouvrirAvec(cle, texte)
  } catch {
    return null
  }
}

/// Le texte tel qu'il doit partir vers Supabase : chiffré si le journal l'est.
/// Lève une erreur plutôt que d'envoyer en clair un journal chiffré.
export async function sceller(texte: string): Promise<string> {
  // Relu à chaque écriture : un état lu avant la connexion, ou avant qu'un
  // autre appareil n'active le chiffrement, ferait partir la note en clair.
  await chargerChiffre()
  if (etat === "clair") return texte
  if (!cle) throw new Error("Le journal est chiffré : saisissez d'abord la phrase secrète.")
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const chiffre = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv }, cle, new TextEncoder().encode(texte)),
  )
  const tout = new Uint8Array(iv.length + chiffre.length)
  tout.set(iv)
  tout.set(chiffre, iv.length)
  return PREFIXE + enBase64(tout)
}

export function journalChiffre(): boolean {
  return etat === "ouvert" || etat === "ferme"
}

// --- L'état ----------------------------------------------------------------

/// Demande à Supabase si le journal est chiffré, et regarde si la clé est ici.
export async function chargerChiffre(): Promise<EtatChiffre> {
  const { data: session } = await supabase.auth.getSession()
  if (!session.session) {
    cle = null
    publier("inconnu")
    return etat
  }
  const { data, error } = await supabase.from("journal_crypto").select("salt, iterations, verifier")
  if (error) {
    // Une table absente — le script SQL pas encore passé — vaut « en clair » ;
    // toute autre erreur laisse l'état inconnu, et rien ne s'écrit.
    const absente = error.code === "PGRST205" || error.code === "42P01"
    publier(absente ? "clair" : "inconnu")
    return etat
  }
  config = ((data ?? []) as Config[])[0] ?? null
  if (!config) {
    publier("clair")
    return etat
  }
  const gardee = await lireCle()
  if (gardee && gardee.salt === config.salt) {
    try {
      if ((await ouvrirAvec(gardee.cle, config.verifier)) === TEXTE_VERIFICATEUR) {
        cle = gardee.cle
        publier("ouvert")
        return etat
      }
    } catch {
      // Une clé d'un autre chiffrement : on redemande la phrase.
    }
  }
  cle = null
  publier("ferme")
  return etat
}

/// Vérifie la phrase contre le vérificateur, et garde la clé sur cet appareil.
export async function saisirPhrase(phrase: string): Promise<boolean> {
  if (!config) await chargerChiffre()
  if (!config) return false
  const candidate = await deriver(phrase, config)
  try {
    if ((await ouvrirAvec(candidate, config.verifier)) !== TEXTE_VERIFICATEUR) return false
  } catch {
    return false
  }
  cle = candidate
  try {
    await ecrireCle({ cle: candidate, salt: config.salt })
  } catch {
    // Navigation privée : la clé vaut pour la séance, c'est tout.
  }
  publier("ouvert")
  return true
}

void chargerChiffre()
supabase.auth.onAuthStateChange((evenement) => {
  // Hors du rappel : Supabase déconseille d'y appeler l'API, qui attend la
  // fin de ce même rappel.
  if (evenement === "SIGNED_IN" || evenement === "SIGNED_OUT") {
    setTimeout(() => void chargerChiffre(), 0)
  }
})
