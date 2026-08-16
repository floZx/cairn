import Testing
import Foundation
import SwiftData
@testable import Cairn

// `MirrorProgress` is `@MainActor` (task 6's own interface), so every test
// that builds one needs to be too — same reasoning as `MirrorBootstrapTests`.
@Suite("Push du miroir")
@MainActor
struct MirrorPushTests {
    /// Une entrée d'outbox part, puis disparaît. Une entrée qui survivrait à son
    /// envoi ferait repartir la même ligne à chaque passage.
    @Test func uneEntreeEnvoyeeEstConsommee() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        let pending = MirrorOutbox(table: "weight_entry", rowUUID: entry.uuid, isDeletion: false)
        context.insert(pending)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.push()

        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
        #expect(await transport.requests().count == 1)
    }

    /// Un envoi qui échoue laisse l'entrée en place. C'est toute la raison
    /// d'être d'une outbox : une coupure ne doit rien perdre.
    @Test func unEnvoiQuiEchoueLaisseLEntreeEnPlace() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        let pending = MirrorOutbox(table: "weight_entry", rowUUID: entry.uuid, isDeletion: false)
        context.insert(pending)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 500)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        _ = try? await engine.push()

        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).count == 1)
    }

    /// Une suppression part en `deleted_at`, jamais en DELETE. Effacer la ligne
    /// pour de bon la ferait revenir au prochain amorçage.
    @Test func uneSuppressionPartEnEffacementDoux() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let pending = MirrorOutbox(table: "weight_entry", rowUUID: "disparue", isDeletion: true)
        context.insert(pending)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.push()

        let sent = await transport.requests()
        let body = String(data: sent[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("deleted_at"))
        // Une mise à jour, pas un upsert. Voir `MirrorClient.softDelete`.
        #expect(sent[0].httpMethod == "PATCH")
        #expect(sent[0].url?.query?.contains("uuid=eq.disparue") == true)
    }

    /// Dix modifications de la même ligne avant un seul push ne laissent
    /// qu'une seule requête, pas dix — et l'outbox est vidée entièrement,
    /// entrées périmées comprises, pas seulement la dernière.
    @Test func dixModificationsDeLaMemeLigneNeFontQuUneRequete() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        var changedAt = Date.distantPast
        for _ in 0..<10 {
            changedAt = changedAt.addingTimeInterval(1)
            context.insert(
                MirrorOutbox(
                    table: "weight_entry", rowUUID: entry.uuid, isDeletion: false,
                    changedAt: changedAt
                )
            )
        }
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.push()

        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
        #expect(await transport.requests().count == 1)
    }

    /// Une création suivie d'une suppression, dans deux sauvegardes
    /// distinctes avant tout push : seule la suppression part, en `PATCH`,
    /// jamais l'upsert de la création.
    @Test func creationPuisSuppressionNEnvoieQueLaSuppression() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let uuid = UUID().uuidString
        let created = Date.distantPast.addingTimeInterval(1)
        let deleted = Date.distantPast.addingTimeInterval(2)
        context.insert(
            MirrorOutbox(table: "weight_entry", rowUUID: uuid, isDeletion: false, changedAt: created)
        )
        context.insert(
            MirrorOutbox(table: "weight_entry", rowUUID: uuid, isDeletion: true, changedAt: deleted)
        )
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.push()

        let sent = await transport.requests()
        #expect(sent.count == 1)
        #expect(sent[0].httpMethod == "PATCH")
        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
    }

    /// Une entrée dont la ligne locale a disparu sans marque `isDeletion` —
    /// tuée entre deux sauvegardes — est jetée sans bruit : pas d'erreur, pas
    /// de requête, l'outbox se vide quand même.
    @Test func uneLigneDisparueSansMarqueEstJeteeSansBruit() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let pending = MirrorOutbox(table: "weight_entry", rowUUID: "jamais-montee", isDeletion: false)
        context.insert(pending)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 201)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.push()

        #expect(await transport.requests().isEmpty)
        #expect(try context.fetch(FetchDescriptor<MirrorOutbox>()).isEmpty)
    }
}
