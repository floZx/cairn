import Testing
import Foundation
import SwiftData
@testable import Cairn

// `MirrorProgress` is `@MainActor` (task 6's own interface), so every test
// that constructs one needs to run there too — `Tests/MirrorBootstrapTests.swift`
// follows the same rule for the same reason.
@Suite("Blobs du miroir")
@MainActor
struct MirrorBlobTests {
    /// Une photo part une fois, dans son bucket, au chemin que sa ligne
    /// annonce. Un chemin qui ne correspondrait pas à la ligne donnerait une
    /// image introuvable depuis le web.
    @Test func unePhotoPartAuCheminQueSaLigneAnnonce() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let photo = ActivityPhoto(uniqueID: "p1")
        photo.data = Data(repeating: 0xAB, count: 128)
        photo.activityUUID = "a1"
        context.insert(photo)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 200)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.uploadPendingBlobs()

        let paths = await transport.requests().compactMap(\.url?.path)
        #expect(paths.contains { $0.hasSuffix("/storage/v1/object/photos/u/p1") })
    }

    /// Une photo sans octets ne produit aucune requête. Les activités
    /// synchronisées avant l'arrivée des photos en ont, et téléverser du vide
    /// coûterait 852 requêtes pour rien.
    @Test func unePhotoSansOctetsNeProduitAucuneRequete() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let photo = ActivityPhoto(uniqueID: "p1")
        photo.data = nil
        context.insert(photo)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 200)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.uploadPendingBlobs()

        #expect(await transport.requests().isEmpty)
    }

    /// Les onze flux d'`ActivityStreams` partent groupés dans un seul objet
    /// JSON, au chemin `storage_path` de la ligne — pas onze requêtes.
    @Test func lesFluxPartentGroupesDansUnSeulObjet() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let streams = ActivityStreams()
        streams.latlng = TrackBlob.encode(coordinates: [Coordinate(latitude: 1, longitude: 2)])
        streams.heartrate = TrackBlob.encode(scalars: [140, 150])
        context.insert(streams)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 200)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.uploadPendingBlobs()

        let requests = await transport.requests()
        let streamRequests = requests.filter {
            $0.url?.path.hasSuffix("/storage/v1/object/streams/u/\(streams.uuid)") ?? false
        }
        #expect(streamRequests.count == 1)

        let body = try #require(streamRequests.first?.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: String]
        )
        #expect(json.keys.sorted() == ["heartrate", "latlng"])
        let latlngBase64 = try #require(json["latlng"])
        let decoded = try #require(Data(base64Encoded: latlngBase64))
        #expect(TrackBlob.decodeCoordinates(decoded).count == 1)
    }

    /// Un flux sans aucun des onze tableaux ne produit aucune requête, comme
    /// une photo sans octets.
    @Test func desFluxVidesNeProduisentAucuneRequete() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(ActivityStreams())
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 200)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.uploadPendingBlobs()

        #expect(await transport.requests().isEmpty)
    }

    /// Un blob déjà envoyé — `mirroredAt` déjà posé — n'est pas renvoyé au
    /// deuxième appel : c'est ce qui évite de réexpédier 290 Mo à chaque
    /// amorçage rejoué.
    @Test func unBlobDejaEnvoyeNEstPasRenvoye() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let photo = ActivityPhoto(uniqueID: "p1")
        photo.data = Data(repeating: 0xAB, count: 128)
        context.insert(photo)
        try context.save()

        let transport = StubTransport(alwaysRespondingWith: 200)
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: MirrorProgress(), cursor: cursor
        )
        try await engine.uploadPendingBlobs()
        #expect(await transport.requests().count == 1)

        try await engine.uploadPendingBlobs()
        #expect(await transport.requests().count == 1)
    }
}
