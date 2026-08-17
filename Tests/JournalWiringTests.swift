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

    /// Un dossier de cache jetable, jamais `JournalAttachmentCache.vaultRoot` —
    /// voir la même paire dans `Tests/StoreMaintenanceTests.swift` : la reprise
    /// reconstruit le cache des pièces jointes, et le vrai dossier de cache de
    /// l'application n'est pas un endroit où une suite de tests écrit.
    private func freshCacheDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "\(Self.suitePrefix)cache-\(UUID().uuidString)")
    }

    private func discardCache(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
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
        let cache = freshCacheDirectory()
        defer { discardCache(cache) }
        defaults.set(folder.path, forKey: JournalSettings.folderPathKey)

        try StoreMaintenance.run(context, cacheDirectory: cache, defaults: defaults)

        #expect(try context.fetch(FetchDescriptor<JournalNote>()).count == 1)
    }

    /// Un environnement complet, mais rien de réel dedans — le patron de
    /// `Tests/MirrorAutonomyTests.swift`, et pour la raison que le
    /// doc-comment d'`AppEnvironment.init` développe sur un paragraphe :
    /// `AppEnvironment(container:)` nu prend le vrai `KeychainStore`, le vrai
    /// `URLSessionTransport` et `MirrorBootstrapCursor(defaults: .standard)`.
    /// Sur une machine où le miroir est configuré — celle du propriétaire de
    /// ce dépôt en est une — `mirrorRecorder.start()` part alors pour de
    /// vrai, sur les vraies préférences.
    private func throwawayEnvironment(
        container: ModelContainer, cursor: MirrorBootstrapCursor
    ) -> AppEnvironment {
        AppEnvironment(
            container: container, store: InMemorySecretStore(),
            mirrorTransport: StubTransport(alwaysRespondingWith: 200), mirrorCursor: cursor
        )
    }

    /// Le journal n'attend plus qu'on lui désigne un dossier : il est
    /// utilisable dès la construction de l'environnement.
    @Test func leJournalEstUtilisableSansDossier() throws {
        let container = try AppModelContainer.inMemory()
        let (cursor, cursorSuite) = freshCursor()
        defer { discard(cursorSuite) }
        let environment = throwawayEnvironment(container: container, cursor: cursor)
        let today = environment.journal.openToday()
        environment.journal.update("une note", for: today)
        environment.journal.saveNow()

        #expect(environment.journal.text(for: today) == "une note")
    }

    /// La garantie la plus visible de la tranche, et celle qu'aucun test ne
    /// portait : sans le `refresh()` que `CairnApp.init` fait suivre la
    /// maintenance, le premier lancement après la reprise montre un journal
    /// vide alors que la base vient d'en recevoir toutes les notes.
    ///
    /// Reproduit la production à la lettre, ce que
    /// `laMaintenanceDeclencheLaReprise` ne fait pas : là-bas le même
    /// `ModelContext` sert des deux côtés, ici la reprise reçoit un contexte
    /// **neuf** — comme `StoreMaintenance.run(ModelContext(container))` dans
    /// `CairnApp.init` — pendant que `JournalStore` tient, lui,
    /// `container.mainContext`. C'est précisément cet écart-là qui rend le
    /// `refresh()` nécessaire, et qu'un contexte partagé masquait.
    @Test func laRepriseNEstVisibleQuApresLeRefresh() throws {
        let container = try AppModelContainer.inMemory()
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "journal-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "reprise".write(
            to: folder.appending(path: "2026-08-17.md"), atomically: true, encoding: .utf8
        )

        let (defaults, suiteName) = freshJournalDefaults()
        defer { discardJournalDefaults(suiteName) }
        let cache = freshCacheDirectory()
        defer { discardCache(cache) }
        defaults.set(folder.path, forKey: JournalSettings.folderPathKey)
        let (cursor, cursorSuite) = freshCursor()
        defer { discard(cursorSuite) }

        // Construit avant la reprise, comme dans `CairnApp.init` : le journal
        // est bâti sur ce que la base tenait à cet instant, c'est-à-dire rien.
        let environment = throwawayEnvironment(container: container, cursor: cursor)
        #expect(environment.journal.notes.isEmpty)

        try StoreMaintenance.run(
            ModelContext(container), cacheDirectory: cache, defaults: defaults
        )
        // Toujours rien : le `mainContext` ne voit pas de lui-même ce qu'un
        // autre contexte vient d'insérer. C'est ce que ce test doit
        // établir avant tout — sans quoi le `refresh()` de la ligne suivante
        // serait vérifié par un test qui passerait aussi bien sans lui.
        #expect(environment.journal.notes.isEmpty)
        environment.journal.refresh()

        #expect(environment.journal.notes.count == 1)
        #expect(environment.journal.text(for: DateKey(raw: "2026-08-17")!) == "reprise")
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
        let cache = freshCacheDirectory()
        defer { discardCache(cache) }
        defaults.set(folder.path, forKey: JournalSettings.folderPathKey)

        try StoreMaintenance.run(context, cacheDirectory: cache, defaults: defaults)

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
        let cache = freshCacheDirectory()
        defer { discardCache(cache) }
        defaults.set(folder.path, forKey: JournalSettings.folderPathKey)

        try StoreMaintenance.run(context, cacheDirectory: cache, defaults: defaults)

        #expect(defaults.string(forKey: JournalSettings.importNoticeKey) == nil)
    }
}
