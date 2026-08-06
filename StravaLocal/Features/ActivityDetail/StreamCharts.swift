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
    /// Distance under the cursor, shared with the map so it can mark the spot.
    @Binding var hoverDistanceKm: Double?

    private var maxDistanceKm: Double {
        series.compactMap { $0.points.last?.distanceKm }.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(series) { serie in
                VStack(alignment: .leading, spacing: 4) {
                    header(for: serie)
                    chart(for: serie)
                }
            }
        }
    }

    private func header(for serie: StreamSeries) -> some View {
        HStack {
            Text("\(serie.label) (\(serie.unit))")
            Spacer()
            // The hovered reading, so the cursor answers "how high was I here?"
            if let value = value(of: serie, at: hoverDistanceKm) {
                Text("\(Int(value.rounded())) \(serie.unit)")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func chart(for serie: StreamSeries) -> some View {
        Chart {
            ForEach(serie.points) { point in
                AreaMark(x: .value("km", point.distanceKm),
                         y: .value(serie.label, point.value))
                .opacity(0.15)
                LineMark(x: .value("km", point.distanceKm),
                         y: .value(serie.label, point.value))
            }
            if let hoverDistanceKm {
                RuleMark(x: .value("km", hoverDistanceKm))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(.secondary)
            }
        }
        // Scaled to the readings rather than to zero: an altitude profile
        // between 400 m and 850 m spends most of a zero-based chart as empty
        // space below the trace.
        .chartYScale(domain: yDomain(for: serie))
        // Pinned to the ride's own length, so the plot fills the width instead
        // of stopping short of a rounded-up axis maximum.
        .chartXScale(domain: 0...max(maxDistanceKm, 0.1))
        .chartXAxisLabel("km")
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard let plotFrame = proxy.plotFrame else { return }
                        switch phase {
                        case let .active(location):
                            let x = location.x - geometry[plotFrame].origin.x
                            hoverDistanceKm = proxy.value(atX: x, as: Double.self)
                        case .ended:
                            hoverDistanceKm = nil
                        }
                    }
            }
        }
    }

    private func yDomain(for serie: StreamSeries) -> ClosedRange<Double> {
        let values = serie.points.map(\.value)
        guard let lowest = values.min(), let highest = values.max() else {
            return 0...1
        }
        guard highest > lowest else {
            // A perfectly flat series still needs a non-empty domain.
            return (lowest - 1)...(highest + 1)
        }
        let padding = (highest - lowest) * 0.08
        return (lowest - padding)...(highest + padding)
    }

    /// The reading nearest a given distance, for the header readout.
    private func value(of serie: StreamSeries, at distanceKm: Double?) -> Double? {
        guard let distanceKm, !serie.points.isEmpty else { return nil }
        return serie.points
            .min { abs($0.distanceKm - distanceKm) < abs($1.distanceKm - distanceKm) }?
            .value
    }
}
