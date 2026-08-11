import Testing
import Foundation
@testable import Cairn

@Suite("JournalReconciliation")
struct JournalReconciliationTests {
    @Test("sans modification en cours, le disque gagne")
    func cleanBufferAdoptsTheDisk() {
        #expect(
            JournalReconciliation.outcome(
                isDirty: false, bufferText: "ancien", diskText: "nouveau"
            ) == .adopt
        )
    }

    @Test("notre propre enregistrement qui revient n'est pas un conflit")
    func ourOwnWriteIsNotAConflict() {
        #expect(
            JournalReconciliation.outcome(
                isDirty: true, bufferText: "en cours", diskText: "en cours"
            ) == .adopt
        )
    }

    @Test("un texte différent sous une frappe en cours est un conflit")
    func differingTextIsAConflict() {
        #expect(
            JournalReconciliation.outcome(
                isDirty: true, bufferText: "ma phrase", diskText: "celle du téléphone"
            ) == .conflict
        )
    }

    @Test("un fichier disparu sous une frappe en cours se signale à part")
    func vanishedFileIsItsOwnCase() {
        #expect(
            JournalReconciliation.outcome(
                isDirty: true, bufferText: "ma phrase", diskText: nil
            ) == .vanished
        )
    }

    @Test("un fichier disparu sans frappe en cours n'alerte pas")
    func vanishedWithoutAnEditIsSilent() {
        #expect(
            JournalReconciliation.outcome(
                isDirty: false, bufferText: "", diskText: nil
            ) == .adopt
        )
    }

    @Test("le fichier tel qu'on l'a laissé n'a pas changé")
    func theFileWeLeftBehindIsUnchanged() {
        #expect(
            JournalReconciliation.isUnchanged(
                diskText: "ma phrase", baselineText: "ma phrase"
            )
        )
    }

    @Test("pas de fichier et un fichier vide sont le même état")
    func noFileAndAnEmptyFileAreTheSameState() {
        #expect(
            JournalReconciliation.isUnchanged(diskText: nil, baselineText: "")
        )
    }

    @Test("un fichier réécrit ailleurs a changé")
    func aFileRewrittenElsewhereHasChanged() {
        #expect(
            !JournalReconciliation.isUnchanged(
                diskText: "celle du téléphone", baselineText: "ma phrase"
            )
        )
    }

    @Test("un fichier supprimé ailleurs a changé")
    func aFileDeletedElsewhereHasChanged() {
        #expect(
            !JournalReconciliation.isUnchanged(
                diskText: nil, baselineText: "ma phrase"
            )
        )
    }
}
