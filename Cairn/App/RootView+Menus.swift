import SwiftUI
import SwiftData

// The menu bar's view of the window: what each command may act on.
extension RootView {
    /// What the menu bar can act on from the screen on display.
    ///
    /// The commands used to be installed once and never withdrawn: beside the
    /// food journal, the statistics or a locked journal, ⌘⌫ offered to delete
    /// an outing the screen did not show, ⌘N opened the activity editor, and
    /// no item ever greyed out. The vim layer already refused the same
    /// commands there (`VimCommand.actsOnActivities`); the menu now agrees.
    struct MenuState: Equatable {
        /// The activity list's own section: ⌘N and the table/cards switch.
        var activities = false
        var selectedOne = false
        var selectedAny = false
        var selectionIsFavorite = false
        var journalOpen = false
        var journalNote = false
        var journalUnlocked = false
    }

    var menuState: MenuState {
        let activities = showsActivityActions
        // The statistics and the plan open an outing's pane of their own: what
        // it shows is the selection, and the commands may act on it.
        let outingOnScreen = activities
            || ((showsStatistics || showsTraining) && sortieOuverteDepuisLEcran)
        let selection = outingOnScreen ? selection : []
        let journalUnlocked = app.journalLock.estOuvert
        return MenuState(
            activities: activities,
            selectedOne: selection.count == 1,
            selectedAny: !selection.isEmpty,
            selectionIsFavorite: !selection.isEmpty && selection.allSatisfy(\.isFavorite),
            journalOpen: showsJournal && journalUnlocked,
            journalNote: showsJournal && journalUnlocked && journalSelectionHasNote,
            journalUnlocked: journalUnlocked
        )
    }

    /// A nil closure is what greys an item out; nil everywhere once the window
    /// has gone, so nothing acts on a view that no longer exists.
    func installMenuCommands(_ state: MenuState?) {
        guard let state else {
            app.requestNewActivity = nil
            app.requestEditSelection = nil
            app.requestDeleteSelection = nil
            app.requestToggleFavorite = nil
            app.selectionIsFavorite = false
            app.requestExportGPX = nil
            app.requestToggleListStyle = nil
            app.requestExportJournalPDF = nil
            app.requestImportGPX = nil
            app.requestShowJournalTag = nil
            app.requestShowKeyboardHelp = nil
            app.requestResyncEverything = nil
            return
        }
        // ⌘N means "make the thing this section is about": an activity in
        // the list, today's note in the journal.
        app.requestNewActivity = state.journalOpen
            ? { openTodaysNote() }
            : state.activities ? { editor = .create } : nil
        app.requestEditSelection = state.selectedOne
            ? { if let selected { editor = .edit(selected) } } : nil
        app.requestDeleteSelection = state.journalNote
            ? { journalPendingDeletion = journalSelection }
            : state.selectedOne ? { pendingDeletion = selected } : nil
        app.requestToggleFavorite = state.selectedAny ? { toggleFavorite() } : nil
        app.selectionIsFavorite = state.selectionIsFavorite
        app.requestExportGPX = state.selectedAny ? { exportGPX(selection) } : nil
        app.requestToggleListStyle = state.activities
            ? { listStyle = listStyle.toggled } : nil
        app.requestExportJournalPDF = state.journalUnlocked ? {
            // Pre-filled on the month being read: that is the period one
            // has in mind when the menu is opened from the journal.
            let day = journalSelection ?? DateKey(Date())
            journalExportProgress = nil
            journalExportFrom = day.monthStart
            journalExportTo = day.monthEnd()
            showsJournalExport = true
        } : nil
        app.requestImportGPX = { chooseGPXFilesToImport() }
        app.requestShowJournalTag = { tag in
            allerA(.journal)
            vueJournal = .journees
            journalQuery = ""
            journalTags = [tag]
        }
        app.requestShowKeyboardHelp = { showsKeyboardHelp = true }
        app.requestResyncEverything = { confirmsResync = true }
    }
}
