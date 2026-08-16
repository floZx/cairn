import Testing
import Foundation
import SwiftData
@testable import Cairn

/// Un transport qui refuse tout le Storage et accepte tout le reste : la
/// panne que ce fichier doit reproduire est une politique de bucket mal posée,
/// pas un réseau coupé. `StubTransport` ne sait pas répondre selon la requête,
/// et c'est précisément la distinction qui compte ici.
private actor StorageRefusingTransport: MirrorTransport {
    private(set) var paths: [String] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        paths.append(path)
        let refused = path.hasPrefix("/storage/v1/")
        let response = HTTPURLResponse(
            url: request.url!, statusCode: refused ? 403 : 200,
            httpVersion: nil, headerFields: nil
        )!
        return (Data(), response)
    }
}

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

    /// Un téléversement refusé est compté, pas fatal : les lignes doivent
    /// partir quand même. Les politiques de `storage.objects` sont le seul
    /// point du miroir jamais éprouvé contre un vrai projet ; un 403 durable
    /// ferait autrement échouer l'amorçage avant la première ligne, et une
    /// ligne pointant vers un objet absent reste une lecture dégradée là où
    /// tout bloquer ne laisse rien du tout.
    @Test func unTeleversementRefuseNInterrompPasLenvoiDesLignes() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let photo = ActivityPhoto(uniqueID: "p1")
        photo.data = Data(repeating: 0xAB, count: 128)
        context.insert(photo)
        context.insert(Athlete(stravaID: 1))
        try context.save()

        let transport = StorageRefusingTransport()
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let progress = MirrorProgress()
        let engine = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: transport),
            container: container, progress: progress, cursor: cursor
        )

        try await engine.bootstrap()

        #expect(progress.failedUploads == 1)
        #expect(progress.statusText.contains("1 fichier non envoyé"))
        // Les lignes sont bien parties malgré le refus du bucket.
        let paths = await transport.paths
        #expect(paths.contains("/rest/v1/athlete"))
        #expect(paths.contains("/rest/v1/activity_photo"))
        // Et la photo reste due : `mirroredAt` intact, donc réessayée plus tard.
        let reloaded = try ModelContext(container).fetch(FetchDescriptor<ActivityPhoto>())
        #expect(reloaded.first?.mirroredAt == nil)
    }

    /// Une passe qui finit par réussir remet le compteur à zéro : il décrit le
    /// dernier balayage, il ne s'accumule pas.
    @Test func unePasseReussieEffaceLeCompteurDechecs() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let photo = ActivityPhoto(uniqueID: "p1")
        photo.data = Data(repeating: 0xAB, count: 128)
        context.insert(photo)
        try context.save()

        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }
        let progress = MirrorProgress()
        let refusing = StubTransport(alwaysRespondingWith: 403)
        let refused = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: refusing),
            container: container, progress: progress, cursor: cursor
        )
        #expect(try await refused.uploadPendingBlobs() == 1)
        #expect(progress.failedUploads == 1)

        let accepting = StubTransport(alwaysRespondingWith: 200)
        let accepted = MirrorEngine(
            client: MirrorClient(store: try configuredStore(), transport: accepting),
            container: container, progress: progress, cursor: cursor
        )
        #expect(try await accepted.uploadPendingBlobs() == 0)
        #expect(progress.failedUploads == 0)
    }
}
