import Testing
import Foundation
@testable import Cairn

@Suite("BackupPlan")
struct BackupPlanTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("jamais sauvegardé : on sauvegarde")
    func firstRunAlwaysBacksUp() {
        #expect(BackupPlan.shouldBackUp(
            lastBackup: nil, storeModified: now, now: now
        ))
    }

    @Test("rien écrit depuis la dernière : inutile de recopier")
    func unchangedLibraryIsNotCopiedAgain() {
        let lastWeek = now.addingTimeInterval(-7 * 24 * 3600)
        let older = lastWeek.addingTimeInterval(-3600)
        // Une semaine a passé, largement plus que l'intervalle, mais la base
        // n'a pas bougé : la copie serait un doublon.
        #expect(!BackupPlan.shouldBackUp(
            lastBackup: lastWeek, storeModified: older, now: now
        ))
    }

    @Test("des données neuves, mais pas avant un jour")
    func waitsForTheInterval() {
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        #expect(!BackupPlan.shouldBackUp(
            lastBackup: twoHoursAgo, storeModified: now, now: now
        ))
        let yesterday = now.addingTimeInterval(-25 * 3600)
        #expect(BackupPlan.shouldBackUp(
            lastBackup: yesterday, storeModified: now, now: now
        ))
    }

    @Test("une date de modification inconnue ne bloque pas la sauvegarde")
    func unknownModificationStillBacksUp() {
        let yesterday = now.addingTimeInterval(-25 * 3600)
        #expect(BackupPlan.shouldBackUp(
            lastBackup: yesterday, storeModified: nil, now: now
        ))
    }

    @Test("on ne garde que les trois dernières, les plus anciennes partent")
    func rotationKeepsTheLatest() {
        let names = [
            "journal-2026-08-07-0900.sqlite",
            "journal-2026-08-10-0900.sqlite",
            "journal-2026-08-08-0900.sqlite",
            "journal-2026-08-05-0900.sqlite",
            "journal-2026-08-09-0900.sqlite",
        ]
        #expect(BackupPlan.snapshotsToDelete(names) == [
            "journal-2026-08-05-0900.sqlite",
            "journal-2026-08-07-0900.sqlite",
        ])
    }

    @Test("en dessous du quota, rien n'est supprimé")
    func rotationSparesASmallSet() {
        #expect(BackupPlan.snapshotsToDelete(["a", "b"], keep: 3).isEmpty)
        #expect(BackupPlan.snapshotsToDelete([], keep: 3).isEmpty)
    }

    @Test("le nom d'une sauvegarde se trie par sa date")
    func namesSortChronologically() {
        let earlier = BackupPlan.snapshotName(
            for: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let later = BackupPlan.snapshotName(
            for: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(earlier < later)
        #expect(later.hasSuffix(".sqlite"))
    }
}
