import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Branchement du journal")
@MainActor
struct JournalWiringTests {
    /// Jamais `AppEnvironment(container:)` nu : il prend le vrai trousseau et
    /// les vraies préférences, et sur une machine où le miroir est configuré,
    /// l'enregistreur partirait pour de vrai.
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
}
