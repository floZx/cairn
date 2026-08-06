import Testing
import SwiftData
import Foundation
@testable import StravaLocal

/// Serves pages of canned summaries and records what was asked for.
private actor FakeSource: ActivitySource {
    private let pages: [[SummaryActivityDTO]]
    private(set) var requestedAfter: [Int] = []
    private(set) var streamRequests: [Int64] = []
    private(set) var gearRequests: [String] = []
    var streamsToReturn = StreamSetDTO(
        latlng: StreamDTO(data: [[45.0, 4.0], [45.001, 4.001]]),
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

    func streams(id: Int64) async throws -> StreamSetDTO {
        streamRequests.append(id)
        return streamsToReturn
    }

    func activityDetail(id: Int64) async throws -> DetailActivityDTO {
        DetailActivityDTO(
            id: id, description: nil, calories: nil, device_name: nil, laps: nil
        )
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
}

private func makeSummary(
    id: Int64, epoch: Int, sport: String = "Ride", gearID: String? = nil
) -> SummaryActivityDTO {
    SummaryActivityDTO(
        id: id, name: "Activité \(id)", sport_type: sport,
        start_date: Date(timeIntervalSince1970: Double(epoch)),
        start_date_local: Date(timeIntervalSince1970: Double(epoch)),
        timezone: nil, distance: 10_000, moving_time: 3600, elapsed_time: 3700,
        total_elevation_gain: 100, average_speed: 2.7, max_speed: 5,
        average_heartrate: nil, max_heartrate: nil, average_watts: nil,
        weighted_average_watts: nil, kilojoules: nil, average_cadence: nil,
        commute: nil, trainer: nil, manual: nil, `private`: nil,
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
