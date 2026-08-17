/// Les mises en forme partagées. Le Mac les fait dans `Format` ; celles-ci
/// disent la même chose avec les outils du navigateur.

export function distance(metres: number): string {
  if (metres <= 0) return "—"
  return `${(metres / 1000).toLocaleString("fr-FR", {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })} km`
}

/// `1 h 24` plutôt que `1:24:00` : c'est ainsi qu'on parle d'une sortie, et la
/// seconde ne veut rien dire sur une heure et demie de vélo.
export function duree(secondes: number): string {
  if (secondes <= 0) return "—"
  const heures = Math.floor(secondes / 3600)
  const minutes = Math.round((secondes % 3600) / 60)
  if (heures === 0) return `${minutes} min`
  return `${heures} h ${String(minutes).padStart(2, "0")}`
}

export function denivele(metres: number): string {
  if (metres <= 0) return "—"
  return `${Math.round(metres).toLocaleString("fr-FR")} m`
}

const jour = new Intl.DateTimeFormat("fr-FR", {
  weekday: "short",
  day: "numeric",
  month: "short",
})

const jourAvecAnnee = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "short",
  year: "numeric",
})

/// L'année n'apparaît que si l'activité n'est pas de l'année en cours — elle
/// est du bruit sur les sorties récentes, et indispensable sur les anciennes.
export function dateCourte(iso: string): string {
  const date = new Date(iso)
  const memeAnnee = date.getFullYear() === new Date().getFullYear()
  return (memeAnnee ? jour : jourAvecAnnee).format(date)
}

const jourLong = new Intl.DateTimeFormat("fr-FR", {
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
})

/// Une clé de jour du journal (`AAAA-MM-JJ`) en toutes lettres.
///
/// Découpée à la main plutôt que passée à `new Date` : une date seule est lue
/// comme UTC par le navigateur, et un journal tenu à Paris verrait ses notes
/// du soir datées de la veille.
export function dateLongue(dateKey: string): string {
  const [a, m, j] = dateKey.split("-").map(Number)
  return jourLong.format(new Date(a, m - 1, j))
}

const jourEntier = new Intl.DateTimeFormat("fr-FR", {
  weekday: "long",
  day: "numeric",
  month: "long",
  year: "numeric",
})

const heureExacte = new Intl.DateTimeFormat("fr-FR", {
  hour: "2-digit",
  minute: "2-digit",
})

/// « lundi 17 août 2026 à 19:23 » — la forme que la fiche du Mac emploie.
///
/// Le « à » est écrit, et l'heure sur deux chiffres : « à 6:52 » se lit moins
/// bien que « à 06:52 » quand la date qui précède est longue.
export function dateEtHeure(iso: string): string {
  const d = new Date(iso)
  return `${jourEntier.format(d)} à ${heureExacte.format(d)}`
}
