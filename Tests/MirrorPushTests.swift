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

    /// Dix modifications de la même ligne avant un seul push laissent dix
    /// entrées d'outbox (task 8 ne déduplique pas) ; après le push, aucune
    /// ne doit rester — ni la plus récente, choisie pour l'envoi, ni les
    /// neuf autres, qui n'auraient jamais été revisitées si elles étaient
    /// restées en place.
    ///
    /// Ce test ne distingue pas, à lui seul, « la ligne la plus récente a
    /// été choisie pour l'envoi » de « la ligne a été résolue d'une manière
    /// ou d'une autre » : un seul modèle existant en local, un `Set` d'un
    /// seul `uuid` produirait une seule requête même sans le regroupement
    /// par `(table, uuid)` que `push()` documente. Ce qu'il vérifie
    /// vraiment — et que rien d'autre ne couvre — c'est que la purge efface
    /// bien les neuf doublons périmés, pas seulement l'entrée retenue.
    @Test func dixEntreesPourUneMemeLigneNeLaissentQuUneRequeteEtSontToutesPurgees() async throws {
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
        #expect(await transport.upsertedUUIDs(table: "weight_entry") == [entry.uuid])
    }

    /// Une création suivie d'une suppression, dans deux sauvegardes
    /// distinctes avant tout push : seule la suppression part, en `PATCH`,
    /// jamais l'upsert de la création. Le `WeightEntry` existe réellement en
    /// local — sans lui, l'entrée de création n'enverrait de toute façon
    /// rien (aucun modèle à retrouver), et le test ne prouverait rien sur le
    /// regroupement par `(table, uuid)` lui-même : avec un modèle bien
    /// présent, un push qui ne dédupliquerait pas enverrait un upsert *et*
    /// un `PATCH`, deux requêtes au lieu d'une.
    @Test func creationPuisSuppressionNEnvoieQueLaSuppression() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        let created = Date.distantPast.addingTimeInterval(1)
        let deleted = Date.distantPast.addingTimeInterval(2)
        context.insert(
            MirrorOutbox(
                table: "weight_entry", rowUUID: entry.uuid, isDeletion: false, changedAt: created
            )
        )
        context.insert(
            MirrorOutbox(
                table: "weight_entry", rowUUID: entry.uuid, isDeletion: true, changedAt: deleted
            )
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

    /// Une suppression qui échoue au milieu d'un lot ne doit pas défaire ce
    /// qui a déjà été confirmé ni tenter ce qui vient après : la première
    /// suppression, réussie, est purgée ; la seconde, en échec, et tout ce
    /// qui l'aurait suivi restent en place. `StubTransport(responses:)`
    /// scripte la séquence, contrairement à `alwaysRespondingWith`, qui ne
    /// peut pas distinguer un succès partiel d'un échec total.
    @Test func uneSuppressionQuiEchoueAuMilieuDUnLotLaisseLeResteEnPlace() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(MirrorOutbox(table: "weight_entry", rowUUID: "premiere", isDeletion: true))
        context.insert(MirrorOutbox(table: "weight_entry", rowUUID: "seconde", isDeletion: true))
        try context.save()

        // Triée par `(changedAt, rowUUID)` comme `pushRows` le fait lui-même :
        // les deux entrées ont le même `changedAt` par défaut (même
        // sauvegarde), donc "premiere" < "seconde" à l'ordre lexical décide,
        // et la première requête scriptée (204) correspond à "premiere".
        let transport = StubTransport(responses: [(Data(), 204), (Data(), 500)])
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        _ = try? await engine.push()

        let remaining = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.rowUUID == "seconde")
        #expect(await transport.requests().count == 2)
    }

    /// La faute critique relevée en revue : une purge qui re-interrogerait
    /// le magasin après le retour de la requête effacerait aussi une entrée
    /// écrite *pendant* l'aller-retour réseau — l'utilisateur modifie la
    /// ligne R juste après que le push a lu son état pour la pousser, avant
    /// que la réponse HTTP ne revienne. Ce test simule exactement ça : le
    /// transport, au moment où il reçoit la requête (donc après le `fetch`
    /// initial de `push()`, avant que `purge` ne tourne), écrit lui-même une
    /// nouvelle entrée d'outbox pour la même ligne depuis un second
    /// contexte — ce que ferait `MirrorRecorder` si l'utilisateur rééditait
    /// la pesée à cet instant précis.
    ///
    /// Avant la correction (une purge qui refait `context.fetch(predicate:
    /// table == … && uuids.contains(rowUUID))` après le retour de la
    /// requête), cette nouvelle entrée existe déjà dans le magasin au moment
    /// où `purge` tourne et se fait effacer avec l'originale — la
    /// modification de l'utilisateur ne repart alors plus jamais vers
    /// Supabase, silencieusement. Après la correction (`purge` ne supprime
    /// que les objets `MirrorOutbox` que `push()` avait déjà en main avant
    /// le premier envoi, via `entriesByRow`), l'entrée survit et attend le
    /// prochain push.
    @Test func unChangementEcritPendantLEnvoiNEstPasPurge() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let entry = WeightEntry(dateKey: DateKey(raw: "2026-08-16")!, weightKg: 70)
        context.insert(entry)
        context.insert(MirrorOutbox(table: "weight_entry", rowUUID: entry.uuid, isDeletion: false))
        try context.save()

        let rowUUID = entry.uuid
        let transport = MidFlightWriteTransport {
            let side = ModelContext(container)
            side.insert(MirrorOutbox(table: "weight_entry", rowUUID: rowUUID, isDeletion: false))
            try? side.save()
        }
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.push()

        let remaining = try context.fetch(FetchDescriptor<MirrorOutbox>())
        #expect(
            remaining.count == 1,
            "l'entrée écrite pendant l'envoi doit survivre à la purge, pas être effacée avec celle qui a été résolue"
        )
    }
}

/// A transport that runs a side effect the instant it receives a request,
/// before answering — used only to simulate a save landing *during* the
/// network round trip a push is waiting on, which no other transport in
/// `Tests/MirrorTestSupport.swift` can reproduce (`StubTransport` answers
/// from a fixed script, with no hook into the moment a request arrives).
/// Local to this file, on the same precedent as task 6's `FlakyTransport`.
private actor MidFlightWriteTransport: MirrorTransport {
    private let onSend: @Sendable () -> Void

    init(onSend: @escaping @Sendable () -> Void) {
        self.onSend = onSend
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        onSend()
        let response = HTTPURLResponse(
            url: URL(string: "https://x.supabase.co")!,
            statusCode: 201, httpVersion: nil, headerFields: nil
        )!
        return (Data(), response)
    }
}
