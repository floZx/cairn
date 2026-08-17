import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Branchement du journal")
@MainActor
struct JournalWiringTests {
    /// Un domaine `UserDefaults` jetable, jamais `.standard` — voir
    /// `freshCursor()` dans `Tests/MirrorTestSupport.swift`, dont celui-ci suit
    /// le patron : un préfixe qui n'appartient qu'à cette suite, un fichier
    /// balayé par `discardJournalDefaults(_:)` plutôt que simplement retiré.
    /// Sans ça, `StoreMaintenance.run(context)` — appelé ici avec le paramètre
    /// `defaults:` explicite pour ne jamais y tomber — lirait et écrirait les
    /// vraies préférences de cette machine : le vrai `journalFolderPath`, et le
    /// vrai marqueur de reprise qu'un lancement réel de Cairn ne verrait alors
    /// plus jamais.
    private static let suitePrefix = "journal-wiring-tests-"

    private func freshJournalDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "\(Self.suitePrefix)\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    /// Le domaine **et** son fichier — voir `discard(_:)` dans
    /// `Tests/MirrorTestSupport.swift` pour pourquoi le second ne suit pas le
    /// premier de lui-même.
    private func discardJournalDefaults(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
        ThrowawayDefaults.sweep(prefix: Self.suitePrefix)
    }

    /// La reprise a lieu à la maintenance du magasin, pas au premier affichage
    /// du journal : une note écrite avant qu'on ouvre l'onglet serait sinon
    /// invisible.
    @Test func laMaintenanceDeclencheLaReprise() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "reprise".write(
            to: folder.appending(path: "2026-08-17.md"), atomically: true, encoding: .utf8
        )

        let (defaults, suiteName) = freshJournalDefaults()
        defer { discardJournalDefaults(suiteName) }
        defaults.set(folder.path, forKey: JournalSettings.folderPathKey)

        try StoreMaintenance.run(context, defaults: defaults)

        #expect(try context.fetch(FetchDescriptor<JournalNote>()).count == 1)
    }

    /// Le journal n'attend plus qu'on lui désigne un dossier : il est
    /// utilisable dès la construction de l'environnement.
    @Test func leJournalEstUtilisableSansDossier() throws {
        let container = try AppModelContainer.inMemory()
        let environment = AppEnvironment(container: container)
        let today = environment.journal.openToday()
        environment.journal.update("une note", for: today)
        environment.journal.saveNow()

        #expect(environment.journal.text(for: today) == "une note")
    }

    /// Un fichier illisible à la reprise se retrouve dans les préférences, en
    /// français, pour que `JournalSettingsView` puisse le montrer — la seule
    /// trace que la reprise a laissée quelque chose à vérifier.
    @Test func unFichierIllisibleALaRepriseEstSignaleDansLesPreferences() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: folder.appending(path: "2026-08-17.md"))

        let (defaults, suiteName) = freshJournalDefaults()
        defer { discardJournalDefaults(suiteName) }
        defaults.set(folder.path, forKey: JournalSettings.folderPathKey)

        try StoreMaintenance.run(context, defaults: defaults)

        let notice = try #require(defaults.string(forKey: JournalSettings.importNoticeKey))
        #expect(notice.contains("2026-08-17.md"))
    }

    /// Une reprise sans rien d'illisible ne pose aucune note dans les
    /// préférences : un silence n'est pas un oubli de la part de la vue qui le
    /// lit.
    @Test func uneRepriseSansSoucINePoseAucuneNote() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "propre".write(
            to: folder.appending(path: "2026-08-17.md"), atomically: true, encoding: .utf8
        )

        let (defaults, suiteName) = freshJournalDefaults()
        defer { discardJournalDefaults(suiteName) }
        defaults.set(folder.path, forKey: JournalSettings.folderPathKey)

        try StoreMaintenance.run(context, defaults: defaults)

        #expect(defaults.string(forKey: JournalSettings.importNoticeKey) == nil)
    }
}
