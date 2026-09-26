import { useSyncExternalStore } from "react"
import { supabase } from "./supabase"

/// Le verrou du journal, côté téléphone — le pendant de `JournalLock` sur le Mac.
///
/// Ce qu'il est, et ce qu'il n'est pas : un écran devant le journal, contre un
/// regard sur un téléphone déverrouillé qu'on prête ou qu'on laisse traîner. Il
/// ne chiffre rien — les notes arrivent de Supabase en clair, comme partout.
///
/// Deux façons de l'ouvrir. Face ID ou Touch ID, par une passkey que
/// l'appareil garde : c'est lui qui vérifie le visage ou le doigt, et rien ne
/// part vers un serveur. Et toujours, en second, le mot de passe du compte,
/// vérifié par Supabase : pas de code de plus à retenir, et surtout jamais de
/// journal enfermé si la passkey disparaît. **Un verrou qu'on ne peut pas
/// ouvrir n'est pas une sécurité, c'est la perte de ce qu'on a écrit** — la
/// règle du Mac, tenue ici par ce second chemin.
///
/// Réglé par appareil, dans `localStorage` : c'est ce téléphone qu'on protège.

export type ReglageVerrou = {
  actif: boolean
  /// L'identifiant de la passkey, en base64url ; null sans Face ID.
  passkey: string | null
  /// Minutes hors de l'application avant qu'il se referme.
  delai: number
}

const CLEF = "cairn.verrou-journal"
const DEFAUT: ReglageVerrou = { actif: false, passkey: null, delai: 10 }

export const DELAIS: { minutes: number; libelle: string }[] = [
  { minutes: 0, libelle: "Dès qu'on quitte Cairn" },
  { minutes: 1, libelle: "Après 1 minute" },
  { minutes: 5, libelle: "Après 5 minutes" },
  { minutes: 10, libelle: "Après 10 minutes" },
  { minutes: 30, libelle: "Après 30 minutes" },
]

function lire(): ReglageVerrou {
  try {
    const brut = localStorage.getItem(CLEF)
    return brut ? { ...DEFAUT, ...(JSON.parse(brut) as Partial<ReglageVerrou>) } : DEFAUT
  } catch {
    return DEFAUT
  }
}

// L'état, hors de React : l'onglet du journal, la feuille du compte et le
// suivi de visibilité le partagent.
let reglage = lire()
let ouvert = !reglage.actif
let cacheDepuis: number | null = null
const abonnes = new Set<() => void>()
let instantane = { reglage, ouvert }

function publier() {
  instantane = { reglage, ouvert }
  abonnes.forEach((f) => f())
}

function enregistrer(nouveau: ReglageVerrou) {
  reglage = nouveau
  try {
    localStorage.setItem(CLEF, JSON.stringify(nouveau))
  } catch {
    // Navigation privée : le réglage vaut pour la séance, c'est tout.
  }
  publier()
}

// Parti trop longtemps : refermé au retour.
if (typeof document !== "undefined") {
  document.addEventListener("visibilitychange", () => {
    if (!reglage.actif) return
    if (document.visibilityState === "hidden") {
      cacheDepuis = Date.now()
      if (reglage.delai === 0 && ouvert) {
        ouvert = false
        publier()
      }
    } else if (cacheDepuis !== null) {
      if (Date.now() - cacheDepuis >= reglage.delai * 60_000 && ouvert) {
        ouvert = false
        publier()
      }
      cacheDepuis = null
    }
  })
}

export function useVerrou() {
  return useSyncExternalStore(
    (f) => {
      abonnes.add(f)
      return () => abonnes.delete(f)
    },
    () => instantane,
  )
}

// --- Passkey --------------------------------------------------------------

function base64url(octets: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(octets)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

function octets(texte: string): Uint8Array<ArrayBuffer> {
  const b64 = texte.replace(/-/g, "+").replace(/_/g, "/")
  const brut = atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4))
  return Uint8Array.from(brut, (c) => c.charCodeAt(0))
}

function hasard(taille: number): Uint8Array<ArrayBuffer> {
  return crypto.getRandomValues(new Uint8Array(taille))
}

/// Si l'appareil sait vérifier un visage ou un doigt.
export async function biometrieDisponible(): Promise<boolean> {
  try {
    return (
      typeof PublicKeyCredential !== "undefined" &&
      (await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable())
    )
  } catch {
    return false
  }
}

async function creerPasskey(): Promise<string | null> {
  const credential = (await navigator.credentials.create({
    publicKey: {
      challenge: hasard(32),
      rp: { name: "Cairn", id: location.hostname },
      user: { id: hasard(16), name: "journal", displayName: "Journal Cairn" },
      pubKeyCredParams: [
        { type: "public-key", alg: -7 },
        { type: "public-key", alg: -257 },
      ],
      authenticatorSelection: {
        authenticatorAttachment: "platform",
        userVerification: "required",
        residentKey: "discouraged",
      },
      timeout: 60_000,
    },
  })) as PublicKeyCredential | null
  return credential ? base64url(credential.rawId) : null
}

async function verifierPasskey(id: string): Promise<boolean> {
  const reponse = await navigator.credentials.get({
    publicKey: {
      challenge: hasard(32),
      rpId: location.hostname,
      allowCredentials: [{ type: "public-key", id: octets(id) }],
      userVerification: "required",
      timeout: 60_000,
    },
  })
  return reponse !== null
}

// --- Gestes ---------------------------------------------------------------

/// Active le verrou ; propose Face ID quand l'appareil l'a. Un refus de Face ID
/// n'empêche pas d'activer : le mot de passe du compte suffit.
export async function activer(): Promise<void> {
  let passkey: string | null = null
  if (await biometrieDisponible()) {
    try {
      passkey = await creerPasskey()
    } catch {
      passkey = null
    }
  }
  ouvert = true
  enregistrer({ ...reglage, actif: true, passkey })
}

export function desactiver() {
  ouvert = true
  enregistrer({ ...reglage, actif: false, passkey: null })
}

export function choisirDelai(minutes: number) {
  enregistrer({ ...reglage, delai: minutes })
}

export function verrouiller() {
  if (!reglage.actif) return
  ouvert = false
  publier()
}

export async function ouvrirAvecBiometrie(): Promise<boolean> {
  if (!reglage.passkey) return false
  try {
    if (await verifierPasskey(reglage.passkey)) {
      ouvert = true
      publier()
      return true
    }
  } catch {
    // Annulé, ou la passkey n'existe plus : le mot de passe reste.
  }
  return false
}

/// Le mot de passe du compte, vérifié par Supabase — le chemin qui marche
/// toujours.
export async function ouvrirAvecMotDePasse(motDePasse: string): Promise<boolean> {
  const { data } = await supabase.auth.getUser()
  const email = data.user?.email
  if (!email) return false
  const { error } = await supabase.auth.signInWithPassword({ email, password: motDePasse })
  if (error) return false
  ouvert = true
  publier()
  return true
}
