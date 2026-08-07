import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("DemoData")
@MainActor
struct DemoDataTests {
    /// 7 August 2026, so the generated history is a fixed range.
    private let now = Date(timeIntervalSince1970: 1_786_000_000)

    @Test("le mode démo est désactivé sauf variable d'environnement")
    func staysOffByDefault() throws {
        // The suite runs without STRAVALOCAL_DEMO set, which is the point: a
        // guard that could ever be true by accident would risk writing invented
        // activities into a real library.
        #expect(DemoData.isEnabled == false)

        let context = ModelContext(try AppModelContainer.inMemory())
        try DemoData.populateIfNeeded(context, now: now)
        #expect(try context.fetch(FetchDescriptor<Activity>()).isEmpty)
    }

    @Test("la bibliothèque est reproductible à l'identique")
    func generatesTheSameLibraryTwice() {
        let first = DemoData.library(now: now)
        let second = DemoData.library(now: now)

        // A fixed seed rather than the system generator: without it a screenshot
        // could never be retaken.
        #expect(first.count == second.count)
        #expect(first.map(\.name) == second.map(\.name))
        #expect(first.map(\.distance) == second.map(\.distance))
        #expect(first.map(\.startDate) == second.map(\.startDate))
    }

    @Test("la bibliothèque couvre dix-huit mois et plusieurs sports")
    func coversEnoughToBeWorthShowing() {
        let library = DemoData.library(now: now)
        let calendar = Calendar(identifier: .gregorian)

        #expect(library.count > 150)
        // Eighteen months, so the twelve-month window has a full year behind it
        // to compare against.
        let oldest = library.map(\.startDate).min()!
        let months = calendar.dateComponents([.month], from: oldest, to: now).month ?? 0
        #expect(months >= 16)
        // Nothing dated in the future, which would read as a bug in a screenshot.
        #expect(library.allSatisfy { $0.startDate <= now })

        let sports = Set(library.map(\.sportType))
        #expect(sports.count >= 4)
        #expect(sports.contains(.trailRun))
        #expect(sports.contains(.ride))
    }

    @Test("les sorties extérieures ont une trace, la salle n'en a pas")
    func buildsTracksOnlyWhereTheyBelong() {
        let library = DemoData.library(now: now)

        let outdoors = library.filter { $0.sportType == .trailRun }
        #expect(!outdoors.isEmpty)
        for activity in outdoors {
            #expect(activity.hasTrack)
            // Both are needed: the global map and the geographic search read the
            // simplified track and the bounding box, not the streams.
            #expect(activity.simplifiedCoordinates.count > 2)
            #expect(activity.boundingBox != nil)
            #expect((activity.streams?.coordinates.count ?? 0) > 2)
        }

        // A gym session has neither track nor distance, and the app has to stay
        // honest about that — a demo library of tidy outdoor outings would hide
        // how it handles them.
        let indoors = library.filter { $0.sportType == .workout }
        #expect(!indoors.isEmpty)
        #expect(indoors.allSatisfy { !$0.hasTrack && $0.distance == 0 })
        #expect(indoors.allSatisfy { $0.movingTime > 0 })
    }

    @Test("les traces sont des boucles fermées de longueur plausible")
    func generatesClosedPlausibleLoops() {
        let ride = DemoData.library(now: now).first { $0.sportType == .ride }
        let track = try! #require(ride?.streams?.coordinates)

        #expect(track.first == track.last)
        // The measured geometry has to agree with the distance the summary
        // claims, or the detail view would contradict the list.
        let measured = DistanceAxis.cumulativeMetres(along: track).last ?? 0
        let claimed = ride!.distance
        #expect(abs(measured - claimed) / claimed < 0.35)
    }

    @Test("le générateur ne reste pas bloqué sur une seule valeur")
    func generatorProducesVariety() {
        var generator = SeededGenerator(seed: 1)
        let values = (0..<50).map { _ in generator.double(in: 0...1) }

        #expect(Set(values).count > 40)
        #expect(values.allSatisfy { $0 >= 0 && $0 <= 1 })

        // Zero is a fixed point of xorshift: seeded with it, an unguarded
        // generator returns nothing but zero for ever.
        var fromZero = SeededGenerator(seed: 0)
        let afterZero = (0..<10).map { _ in fromZero.next() }
        #expect(Set(afterZero).count == 10)
    }
}
