import Testing
@testable import Cairn

@Suite("Raccourcis vim")
struct VimKeyBufferTests {
    /// Types a whole sequence and returns the commands it produced.
    private func run(_ keys: [(Character, Bool)]) -> [VimCommand] {
        var buffer = VimKeyBuffer()
        return keys.compactMap { buffer.accept($0.0, control: $0.1) }
    }

    private func run(_ keys: String) -> [VimCommand] {
        run(keys.map { ($0, false) })
    }

    @Test("j et k déplacent d'une ligne")
    func movesOneRow() {
        #expect(run("j") == [.move(1)])
        #expect(run("k") == [.move(-1)])
    }

    @Test("un compte précède le mouvement")
    func countPrecedesTheMotion() {
        // The digits produce nothing on their own: a count is not a command.
        #expect(run("5j") == [.move(5)])
        #expect(run("12k") == [.move(-12)])
    }

    @Test("le compte est consommé et ne se reporte pas")
    func theCountIsConsumed() {
        // The bug this closes: `3j` then `j` must move three rows then one, not
        // three then three.
        #expect(run("3jj") == [.move(3), .move(1)])
    }

    @Test("un zéro isolé n'ouvre pas un compte")
    func aLeadingZeroIsNotACount() {
        // In vim `0` is a motion, never the start of a number, so `0j` is a
        // plain `j` rather than a move of zero rows — which would do nothing at
        // all and look like a dead key.
        #expect(run("0j") == [.move(1)])
        #expect(run("10j") == [.move(10)])
    }

    @Test("gg va au début, G à la fin")
    func goesToTheEnds() {
        #expect(run("gg") == [.first])
        #expect(run("G") == [.last])
    }

    @Test("g suivi d'une lettre change de section")
    func gSwitchesSection() {
        #expect(run("ga") == [.section(.all)])
        #expect(run("gm") == [.section(.globalMap)])
        #expect(run("gs") == [.section(.statistics)])
    }

    @Test("une séquence g inconnue est annulée, pas interprétée à moitié")
    func anUnknownGSequenceIsCancelled() {
        // `gj` must not fall through to the one-key table and move a row: a
        // half-recognised prefix is worse than a dead one.
        #expect(run("gj").isEmpty)
        // And the buffer is left clean, so the next key starts fresh.
        var buffer = VimKeyBuffer()
        _ = buffer.accept("g")
        _ = buffer.accept("z")
        #expect(buffer.isEmpty)
    }

    @Test("contrôle-d et contrôle-u font une demi-page")
    func halfPages() {
        #expect(run([("d", true)]) == [.halfPage(down: true)])
        #expect(run([("u", true)]) == [.halfPage(down: false)])
    }

    @Test("les actions sur l'activité ont leur touche")
    func activityActions() {
        #expect(run("e") == [.edit])
        #expect(run("x") == [.delete])
        #expect(run("f") == [.toggleFavorite])
        #expect(run("o") == [.expandMap])
        #expect(run("/") == [.openSearch])
        #expect(run("?") == [.showHelp])
    }

    @Test("une touche inconnue nettoie l'état au lieu de l'armer")
    func anUnknownKeyClearsThePendingState() {
        // `3` then a typo then `j` would otherwise jump three rows, long after
        // the user had given up on the count.
        #expect(run("3zj") == [.move(1)])
    }

    @Test("un compte démesuré est borné")
    func theCountIsBounded() {
        // Leaning on a digit key must not produce a move nothing can undo.
        #expect(run("99999999j") == [.move(VimKeyBuffer.maximumCount)])
    }

    @Test("la remise à zéro vide aussi un préfixe à moitié tapé")
    func resetClearsAHalfTypedPrefix() {
        var buffer = VimKeyBuffer()
        _ = buffer.accept("4")
        _ = buffer.accept("g")
        #expect(!buffer.isEmpty)
        buffer.reset()
        #expect(buffer.isEmpty)
        // And nothing of it survives into the next key.
        #expect(buffer.accept("j") == .move(1))
    }

    @Test("gn et gp rejoignent les écrans du journal")
    func gPrefixReachesJournalSections() {
        #expect(run("gn") == [.section(.nutrition)])
        #expect(run("gp") == [.section(.weight)])
    }

    @Test("a et w déclenchent l'ajout, le compte est ignoré")
    func addFoodAndWeighIn() {
        #expect(run("a") == [.addFood])
        #expect(run("w") == [.newWeighIn])
        // Un compte n'a pas de sens sur une ouverture de sheet.
        #expect(run("3a") == [.addFood])
    }

    @Test("les commandes du journal ne sont pas des commandes d'activité")
    func journalCommandsAreNotActivityBound() {
        #expect(!VimCommand.addFood.actsOnActivities)
        #expect(!VimCommand.newWeighIn.actsOnActivities)
    }

    @Test("K/J, c et s pilotent le journal")
    func journalRowCommands() {
        #expect(run("K") == [.moveEntryUp])
        #expect(run("J") == [.moveEntryDown])
        #expect(run("c") == [.loadRecipe])
        #expect(run("s") == [.saveRecipe])
        #expect(!VimCommand.moveEntryUp.actsOnActivities)
        #expect(!VimCommand.loadRecipe.actsOnActivities)
    }
}

@Suite("Déplacement dans la liste")
struct VimMotionTests {
    @Test("le mouvement est borné aux extrémités, il ne boucle pas")
    func clampsRatherThanWraps() {
        // A list that loops silently loses your place: `G` then `j` must stay
        // on the last row.
        #expect(VimMotion.destination(from: 9, delta: 1, count: 10) == 9)
        #expect(VimMotion.destination(from: 0, delta: -1, count: 10) == 0)
        #expect(VimMotion.destination(from: 3, delta: 100, count: 10) == 9)
    }

    @Test("sans sélection, j part du haut et k du bas")
    func startsFromTheRightEnd() {
        // Both keys have to do something on a list nobody has touched yet.
        #expect(VimMotion.destination(from: nil, delta: 1, count: 10) == 0)
        #expect(VimMotion.destination(from: nil, delta: -1, count: 10) == 9)
    }

    @Test("une liste vide ne mène nulle part")
    func anEmptyListHasNoDestination() {
        #expect(VimMotion.destination(from: nil, delta: 1, count: 0) == nil)
        #expect(VimMotion.destination(from: 0, delta: 1, count: 0) == nil)
    }
}

@Suite("Fermeture du volet au clavier")
struct ClosePaneKeyTests {
    @Test("h ferme le volet, sans l'ambiguïté d'échap")
    func hClosesThePane() {
        var buffer = VimKeyBuffer()
        #expect(buffer.accept("h") == .closePane)
        // Escape peels the search first, so it cannot be relied on to close the
        // pane while something is typed in the field. `h` has one meaning.
        #expect(VimCommand.closePane != VimCommand.clear)
    }

    @Test("un compte devant h est consommé, pas reporté")
    func aCountBeforeHIsConsumed() {
        var buffer = VimKeyBuffer()
        _ = buffer.accept("3")
        _ = buffer.accept("h")
        #expect(buffer.accept("j") == .move(1))
    }
}

@Suite("Écrire les notes au clavier")
struct EditNotesKeyTests {
    @Test("n ouvre l'éditeur dans les notes, e l'ouvre normalement")
    func nAndEAreDistinct() {
        var buffer = VimKeyBuffer()
        #expect(buffer.accept("n") == .editNotes)
        #expect(buffer.accept("e") == .edit)
        // Two intentions, not one with a flag: opening the form and sitting down
        // to write are different acts, and only one of them keeps a journal.
        #expect(VimCommand.editNotes != VimCommand.edit)
    }

    @Test("un compte devant n est consommé, pas reporté")
    func aCountBeforeNIsConsumed() {
        var buffer = VimKeyBuffer()
        _ = buffer.accept("2")
        #expect(buffer.accept("n") == .editNotes)
        #expect(buffer.accept("j") == .move(1))
    }
}

@Suite("Répétition des touches maintenues")
struct KeyRepeatTests {
    @Test("seuls les mouvements se répètent quand la touche reste enfoncée")
    func onlyMotionsRepeat() {
        // Holding `x` would queue a deletion per tick and `e` would reopen the
        // editor under the user's hands; leaning on `j` to walk a list is the
        // whole point of having `j`.
        #expect(VimKeyBuffer.repeatsWhenHeld("j", control: false))
        #expect(VimKeyBuffer.repeatsWhenHeld("k", control: false))
        #expect(VimKeyBuffer.repeatsWhenHeld("d", control: true))
        #expect(VimKeyBuffer.repeatsWhenHeld("u", control: true))

        for key: Character in ["e", "x", "f", "o", "n", "h", "g", "G", "/", "?"] {
            #expect(!VimKeyBuffer.repeatsWhenHeld(key, control: false))
        }
    }

    @Test("un chiffre maintenu ne construit pas un compte")
    func heldDigitsBuildNoCount() {
        // Leaning on a digit would otherwise arm a move of several hundred rows
        // that nobody asked for.
        for key: Character in ["0", "5", "9"] {
            #expect(!VimKeyBuffer.repeatsWhenHeld(key, control: false))
        }
    }
}

@Suite("Bascule de présentation au clavier")
struct ToggleListStyleKeyTests {
    @Test("t bascule la présentation")
    func tTogglesTheStyle() {
        var buffer = VimKeyBuffer()
        #expect(buffer.accept("t") == .toggleListStyle)
    }

    @Test("la bascule fait l'aller-retour")
    func theToggleGoesBothWays() {
        // Two cases, so one key is the whole vocabulary: a picker would want a
        // shortcut each, and there would be nothing to press to come back.
        #expect(ActivityListStyle.table.toggled == .cards)
        #expect(ActivityListStyle.cards.toggled == .table)
        #expect(ActivityListStyle.table.toggled.toggled == .table)
    }

    @Test("les commandes d'activité sont identifiées comme telles")
    func flagsActivityBoundCommands() {
        // Everything that acts on the selected activity or the list's own
        // presentation: meaningless on the food journal, where firing one
        // would edit or delete an activity the screen does not show.
        #expect(VimCommand.edit.actsOnActivities)
        #expect(VimCommand.editNotes.actsOnActivities)
        #expect(VimCommand.delete.actsOnActivities)
        #expect(VimCommand.toggleFavorite.actsOnActivities)
        #expect(VimCommand.expandMap.actsOnActivities)
        #expect(VimCommand.toggleListStyle.actsOnActivities)
        #expect(VimCommand.openSearch.actsOnActivities)
        // Navigation, escape, help and pane-closing stay meaningful anywhere.
        #expect(!VimCommand.section(.nutrition).actsOnActivities)
        #expect(!VimCommand.clear.actsOnActivities)
        #expect(!VimCommand.showHelp.actsOnActivities)
        #expect(!VimCommand.closePane.actsOnActivities)
        #expect(!VimCommand.move(1).actsOnActivities)
    }
}
