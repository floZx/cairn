import type { Section } from "./Chrome"

/// Ce qui est mis de côté : le code reste, rien ne s'affiche.
///
/// Retirés le 24 septembre 2026 — le journal (et les gens, qui en sont une
/// vue), le plan d'entraînement et le poids. Vider l'ensemble et repasser
/// `POIDS_MASQUE` à faux remet tout. Le Mac a son pendant :
/// `SidebarItem.masquees`.
export const SECTIONS_MASQUEES: ReadonlySet<Section> = new Set<Section>(["plan", "journal"])

export const POIDS_MASQUE = true

/// La section demandée, ou les activités quand elle est masquée — une adresse
/// ou une entrée d'historique d'avant peut encore en porter une.
export function sectionVisible(s: Section): Section {
  return SECTIONS_MASQUEES.has(s) ? "activites" : s
}
