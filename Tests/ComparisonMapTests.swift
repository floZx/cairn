import Testing
import SwiftData
import AppKit
import MapKit
import Foundation
@testable import Cairn

@Suite("Carte de comparaison")
@MainActor
struct ComparisonMapTests {
    /// An activity with a two-point track, dated `daysAgo` before a fixed date.
    private func makeActivity(
        in context: ModelContext, id: Int64, daysAgo: Int, hasTrack: Bool = true
    ) -> Activity {
        let activity = Activity(stravaID: id, name: "Sortie \(id)", sportType: .ride)
        activity.startDate = Date(timeIntervalSince1970: 1_700_000_000)
            .addingTimeInterval(-Double(daysAgo) * 86_400)
        if hasTrack {
            activity.simplifiedTrack = TrackBlob.encode(coordinates: [
                Coordinate(latitude: 45.75, longitude: 4.83),
                Coordinate(latitude: 45.76, longitude: 4.84),
            ])
        }
        context.insert(activity)
        return activity
    }

    @Test("les couleurs suivent l'ordre chronologique, pas celui du Set")
    func assignsColorsDeterministically() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let oldest = makeActivity(in: context, id: 1, daysAgo: 30)
        let newest = makeActivity(in: context, id: 2, daysAgo: 1)
        let middle = makeActivity(in: context, id: 3, daysAgo: 10)

        // Fed in three different orders, as an unordered selection would.
        let orders = [
            [oldest, newest, middle], [newest, middle, oldest], [middle, oldest, newest],
        ]
        let results = orders.map { ComparedTrack.build(from: $0) }

        for tracks in results {
            #expect(tracks.map(\.id) == [newest.id, middle.id, oldest.id])
            #expect(tracks.map(\.color) == Array(TrackPalette.colors.prefix(3)))
        }
    }

    @Test("au-delà de la palette les couleurs se répètent sans déborder")
    func wrapsPastTheEndOfThePalette() {
        let count = TrackPalette.colors.count
        #expect(TrackPalette.color(at: 0) == TrackPalette.colors[0])
        #expect(TrackPalette.color(at: count) == TrackPalette.colors[0])
        #expect(TrackPalette.color(at: count + 2) == TrackPalette.colors[2])
        // Nothing passes a negative index today; it must not trap if that changes.
        #expect(TrackPalette.color(at: -1) == TrackPalette.colors[count - 1])
    }

    @Test("une activité sans trace est listée mais pas dessinée")
    func marksActivitiesWithoutATrack() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let outdoors = makeActivity(in: context, id: 1, daysAgo: 2)
        let indoors = makeActivity(in: context, id: 2, daysAgo: 1, hasTrack: false)

        let tracks = ComparedTrack.build(from: [outdoors, indoors])

        #expect(tracks.count == 2)
        #expect(tracks.first { $0.id == indoors.id }?.isDrawable == false)
        #expect(tracks.first { $0.id == outdoors.id }?.isDrawable == true)
    }

    @Test("la signature change avec les couleurs, pas seulement la géométrie")
    func signatureCoversColors() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let first = makeActivity(in: context, id: 1, daysAgo: 2)
        let second = makeActivity(in: context, id: 2, daysAgo: 1)

        let tracks = ComparedTrack.build(from: [first, second])
        let baseline = MultiTrackMapRepresentable.signature(of: tracks)

        #expect(MultiTrackMapRepresentable.signature(of: tracks) == baseline)
        // Same geometry, swapped colours: MapKit keeps its renderers, so this
        // has to register as a change or the recolour never reaches the screen.
        let recoloured = [
            ComparedTrack(
                id: tracks[0].id, name: tracks[0].name, date: tracks[0].date,
                distance: tracks[0].distance, sportSymbol: tracks[0].sportSymbol,
                coordinates: tracks[0].coordinates, color: tracks[1].color
            ),
            tracks[1],
        ]
        #expect(MultiTrackMapRepresentable.signature(of: recoloured) != baseline)
        // And dropping a track has to register too.
        #expect(
            MultiTrackMapRepresentable.signature(of: [tracks[0]]) != baseline
        )
    }

    @Test("la polyligne colorée transporte sa couleur jusqu'au rendu")
    func coloredPolylineCarriesItsColor() {
        let line = ColoredPolyline(
            coordinates: [
                Coordinate(latitude: 45.75, longitude: 4.83).clLocation,
                Coordinate(latitude: 45.76, longitude: 4.84).clLocation,
            ],
            count: 2
        )
        line.color = .systemPink

        // The delegate is handed the overlay alone, so this is the only channel
        // by which a per-track colour can reach the renderer.
        let renderer = MultiTrackMapRepresentable.Coordinator()
            .mapView(MKMapView(), rendererFor: line)

        #expect((renderer as? MKPolylineRenderer)?.strokeColor == .systemPink)
    }
}
