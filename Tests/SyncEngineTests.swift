import Testing
import SwiftData
import Foundation
@testable import Cairn

/// Serves pages of canned summaries and records what was asked for.
private actor FakeSource: StravaSyncSource {
    private let pages: [[SummaryActivityDTO]]
    private(set) var requestedAfter: [Int] = []
    private(set) var streamRequests: [Int64] = []
    private(set) var gearRequests: [String] = []
    private(set) var detailRequests: [Int64] = []
    private(set) var photoRequests: [Int64] = []
    private(set) var downloadedURLs: [String] = []
    var listedPhotos: [PhotoDTO] = []
    var photosToReturn: PhotosSummaryDTO?
    var failPhotoDownload = false

    func setListedPhotos(_ photos: [PhotoDTO]) { listedPhotos = photos }
    func setPrimaryPhoto(_ summary: PhotosSummaryDTO?) { photosToReturn = summary }
    func setFailPhotoDownload(_ fail: Bool) { failPhotoDownload = fail }
    private var notFoundIDs: Set<Int64> = []
    private var failWithServerError = false
    var streamsToReturn = StreamSetDTO(
        latlng: StreamDTO(data: [[45.0, 4.0], [45.001, 4.001]]),
        distance: StreamDTO(data: [0, 131]),
        altitude: StreamDTO(data: [100, 110]), time: StreamDTO(data: [0, 10]),
        heartrate: nil, cadence: nil, watts: nil, velocity_smooth: nil,
        temp: nil, grade_smooth: nil, moving: nil
    )

    init(pages: [[SummaryActivityDTO]]) { self.pages = pages }

    func activities(
        after: Int, page: Int, perPage: Int
    ) async throws -> [SummaryActivityDTO] {
        requestedAfter.append(after)
        guard page - 1 < pages.count else { return [] }
        return pages[page - 1]
    }

    func setNotFound(_ ids: Set<Int64>) { notFoundIDs = ids }

    func setFailWithServerError(_ value: Bool) { failWithServerError = value }

    func streams(id: Int64) async throws -> StreamSetDTO {
        streamRequests.append(id)
        if failWithServerError {
            throw StravaError.http(500, "Internal Server Error")
        }
        if notFoundIDs.contains(id) {
            throw StravaError.http(404, "Record Not Found")
        }
        return streamsToReturn
    }

    func activityDetail(id: Int64) async throws -> DetailActivityDTO {
        detailRequests.append(id)
        return DetailActivityDTO(
            id: id, description: nil, calories: nil, device_name: nil,
            laps: nil, photos: photosToReturn
        )
    }

    func photos(id: Int64) async throws -> [PhotoDTO] {
        photoRequests.append(id)
        return listedPhotos
    }

    func imageData(from url: URL) async throws -> Data {
        downloadedURLs.append(url.absoluteString)
        if failPhotoDownload { throw StravaError.http(500, "CDN indisponible") }
        return Data("image-\(url.lastPathComponent)".utf8)
    }

    func athlete() async throws -> AthleteDTO {
        AthleteDTO(
            id: 1, firstname: "Test", lastname: "User", city: nil,
            country: nil, profile: nil, weight: nil
        )
    }

    func gear(id: String) async throws -> GearDTO {
        gearRequests.append(id)
        return GearDTO(
            id: id, name: "Vélo de test", brand_name: "Marque",
            model_name: "Modèle", distance: 12_345
        )
    }

    func rateLimitSnapshot() async -> RateLimitSnapshot? { nil }

    func delayBeforeNextRequest() async -> TimeInterval { 0 }
}

private func makeSummary(
    id: Int64, epoch: Int, sport: String = "Ride", gearID: String? = nil,
    photoCount: Int? = nil
) -> SummaryActivityDTO {
    SummaryActivityDTO(
        id: id, name: "Activité \(id)", sport_type: sport,
        start_date: Date(timeIntervalSince1970: Double(epoch)),
        start_date_local: Date(timeIntervalSince1970: Double(epoch)),
        timezone: nil, distance: 10_000, moving_time: 3600, elapsed_time: 3700,
        total_elevation_gain: 100, average_speed: 2.7, max_speed: 5,
        average_heartrate: nil, max_heartrate: nil, average_watts: nil,
        weighted_average_watts: nil, kilojoules: nil, average_cadence: nil,
        commute: nil, trainer: nil, manual: nil, private: nil,
        workout_type: nil, total_photo_count: photoCount,
        kudos_count: nil, achievement_count: nil, pr_count: nil,
        athlete_count: nil, start_latlng: nil, end_latlng: nil, gear_id: gearID,
        map: MapDTO(summary_polyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
    )
}

@Suite("SyncEngine — phase A")
@MainActor
struct SyncSummariesTests {
    @Test("importe toutes les pages jusqu'à une page vide")
    func importsAllPages() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000)],
            [makeSummary(id: 3, epoch: 3000)],
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        let imported = try await engine.syncSummaries()
        #expect(imported == 3)

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<Activity>()).count == 3)
    }

    @Test("une activité écartée est ignorée en phase A sans échouer ni entrer dans la file de la phase B")
    func discardedActivitySkippedDuringPhaseA() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(DiscardedActivity(stravaID: 5, name: "Sortie supprimée"))
        try context.save()

        let source = FakeSource(pages: [
            [makeSummary(id: 5, epoch: 1000), makeSummary(id: 6, epoch: 2000)]
        ])
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        // The skip must not surface as a sync failure, and must not cost a
        // phase B request: neither assertion alone would catch a regression
        // that only breaks the other.
        let imported = try await engine.syncSummaries()
        #expect(imported == 1)

        let after = ModelContext(container)
        #expect(try after.fetch(FetchDescriptor<Activity>()).count == 1)

        let snapshot = try await engine.stateSnapshot()
        // Proves both halves: not merely that 5 is missing (which a broken
        // enqueue would also satisfy), but that 6 — the one activity actually
        // imported — is exactly what got queued.
        #expect(snapshot.pendingStreamIDs == [6])
    }

    @Test("le curseur retient la date de la conservée, pas de l'écartée la plus récente")
    func cursorIgnoresDiscardedEvenWhenNewest() async throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        context.insert(DiscardedActivity(stravaID: 5, name: "Sortie supprimée"))
        try context.save()

        // 5 is discarded and the newer of the two; 6 is kept and older. A
        // cursor that advances on the discarded one would leave `restore`
        // powerless to bring 5 back on the next incremental sync.
        let source = FakeSource(pages: [
            [makeSummary(id: 6, epoch: 1000), makeSummary(id: 5, epoch: 3000)]
        ])
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        _ = try await engine.syncSummaries()

        #expect(try await engine.stateSnapshot().lastSummaryEpoch == 1000)
    }

    @Test("la trace simplifiée et la bbox sont renseignées dès la phase A")
    func fillsTrackInPhaseA() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let context = ModelContext(container)
        let activity = try context.fetch(FetchDescriptor<Activity>())[0]
        #expect(activity.hasTrack)
        #expect(!activity.simplifiedCoordinates.isEmpty)
    }

    @Test("les activités importées entrent dans la file d'attente des streams")
    func queuesStreams() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000)]
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let state = try await engine.stateSnapshot()
        #expect(Set(state.pendingStreamIDs) == [1, 2])
    }

    @Test("le curseur retient la date la plus récente")
    func advancesCursor() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 5000)]
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        #expect(try await engine.stateSnapshot().lastSummaryEpoch == 5000)
        #expect(try await engine.stateSnapshot().isInitialImportDone)
    }

    @Test("la deuxième synchro repart du curseur")
    func secondRunIsIncremental() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 5000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        _ = try await engine.syncSummaries()
        _ = try await engine.syncSummaries()

        let asked = await source.requestedAfter
        #expect(asked.first == 0)
        #expect(asked.contains(5000))
    }

    @Test("réimporter les mêmes activités ne duplique rien")
    func rerunIsIdempotent() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        _ = try await engine.syncSummaries()
        _ = try await engine.syncSummaries()

        let context = ModelContext(container)
        #expect(try context.fetch(FetchDescriptor<Activity>()).count == 1)
    }

    @Test("resynchroniser tout repart de zéro sans dupliquer")
    func resyncRereadsEverything() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 5000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        _ = try await engine.syncSummaries()
        // Simule un détail déjà récupéré, donc mis en cache pour toujours.
        let context = ModelContext(container)
        let activity = try context.fetch(FetchDescriptor<Activity>())[0]
        activity.detailFetchedAt = Date(timeIntervalSince1970: 1000)
        try context.save()
        #expect(try await engine.stateSnapshot().lastSummaryEpoch == 5000)

        try await engine.resyncEverything()

        // Le curseur est reparti de 0, sinon rien n'aurait été relu.
        let asked = await source.requestedAfter
        #expect(asked.filter { $0 == 0 }.count >= 2)
        // Et le cache du détail est invalidé, sinon une note modifiée sur
        // Strava ne serait jamais relue.
        let after = ModelContext(container)
        let reread = try after.fetch(FetchDescriptor<Activity>())
        #expect(reread.count == 1)
        #expect(reread[0].detailFetchedAt == nil)
    }

    @Test("resynchroniser tout laisse le détail d'une activité locale tel quel")
    func resyncLeavesLocalDetailAlone() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 5000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )

        _ = try await engine.syncSummaries()
        // A local activity, never touched by Strava — its cached detail must
        // survive a resync exactly as `resyncRereadsEverything` shows a synced
        // one's must not.
        let context = ModelContext(container)
        let manual = Activity(stravaID: 999, name: "Séance salle", sportType: .workout)
        manual.source = .manual
        manual.detailFetchedAt = Date(timeIntervalSince1970: 1000)
        context.insert(manual)
        try context.save()

        try await engine.resyncEverything()

        let after = ModelContext(container)
        let reread = try after.fetch(
            FetchDescriptor<Activity>(predicate: #Predicate { $0.stravaID == 999 })
        ).first
        #expect(reread?.detailFetchedAt != nil)
    }

    @Test("la progression retombe à idle en fin de synchro")
    func reportsProgress() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let progress = SyncProgress()
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: progress
        )

        _ = try await engine.syncSummaries()

        #expect(progress.phase == .idle)
        #expect(progress.lastRunAt != nil)
        #expect(!progress.isRunning)
    }
}

@Suite("SyncEngine — phase B")
@MainActor
struct SyncStreamsTests {
    @Test("vide la file d'attente et rattache les streams")
    func drainsQueue() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000)]
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let fetched = try await engine.syncStreams()

        #expect(fetched == 2)
        #expect(Set(await source.streamRequests) == [1, 2])
        #expect(try await engine.stateSnapshot().pendingStreamIDs.isEmpty)

        let context = ModelContext(container)
        let activities = try context.fetch(FetchDescriptor<Activity>())
        #expect(activities.allSatisfy { $0.streams?.latlng != nil })
        #expect(activities.allSatisfy { $0.streams?.pointCount == 2 })
    }

    @Test("une activité écartée pendant que la phase B attend ne coûte pas de requête")
    func discardedActivitySkippedDuringPhaseB() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000)]
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let context = ModelContext(container)
        let mapper = ImportMapper(context: context)
        let activity = try #require(try mapper.activity(stravaID: 1))
        try mapper.discard(activity)

        let fetched = try await engine.syncStreams()

        #expect(fetched == 1)
        // Only 2's request should have gone out — spending one on 1 is exactly
        // the quota waste the brief forbids, and the queue entry has to be
        // gone too, or the next run would re-evaluate it every time.
        #expect(await source.streamRequests == [2])
        #expect(try await engine.stateSnapshot().pendingStreamIDs.isEmpty)
    }

    @Test("respecte la limite passée et laisse le reste en attente")
    func honoursLimit() async throws {
        let source = FakeSource(pages: [
            [
                makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000),
                makeSummary(id: 3, epoch: 3000),
            ]
        ])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let fetched = try await engine.syncStreams(limit: 2)

        #expect(fetched == 2)
        #expect(try await engine.stateSnapshot().pendingStreamIDs.count == 1)
    }

    @Test("reprendre après un arrêt ne redemande pas ce qui est déjà là")
    func resumesWithoutRefetching() async throws {
        let source = FakeSource(pages: [
            [
                makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000),
                makeSummary(id: 3, epoch: 3000),
            ]
        ])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        _ = try await engine.syncStreams(limit: 1)
        _ = try await engine.syncStreams()

        let requests = await source.streamRequests
        #expect(requests.count == 3)
        #expect(Set(requests).count == 3)
    }

    @Test("une file vide ne déclenche aucune requête")
    func emptyQueueDoesNothing() async throws {
        let source = FakeSource(pages: [[]])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        #expect(try await engine.syncStreams() == 0)
        #expect(await source.streamRequests.isEmpty)
    }

    @Test("le détail n'est récupéré qu'une seule fois")
    func fetchesDetailOnce() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        try await engine.fetchDetailIfNeeded(stravaID: 1)
        let context = ModelContext(container)
        let first = try context.fetch(FetchDescriptor<Activity>())[0].detailFetchedAt
        #expect(first != nil)

        try await engine.fetchDetailIfNeeded(stravaID: 1)
        let second = try ModelContext(container)
            .fetch(FetchDescriptor<Activity>())[0].detailFetchedAt
        #expect(second == first)
    }

    @Test("une activité locale ne provoque aucune requête de détail")
    func skipsDetailForLocalActivities() async throws {
        let source = FakeSource(pages: [[]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        let context = ModelContext(container)
        let manual = Activity(stravaID: 99, name: "Séance salle", sportType: .workout)
        manual.source = .manual
        context.insert(manual)
        try context.save()

        try await engine.fetchDetailIfNeeded(stravaID: 99)

        #expect(await source.detailRequests.isEmpty)
        #expect(manual.detailFetchedAt == nil)
    }

    @Test("le matériel référencé est récupéré une fois et rattaché")
    func linksGear() async throws {
        let source = FakeSource(pages: [
            [
                makeSummary(id: 1, epoch: 1000, gearID: "b123"),
                makeSummary(id: 2, epoch: 2000, gearID: "b123"),
                makeSummary(id: 3, epoch: 3000),
            ]
        ])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        try await engine.syncGear()

        // Un seul appel réseau pour deux activités partageant le même vélo.
        #expect(await source.gearRequests == ["b123"])

        let context = ModelContext(container)
        let activities = try context.fetch(FetchDescriptor<Activity>())
            .sorted { $0.stravaID < $1.stravaID }
        #expect(activities[0].gear?.name == "Vélo de test")
        #expect(activities[1].gear?.name == "Vélo de test")
        #expect(activities[2].gear == nil)
        #expect(try context.fetch(FetchDescriptor<Gear>()).count == 1)
    }

    @Test("relancer syncGear ne redemande pas ce qui est déjà rattaché")
    func gearSyncIsIdempotent() async throws {
        let source = FakeSource(pages: [
            [makeSummary(id: 1, epoch: 1000, gearID: "b123")]
        ])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        try await engine.syncGear()
        try await engine.syncGear()

        #expect(await source.gearRequests == ["b123"])
    }

    @Test("syncAll enchaîne les deux phases")
    func syncAllRunsBothPhases() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        let progress = SyncProgress()
        let engine = SyncEngine(
            source: source, container: container, progress: progress
        )

        try await engine.syncAll()

        let context = ModelContext(container)
        let activity = try context.fetch(FetchDescriptor<Activity>())[0]
        #expect(activity.streams?.latlng != nil)
        #expect(progress.phase == .idle)
        #expect(try await engine.stateSnapshot().pendingStreamIDs.isEmpty)
    }

    @Test("une tâche déjà annulée n'émet aucune requête et laisse la file entière")
    func cancelledTaskFetchesNothing() async throws {
        let source = FakeSource(pages: [
            [
                makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000),
                makeSummary(id: 3, epoch: 3000),
            ]
        ])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let fetched = try await Task {
            // Cancel ourselves before the walk starts, so the first
            // cancellation check inside it fires deterministically.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.syncStreams()
        }.value

        #expect(fetched == 0)
        #expect(await source.streamRequests.isEmpty)
        // Nothing fetched means nothing lost: all three are still queued.
        #expect(try await engine.stateSnapshot().pendingStreamIDs.count == 3)
    }

    @Test("une activité supprimée consomme quand même le budget de requêtes")
    func notFoundActivityCountsAgainstLimit() async throws {
        let source = FakeSource(pages: [
            [
                makeSummary(id: 1, epoch: 1000), makeSummary(id: 2, epoch: 2000),
                makeSummary(id: 3, epoch: 3000),
            ]
        ])
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()
        await source.setNotFound([1, 2])

        // Two 404s exhaust a budget of two, even though nothing was imported.
        let fetched = try await engine.syncStreams(limit: 2)

        #expect(fetched == 0)
        #expect(await source.streamRequests.count == 2)
        #expect(try await engine.stateSnapshot().pendingStreamIDs == [3])
    }

    @Test("une erreur inattendue met la progression en échec au lieu de la figer")
    func unexpectedErrorReportsFailure() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let progress = SyncProgress()
        let engine = SyncEngine(
            source: source, container: try AppModelContainer.inMemory(),
            progress: progress
        )
        _ = try await engine.syncSummaries()
        await source.setFailWithServerError(true)

        await #expect(throws: StravaError.self) {
            _ = try await engine.syncStreams()
        }

        // The UI must not be left believing a sync is still running.
        #expect(!progress.isRunning)
        if case .failed = progress.phase {} else {
            Issue.record("expected .failed, got \(progress.phase)")
        }
        // The activity stays queued, so a retry picks it up.
        #expect(try await engine.stateSnapshot().pendingStreamIDs == [1])
    }
}

@Suite("SyncEngine — photos")
@MainActor
struct SyncPhotosTests {
    private func makeEngine() throws -> (FakeSource, SyncEngine, ModelContainer) {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        return (
            source,
            SyncEngine(source: source, container: container, progress: SyncProgress()),
            container
        )
    }

    private func photo(id: String, url: String) -> PhotoDTO {
        PhotoDTO(
            unique_id: id, urls: ["1800": url], caption: nil,
            created_at: nil, created_at_local: nil
        )
    }

    @Test("les photos listées sont enregistrées et téléchargées")
    func downloadsListedPhotos() async throws {
        let (source, engine, container) = try makeEngine()
        await source.setListedPhotos([
            photo(id: "a", url: "https://cdn.test/a.jpg"),
            photo(id: "b", url: "https://cdn.test/b.jpg"),
        ])
        _ = try await engine.syncSummaries()
        try await engine.fetchDetailIfNeeded(stravaID: 1)

        let context = ModelContext(container)
        let activity = try context.fetch(FetchDescriptor<Activity>())[0]
        #expect(activity.orderedPhotos.map(\.uniqueID) == ["a", "b"])
        // Bytes, not links: Strava's photo URLs are signed and expire, so a
        // stored address is a dead photo within months.
        #expect(activity.orderedPhotos.allSatisfy { $0.data != nil })
        #expect(await source.downloadedURLs.count == 2)
    }

    @Test("sans l'endpoint non documenté, la photo principale documentée reste")
    func fallsBackToTheDocumentedPrimary() async throws {
        // The listing endpoint is in no published spec and may be withdrawn at
        // any moment. When it goes, an activity must still show its one
        // documented photo rather than none at all.
        let (source, engine, container) = try makeEngine()
        await source.setListedPhotos([])
        await source.setPrimaryPhoto(
            PhotosSummaryDTO(count: 3, primary: photo(id: "p", url: "https://cdn.test/p.jpg"))
        )
        _ = try await engine.syncSummaries()
        try await engine.fetchDetailIfNeeded(stravaID: 1)

        let context = ModelContext(container)
        let activity = try context.fetch(FetchDescriptor<Activity>())[0]
        #expect(activity.photos.map(\.uniqueID) == ["p"])
        #expect(activity.photos[0].data != nil)
    }

    @Test("un téléchargement en échec ne fait pas échouer la synchro")
    func aFailedDownloadKeepsTheRow() async throws {
        // Photos are the one part of an activity whose absence costs only a
        // picture. A CDN hiccup must not cost the run its tracks — and the row
        // stays so the next pass retries it instead of starting from nothing.
        let (source, engine, container) = try makeEngine()
        await source.setListedPhotos([photo(id: "a", url: "https://cdn.test/a.jpg")])
        await source.setFailPhotoDownload(true)
        _ = try await engine.syncSummaries()
        try await engine.fetchDetailIfNeeded(stravaID: 1)

        let context = ModelContext(container)
        let activity = try context.fetch(FetchDescriptor<Activity>())[0]
        #expect(activity.photos.count == 1)
        #expect(activity.photos[0].data == nil)
        #expect(activity.detailFetchedAt != nil)
    }
}

@Suite("SyncEngine — photos des activités déjà détaillées")
@MainActor
struct PhotosForAlreadyDetailedTests {
    @Test("une activité dont le détail date d'hier cherche quand même ses photos")
    func looksForPhotosOnAnOldActivity() async throws {
        // The case that mattered: every activity synced before photos existed
        // already carries a detail date. While both lived behind the same
        // marker, opening one asked Strava nothing and no photo ever arrived.
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        let context = ModelContext(container)
        let activity = try context.fetch(FetchDescriptor<Activity>())[0]
        activity.detailFetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try context.save()

        await source.setListedPhotos([
            PhotoDTO(
                unique_id: "a", urls: ["1800": "https://cdn.test/a.jpg"],
                caption: nil, created_at: nil, created_at_local: nil
            )
        ])
        try await engine.fetchDetailIfNeeded(stravaID: 1)

        let reread = ModelContext(container)
        let after = try reread.fetch(FetchDescriptor<Activity>())[0]
        #expect(after.photos.count == 1)
        #expect(after.photos[0].data != nil)
        // The detail itself must not be re-fetched: it was already there, and
        // asking again would cost a request for nothing.
        #expect(await source.detailRequests.isEmpty)
    }

    @Test("un compte de photos à zéro ne coûte aucune requête")
    func aKnownZeroCostsNothing() async throws {
        // Strava's own summary said there are none. Asking anyway would be one
        // wasted request per activity opened, against a quota of 2000 a day.
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000, photoCount: 0)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()
        try await engine.fetchDetailIfNeeded(stravaID: 1)

        #expect(await source.photoRequests.isEmpty)
        let context = ModelContext(container)
        // Marked as looked at all the same, so it is not reconsidered on every
        // single open.
        #expect(try context.fetch(FetchDescriptor<Activity>())[0].photosFetchedAt != nil)
    }

    @Test("la recherche de photos n'a lieu qu'une fois")
    func onlyLooksOnce() async throws {
        let source = FakeSource(pages: [[makeSummary(id: 1, epoch: 1000, photoCount: 2)]])
        let container = try AppModelContainer.inMemory()
        let engine = SyncEngine(
            source: source, container: container, progress: SyncProgress()
        )
        _ = try await engine.syncSummaries()

        try await engine.fetchDetailIfNeeded(stravaID: 1)
        try await engine.fetchDetailIfNeeded(stravaID: 1)

        #expect(await source.photoRequests == [1])
    }
}
