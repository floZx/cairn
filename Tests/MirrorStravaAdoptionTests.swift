import Testing
import Foundation
import SwiftData
@testable import Cairn

/// Le rapprochement d'avant l'envoi : quand le téléphone a déjà importé une
/// sortie que le Mac vient de télécharger de son côté, les deux la désignent
/// par le même identifiant Strava et deux `uuid` différents. Sans ce
/// rapprochement, le miroir porterait deux lignes pour une sortie.
@Suite("Adoption de l'uuid d'une sortie Strava")
struct MirrorStravaAdoptionTests {
    private func reponse(_ objets: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: objets)
    }

    @MainActor
    private func moteur(
        _ container: ModelContainer, _ transport: StubTransport
    ) throws -> (MirrorEngine, String) {
        let (cursor, suiteName) = freshCursor()
        return (
            MirrorEngine(
                client: MirrorClient(store: try configuredStore(), transport: transport),
                container: container, progress: MirrorProgress(), cursor: cursor
            ),
            suiteName
        )
    }

    /// Le cas nominal, et la raison d'être de tout ceci.
    @Test func lUUIDDuMiroirEstRepris() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let sortie = Activity(stravaID: 4242, name: "Footing", sportType: .run)
        let localAvant = sortie.uuid
        context.insert(sortie)
        try context.save()

        // Une entrée d'outbox, comme le ferait l'enregistrement du magasin.
        context.insert(MirrorOutbox(table: "activity", rowUUID: sortie.uuid, isDeletion: false))
        try context.save()

        let duTelephone = "11111111-2222-3333-4444-555555555555"
        let transport = StubTransport(
            responses: [(reponse([["uuid": duTelephone, "strava_id": 4242]]), 200)],
            thenAlways: Data(), status: 201
        )
        let (engine, suiteName) = try await moteur(container, transport)
        defer { discard(suiteName) }

        try await engine.push()

        let relue = try #require(
            try ModelContext(container).fetch(FetchDescriptor<Activity>()).first
        )
        #expect(relue.uuid == duTelephone)
        #expect(relue.uuid != localAvant)
        // Et c'est bien sous cette identité-là que la ligne est partie.
        let envoyes = await transport.upsertedUUIDs(table: "activity")
        #expect(envoyes.contains(duTelephone))
    }

    /// Une sortie que le miroir ne connaît pas garde son identité.
    @Test func uneSortieInconnueGardeSonUUID() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let sortie = Activity(stravaID: 7, name: "Footing", sportType: .run)
        let avant = sortie.uuid
        context.insert(sortie)
        context.insert(MirrorOutbox(table: "activity", rowUUID: sortie.uuid, isDeletion: false))
        try context.save()

        let transport = StubTransport(
            responses: [(reponse([]), 200)], thenAlways: Data(), status: 201
        )
        let (engine, suiteName) = try await moteur(container, transport)
        defer { discard(suiteName) }

        try await engine.push()

        let relue = try #require(
            try ModelContext(container).fetch(FetchDescriptor<Activity>()).first
        )
        #expect(relue.uuid == avant)
    }

    /// Une activité saisie à la main porte `stravaID` à zéro : rien à
    /// rapprocher, et surtout rien à demander — la question « qui d'autre n'a
    /// pas d'identifiant » n'a pas de sens.
    @Test func uneActiviteManuelleNeSeDemandePas() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let sortie = Activity(stravaID: 0, name: "Séance libre", sportType: .workout)
        context.insert(sortie)
        context.insert(MirrorOutbox(table: "activity", rowUUID: sortie.uuid, isDeletion: false))
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let (engine, suiteName) = try await moteur(container, transport)
        defer { discard(suiteName) }

        try await engine.push()

        let demandes = await transport.requests().filter {
            $0.httpMethod == "GET" && ($0.url?.query?.contains("strava_id=in.") ?? false)
        }
        #expect(demandes.isEmpty)
    }

    /// Le miroir peut rendre un `uuid` qu'une autre sortie porte déjà ici —
    /// ce serait un défaut, mais l'écrasement serait silencieux.
    @Test func unUUIDDejaPrisNEstPasVole() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let voisine = Activity(stravaID: 1, name: "Voisine", sportType: .run)
        let sortie = Activity(stravaID: 4242, name: "Footing", sportType: .run)
        let sien = sortie.uuid
        context.insert(voisine)
        context.insert(sortie)
        context.insert(MirrorOutbox(table: "activity", rowUUID: sortie.uuid, isDeletion: false))
        try context.save()

        let transport = StubTransport(
            responses: [(reponse([["uuid": voisine.uuid, "strava_id": 4242]]), 200)],
            thenAlways: Data(), status: 201
        )
        let (engine, suiteName) = try await moteur(container, transport)
        defer { discard(suiteName) }

        try await engine.push()

        let relues = try ModelContext(container).fetch(FetchDescriptor<Activity>())
        #expect(Set(relues.map(\.uuid)).count == 2)
        #expect(relues.first { $0.stravaID == 4242 }?.uuid == sien)
    }
}
