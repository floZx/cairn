import Testing
import os
@testable import Cairn

@Suite("Journalisation des échecs")
struct LogTests {
    private struct Panne: Error {}
    private let log = Logger(subsystem: "com.florianmaisonnial.Cairn.tests", category: "log")

    @Test func unSuccesRendSaValeur() {
        #expect(log.attempt("addition") { 1 + 1 } == 2)
    }

    @Test func unEchecRendNilAuLieuDeLever() {
        let valeur: Int? = log.attempt("panne") { throw Panne() }
        #expect(valeur == nil)
    }

    @Test func laVarianteAsynchroneFaitDeMeme() async {
        let valeur: Int? = await log.attempt("panne") {
            try await Task.sleep(for: .zero)
            throw Panne()
        }
        #expect(valeur == nil)
        #expect(await log.attempt("attente") { try await Task.sleep(for: .zero); return 3 } == 3)
    }
}
