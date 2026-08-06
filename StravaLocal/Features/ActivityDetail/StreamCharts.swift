import SwiftUI
import Charts

struct StreamPoint: Sendable, Identifiable {
    let id: Int
    let distanceKm: Double
    let value: Double
}

struct StreamSeries: Sendable, Identifiable {
    let id: String
    let label: String
    let unit: String
    let points: [StreamPoint]
}

enum StreamSeriesBuilder {
    /// Beyond this, Swift Charts spends more time laying out than the extra
    /// detail is worth at screen resolution.
    static let maxChartPoints = 600

    static func series(
        from streams: ActivityStreams?, totalDistance: Double
    ) -> [StreamSeries] {
        guard let streams else { return [] }
        let definitions: [(String, String, String, Data?)] = [
            ("altitude", "Altitude", "m", streams.altitude),
            ("heartrate", "Fréquence cardiaque", "bpm", streams.heartrate),
            ("watts", "Puissance", "W", streams.watts),
            ("cadence", "Cadence", "rpm", streams.cadence),
        ]

        return definitions.compactMap { id, label, unit, blob in
            guard let blob else { return nil }
            let values = Simplify.downsample(
                TrackBlob.decodeScalars(blob), to: maxChartPoints
            )
            guard !values.isEmpty else { return nil }

            // Spread evenly over the activity's distance rather than plotting
            // against point index, so stops don't distort the shape.
            let span = max(values.count - 1, 1)
            let points = values.enumerated().map { index, value in
                StreamPoint(
                    id: index,
                    distanceKm: totalDistance <= 0
                        ? 0
                        : (totalDistance / 1000) * Double(index) / Double(span),
                    value: Double(value)
                )
            }
            return StreamSeries(id: id, label: label, unit: unit, points: points)
        }
    }
}

struct StreamChartsView: View {
    let series: [StreamSeries]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(series) { serie in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(serie.label) (\(serie.unit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Chart(serie.points) { point in
                        AreaMark(x: .value("km", point.distanceKm),
                                 y: .value(serie.label, point.value))
                        .opacity(0.15)
                        LineMark(x: .value("km", point.distanceKm),
                                 y: .value(serie.label, point.value))
                    }
                    .chartXAxisLabel("km")
                    .frame(height: 120)
                }
            }
        }
    }
}
