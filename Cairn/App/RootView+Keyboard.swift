import SwiftUI
import SwiftData

// The vim layer's commands, as each screen carries them out.
extension RootView {
    /// The command set for the screens that show no activity — the journal, the
    /// food journal, the weight chart. An activity selection survives invisibly
    /// behind all three, and without this filter a stray `n` or `x` edited or
    /// deleted an outing nothing was showing.
    func performOutsideActivities(_ command: VimCommand) -> Bool {
        guard !command.actsOnActivities else { return false }
        return performOutsideTheList(command)
    }

    /// The journal's own command set.
    ///
    /// It keeps the rule above — nothing may reach the activity selection
    /// surviving invisibly behind this screen — but three keys mean something
    /// here that they cannot mean beside a food log: `/` has a search field to
    /// aim at, Escape has a search and a selection of its own to peel, and `h`
    /// has a pane that does close.
    func performInJournal(_ command: VimCommand) -> Bool {
        switch command {
        case .openSearch:
            searchFieldFocused = true
            return true
        case .clear:
            // One layer at a time, in the order the screen was narrowed.
            // Jamais la sélection : le volet du journal reste ouvert, toujours
            // sur une journée — comme celui des gens.
            if !journalQuery.isEmpty {
                journalQuery = ""
            } else if !journalTags.isEmpty {
                journalTags = []
            }
            searchFieldFocused = false
            return true
        case .closePane:
            // Pas de volet à fermer ici : il reste ouvert sur une journée.
            return false
        default:
            return performOutsideActivities(command)
        }
    }

    /// Les statistiques n'ont pas de lignes à parcourir : `j`, `k` et les
    /// flèches y font défiler la page. Le compte est ignoré — `5j` n'a pas de
    /// sens sur une page qui défile d'un mouvement continu.
    func performInStatistics(_ command: VimCommand) -> Bool {
        switch command {
        case let .move(step):
            statisticsScroll.direction = step > 0 ? 1 : -1
            return true
        case .stopScroll:
            statisticsScroll.direction = 0
            perform(command)
            return true
        default:
            return performOutsideTheList(command)
        }
    }

    /// The same commands, from a view that has no rows to move through.
    ///
    /// Motions are refused rather than silently ignored: the press falls through
    /// to whatever else might want it, instead of being swallowed by a view that
    /// had nothing to do with it.
    func performOutsideTheList(_ command: VimCommand) -> Bool {
        switch command {
        case .move, .first, .last, .halfPage:
            return false
        default:
            perform(command)
            return true
        }
    }

    /// The keyboard commands the list cannot carry out on its own.
    func perform(_ command: VimCommand) {
        switch command {
        case let .section(item):
            allerA(item)
        case .edit:
            if let selected { openEditor(selected, focusingNotes: false) }
        case .editNotes:
            if let selected { openEditor(selected, focusingNotes: true) }
        case .delete:
            pendingDeletion = selected
        case .toggleFavorite:
            toggleFavorite()
        case .expandMap:
            if let selected { expandedMap = .activity(selected.id) }
        case .closePane:
            if showsStatistics {
                // Le volet s'y ouvre par le drapeau, pas par la sélection :
                // c'est lui qu'on baisse — voir `sortieOuverteDepuisLEcran`.
                sortieOuverteDepuisLEcran = false
            } else if listStyle != .cards {
                // Not in cards: they keep a selection (`keptSelection`).
                selectedActivities = []
            }
        case .toggleListStyle:
            listStyle = listStyle.toggled
        case .openJournalDay:
            openJournalDay()
        case .showHelp:
            showsKeyboardHelp = true
        case .clear:
            // Escape peels one layer at a time, as it does everywhere else on
            // the system: the search first, since that is what narrowed the
            // list, and only then the selection.
            if !filter.searchText.isEmpty {
                filter.searchText = ""
            } else if listStyle != .cards {
                selectedActivities = []
            }
            // Focus comes back to the list either way, so the very next key is
            // a motion again rather than a character typed into the field.
            searchFieldFocused = false
        case .openSearch:
            searchFieldFocused = true
        case .move, .first, .last, .halfPage:
            // Motions are carried out by the list, which has the sorted rows.
            break
        case .moveEntryDown, .moveEntryUp:
            // `J` et `K` hors de l'alimentation, qui les prend avant nous pour
            // déplacer un aliment : ici ils font défiler le volet de droite,
            // pendant que `j` et `k` continuent de choisir la sortie. La
            // répétition de la touche ne change rien — le sens est déjà posé,
            // et c'est le volet qui défile à son rythme jusqu'au relâchement.
            paneScroll.direction = command == .moveEntryDown ? 1 : -1
        case .stopScroll:
            paneScroll.direction = 0
        case .addFood, .newWeighIn, .dayForward,
             .loadRecipe, .saveRecipe:
            // Reaching here means no journal screen intercepted them: the
            // list, map or statistics are showing, where they mean nothing.
            break
        }
    }
}
