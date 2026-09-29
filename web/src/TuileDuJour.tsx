/// La tuile d'un jour — « SAM » sur « 19 » — et le mois en toutes lettres,
/// partagés par les citations d'une personne et la recherche du journal.

const jourAbrege = new Intl.DateTimeFormat("fr-FR", { weekday: "short", timeZone: "UTC" })
const moisEtAnnee = new Intl.DateTimeFormat("fr-FR", {
  month: "long",
  year: "numeric",
  timeZone: "UTC",
})

/// « SAM » sur « 19 » : la tuile du journal, dimanche en rouge, aujourd'hui en
/// couleur d'accent.
export function TuileDuJour({ dateKey }: { dateKey: string }) {
  const date = new Date(`${dateKey}T00:00:00Z`)
  const maintenant = new Date()
  const aujourdhui =
    date.getUTCFullYear() === maintenant.getFullYear() &&
    date.getUTCMonth() === maintenant.getMonth() &&
    date.getUTCDate() === maintenant.getDate()
  const classes = ["tuile-jour", "tuile-sortie"]
  if (aujourdhui) classes.push("aujourdhui")
  else if (date.getUTCDay() === 0) classes.push("dimanche")
  return (
    <span className={classes.join(" ")}>
      <span className="abrege">{jourAbrege.format(date).replace(".", "")}</span>
      <span className="numero">{date.getUTCDate()}</span>
    </span>
  )
}

/// « Septembre 2026 », au-dessus de l'extrait.
export function mois(dateKey: string): string {
  const texte = moisEtAnnee.format(new Date(`${dateKey}T00:00:00Z`))
  return texte.charAt(0).toUpperCase() + texte.slice(1)
}
