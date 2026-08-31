import SwiftUI
import SwiftData

/// La fiche d'une personne, en petit, au-dessus de la note qui la cite.
///
/// Ce qu'on a écrit **sur** elle, puis les cinq dernières notes qui la citent.
/// Cinq, parce qu'une popover se lit d'un coup d'œil : au-delà, c'est la page
/// complète qu'on veut, et le bouton du bas y mène.
///
/// Les cinq coûtent une relecture des textes de la bibliothèque, et c'est
/// assumé pour un clic — mais **pas** au prix de la lire entière : la requête
/// des sorties porte son filtre, si bien qu'on parcourt les cinquante-sept qui
/// ont écrit quelque chose et non les huit cent soixante-huit qui existent.
struct PersonPopoverCard: View {
    let handle: PersonHandle

    @Environment(\.ouvrirDansPeople) private var ouvrirDansPeople
    @Environment(\.ouvrirLaCitation) private var ouvrirLaCitation
    @Environment(\.dismiss) private var fermer
    /// La table des fiches ne contient que les personnes sur qui quelque chose
    /// a été écrit : quelques lignes, pas la bibliothèque.
    @Query private var fiches: [Person]

    // Les textes où quelqu'un peut être cité. Le filtre est dans la requête
    // pour les sorties : c'est la seule table où le rapport entre « en a
    // écrit » et « existe » est de un à quinze.
    @Query private var notesDuJournal: [JournalNote]
    @Query(filter: #Predicate<Activity> {
        $0.activityDescription != nil && $0.activityDescription != ""
    })
    private var sortiesQuiRacontent: [Activity]
    @Query private var notesDeRepas: [MealNote]
    @Query private var pesees: [WeightEntry]
    @Query private var seances: [PlannedSession]
    @Query private var creneaux: [MealSlot]

    /// Les plus récentes d'abord — `PeopleIndex.citations` les range déjà ainsi.
    private var dernieresCitations: [PeopleIndex.Citation] {
        let citations = PeopleIndex.citations(
            dans: PeopleView.textes(
                journalNotes: notesDuJournal, activities: sortiesQuiRacontent,
                mealNotes: notesDeRepas, weights: pesees,
                sessions: seances, slots: creneaux
            )
        )
        return Array((citations[handle] ?? []).prefix(5))
    }

    private var note: String? {
        let ecrit = (fiches.first { $0.key == handle.key }?.note ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ecrit.isEmpty ? nil : ecrit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(handle.displayName)
                .font(.title3.weight(.semibold))

            // Rien quand rien n'a été écrit : une phrase qui dit qu'il n'y a
            // rien occupe la place de ce qu'il n'y a pas, et la carte a mieux à
            // montrer — les notes qui la citent sont juste en dessous.
            if let note {
                // Rendue comme une note, parce que c'en est une : on y écrit
                // des tags et on y cite d'autres gens.
                MarkdownText(markdown: note, hidesTagHashes: true)
                    .textSelection(.enabled)
            }

            let citations = dernieresCitations
            if !citations.isEmpty {
                // La ligne ne sépare que s'il y a quelque chose au-dessus.
                if note != nil { Divider() }
                Text("Dernières notes")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(citations) { citation in
                    // Cliquable, et jusqu'au bout de la ligne : c'est un
                    // extrait, ce qu'on veut en faire est aller le lire entier
                    // là où il a été écrit.
                    Button {
                        fermer()
                        ouvrirLaCitation(citation)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                "\(Format.fullDate(citation.dateKey.date()).capitalized) · "
                                + citation.source.libelle
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            // Du texte nu et non du Markdown rendu : un extrait
                            // de trois lignes dans une popover n'a pas besoin de
                            // ses gras, et les mentions qu'il contient y
                            // deviendraient des liens ouvrant une popover dans
                            // la popover.
                            Text(citation.texte)
                                .font(.callout)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Voir sa fiche") {
                fermer()
                ouvrirDansPeople(handle.key)
            }
            .buttonStyle(.link)
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }
}

/// Aller là d'où vient une citation — la journée, la sortie, le repas, la
/// pesée, la séance. `RootView` sait comment ; la popover n'a qu'à dire
/// laquelle. Voir `ouvrirDansPeople` juste en dessous pour le pourquoi de
/// l'environnement.
extension EnvironmentValues {
    @Entry var ouvrirLaCitation: (PeopleIndex.Citation) -> Void = { _ in }
}

/// Aller à la fiche complète, depuis n'importe quelle note.
///
/// Par l'environnement : une note est rendue à cinq étages de la vue qui sait
/// changer d'écran, et faire descendre une fermeture à travers cinq signatures
/// aurait mêlé la navigation à des vues qui n'en parlent pas.
///
/// Sans rien par défaut : hors de l'application montée — aperçus, essais — il
/// n'y a nulle part où aller.
extension EnvironmentValues {
    @Entry var ouvrirDansPeople: (String) -> Void = { _ in }
}
