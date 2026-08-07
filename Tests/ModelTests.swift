import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("Model")
struct ModelTests {
    @Test(
        "le nom du store choisi ne dépend que de isTesting et isDemo, testing prioritaire",
        arguments: [
            (isTesting: true, isDemo: true, expected: "Cairn-tests.store"),
            (isTesting: true, isDemo: false, expected: "Cairn-tests.store"),
            (isTesting: false, isDemo: true, expected: "Cairn-demo.store"),
            (isTesting: false, isDemo: false, expected: "Cairn.store"),
        ]
    )
    func storeFileNameChoosesTheRightFile(
        case testCase: (isTesting: Bool, isDemo: Bool, expected: String)
    ) {
        let name = AppModelContainer.storeFileName(
            isTesting: testCase.isTesting, isDemo: testCase.isDemo
        )
        // The one property that matters above the rest: under test, this can
        // never be the production file name — that is what keeps the suite from
        // opening the user's real 132 MB store, as it once did.
        if testCase.isTesting { #expect(name != "Cairn.store") }
        #expect(name == testCase.expected)
    }

    @Test("XCTestConfigurationFilePath est bien présente pendant la suite")
    func detectsTestEnvironment() {
        // The entire 132 MB store guard rests on this one line reading true.
        // `storeFileNameChoosesTheRightFile` only proves the pure function is
        // correct for whatever `isTesting` it is handed — nothing until now
        // asserted that the real detection, running right now, actually
        // produces `true`.
        #expect(ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
    }

    @Test("une activité survit à un aller-retour en base")
    func persistsActivity() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let activity = Activity(stravaID: 42, name: "Sortie du matin", sportType: .ride)
        activity.distance = 42_195
        activity.startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let track = [
            Coordinate(latitude: 45.75, longitude: 4.83),
            Coordinate(latitude: 45.80, longitude: 4.90),
        ]
        activity.apply(simplifiedCoordinates: track)
        activity.apply(boundingBox: BoundingBox(coordinates: track)!)
        context.insert(activity)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Activity>())
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Sortie du matin")
        #expect(fetched[0].sportType == .ride)
        #expect(fetched[0].simplifiedCoordinates == track)
        #expect(fetched[0].boundingBox == BoundingBox(coordinates: track))
        #expect(fetched[0].minLat == 45.75)
        #expect(fetched[0].maxLon == 4.90)
    }

    @Test("les streams sont liés et relisibles")
    func persistsStreams() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)

        let activity = Activity(stravaID: 7, name: "Test", sportType: .run)
        let streams = ActivityStreams()
        streams.pointCount = 3
        streams.altitude = TrackBlob.encode(scalars: [100, 110, 120])
        streams.activity = activity
        activity.streams = streams
        context.insert(activity)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Activity>())
        let altitude = fetched[0].streams.flatMap { $0.altitude }
        #expect(altitude.map(TrackBlob.decodeScalars) == [100, 110, 120])
    }

    @Test("le type de sport Strava inconnu retombe sur other")
    func mapsUnknownSport() {
        #expect(SportType(stravaValue: "Ride") == .ride)
        #expect(SportType(stravaValue: "TrailRun") == .trailRun)
        #expect(SportType(stravaValue: "Kitesurf") == .other)
    }

    @Test("la FC moyenne devient triable sans fréquence enregistrée")
    func exposesSortableHeartRate() {
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .ride)

        // `Optional` is not `Comparable`, so the column needs a value; zero puts
        // the monitor-less activities at one end rather than scattering them.
        #expect(activity.averageHeartrateOrZero == 0)
        activity.averageHeartrate = 148
        #expect(activity.averageHeartrateOrZero == 148)
    }

    @Test("l'état de synchro persiste sa file d'attente")
    func persistsSyncState() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let state = SyncState()
        state.pendingStreamIDs = [1, 2, 3]
        state.lastSummaryEpoch = 1_700_000_000
        context.insert(state)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SyncState>())
        #expect(fetched[0].pendingStreamIDs == [1, 2, 3])
        #expect(fetched[0].lastSummaryEpoch == 1_700_000_000)
    }
}
