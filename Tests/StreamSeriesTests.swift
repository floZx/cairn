import Testing
import Foundation
@testable import StravaLocal

@Suite("StreamSeriesBuilder")
struct StreamSeriesTests {
    private func makeStreams(
        altitude: [Float]? = nil, heartrate: [Float]? = nil,
        watts: [Float]? = nil, pointCount: Int = 0
    ) -> ActivityStreams {
        let streams = ActivityStreams()
        streams.pointCount = pointCount
        streams.altitude = altitude.map(TrackBlob.encode(scalars:))
        streams.heartrate = heartrate.map(TrackBlob.encode(scalars:))
        streams.watts = watts.map(TrackBlob.encode(scalars:))
        return streams
    }

    @Test("sans streams, aucune série")
    func noStreamsNoSeries() {
        #expect(StreamSeriesBuilder.series(from: nil, totalDistance: 1000).isEmpty)
    }

    @Test("l'altitude produit une série étalée sur la distance totale")
    func buildsAltitudeSeries() {
        let streams = makeStreams(altitude: [100, 150, 200], pointCount: 3)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 10_000)

        #expect(series.count == 1)
        #expect(series[0].id == "altitude")
        #expect(series[0].points.count == 3)
        #expect(series[0].points.first?.distanceKm == 0)
        #expect(series[0].points.last?.distanceKm == 10)
        #expect(series[0].points.last?.value == 200)
    }

    @Test("chaque stream disponible donne sa propre série")
    func buildsAllAvailableSeries() {
        let streams = makeStreams(
            altitude: [1, 2], heartrate: [100, 120], watts: [200, 250], pointCount: 2
        )
        let ids = StreamSeriesBuilder.series(from: streams, totalDistance: 1000).map(\.id)
        #expect(ids == ["altitude", "heartrate", "watts"])
    }

    @Test("les streams absents ne créent pas de série vide")
    func skipsMissingStreams() {
        let streams = makeStreams(heartrate: [100, 110], pointCount: 2)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 1000)
        #expect(series.map(\.id) == ["heartrate"])
    }

    @Test("les longues séries sont sous-échantillonnées")
    func downsamplesLongSeries() {
        let values = (0..<20_000).map { Float($0) }
        let streams = makeStreams(altitude: values, pointCount: values.count)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 100_000)

        #expect(series[0].points.count <= StreamSeriesBuilder.maxChartPoints)
        #expect(series[0].points.first?.value == 0)
        #expect(series[0].points.last?.value == 19_999)
    }

    @Test("une distance nulle ne divise pas par zéro")
    func handlesZeroDistance() {
        let streams = makeStreams(altitude: [10, 20], pointCount: 2)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 0)
        #expect(series[0].points.allSatisfy { $0.distanceKm == 0 })
    }

    @Test("un stream d'un seul point reste exploitable")
    func handlesSinglePoint() {
        let streams = makeStreams(altitude: [42], pointCount: 1)
        let series = StreamSeriesBuilder.series(from: streams, totalDistance: 1000)
        #expect(series[0].points.count == 1)
        #expect(series[0].points[0].distanceKm == 0)
    }
}
