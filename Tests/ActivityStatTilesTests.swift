import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("ActivityDetailView.statTiles")
@MainActor
struct ActivityStatTilesTests {
    private func makeActivity(
        in context: ModelContext, id: Int64, sport: SportType
    ) -> Activity {
        let activity = Activity(stravaID: id, name: "Sortie", sportType: sport)
        activity.distance = 9_000
        activity.movingTime = 2905
        activity.elapsedTime = 2905
        activity.averageSpeed = 9_000 / 2905
        context.insert(activity)
        return activity
    }

    private func value(_ tiles: [ActivityDetailView.StatTileModel], _ title: String)
        -> String? {
        tiles.first { $0.title == title }?.value
    }

    @Test("la cadence d'une course est doublée et en ppm")
    func runCadenceInStepsPerMinute() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 1, sport: .run)
        activity.averageCadence = 89

        let tiles = ActivityDetailView.statTiles(for: activity)
        #expect(value(tiles, "Cadence") == "178 ppm")
    }

    @Test("la cadence d'une sortie vélo reste en rpm")
    func rideCadenceStaysRPM() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 2, sport: .ride)
        activity.averageCadence = 89

        let tiles = ActivityDetailView.statTiles(for: activity)
        #expect(value(tiles, "Cadence") == "89 rpm")
    }

    @Test("les calories s'affichent dès que Strava les a données")
    func showsCalories() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 3, sport: .run)
        activity.calories = 812

        let tiles = ActivityDetailView.statTiles(for: activity)
        #expect(value(tiles, "Calories") == "812 kcal")
    }

    @Test("une mesure absente n'occupe pas de tuile")
    func omitsMissingMeasurements() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 4, sport: .swim)

        let titles = ActivityDetailView.statTiles(for: activity).map(\.title)
        #expect(!titles.contains("FC moyenne"))
        #expect(!titles.contains("Puissance moyenne"))
        #expect(!titles.contains("Cadence"))
        #expect(!titles.contains("Calories"))
        #expect(!titles.contains("Matériel"))
        // Ce qui reste est toujours là : la distance et le temps.
        #expect(titles.first == "Distance")
    }

    @Test("une puissance normalisée égale à la moyenne n'est pas répétée")
    func dropsRedundantNormalisedPower() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 5, sport: .run)
        activity.averageWatts = 308
        activity.weightedAverageWatts = 308

        let titles = ActivityDetailView.statTiles(for: activity).map(\.title)
        #expect(titles.contains("Puissance moyenne"))
        #expect(!titles.contains("Puissance normalisée"))
    }

    @Test("une puissance normalisée différente est bien affichée")
    func keepsDistinctNormalisedPower() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 6, sport: .ride)
        activity.averageWatts = 210
        activity.weightedAverageWatts = 245

        let tiles = ActivityDetailView.statTiles(for: activity)
        #expect(value(tiles, "Puissance normalisée") == "245 W")
    }

    @Test("un temps total identique au temps en mouvement n'est pas répété")
    func dropsRedundantElapsedTime() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = makeActivity(in: context, id: 7, sport: .run)

        var titles = ActivityDetailView.statTiles(for: activity).map(\.title)
        #expect(!titles.contains("Temps total"))

        activity.elapsedTime = 3200
        titles = ActivityDetailView.statTiles(for: activity).map(\.title)
        #expect(titles.contains("Temps total"))
    }
}
