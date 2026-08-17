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
