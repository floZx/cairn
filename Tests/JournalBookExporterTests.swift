import Testing
import Foundation
@testable import Cairn

@Suite("Le PDF du carnet")
@MainActor
struct JournalBookExporterTests {
    @Test("un document HTML ressort en PDF")
    func htmlBecomesAPDF() async throws {
        // Le seul test qui traverse WebKit : il ne prouve pas la mise en page,
        // seulement que la chaîne va jusqu'au bout et rend bien un PDF.
        let data = try await JournalBookExporter.pdf(
            from: "<!DOCTYPE html><html><body><h1>Carnet</h1></body></html>"
        )
        #expect(data.count > 0)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "%PDF")
    }
}
