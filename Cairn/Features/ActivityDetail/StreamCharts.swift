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

    /// Only altitude reads as a filled profile. Now that the vertical axis
    /// starts at the lowest reading instead of zero, filling a heart-rate or
    /// cadence trace turns the whole plot into a solid block.
    var isFilled: Bool { id == "altitude" }
}

enum StreamSeriesBuilder {
    /// Beyond this, Swift Charts spends more time laying out than the extra
    /// detail is worth at screen resolution.
    static let maxChartPoints = 600

    /// - Parameter distancesMetres: real cumulative distance per sample, aligned
    ///   with the streams. When it is empty or misaligned the samples are spread
    ///   evenly over `totalDistance` instead — good enough for a steady outing,
    ///   but it drifts wherever the pace does.
    static func series(
        from streams: ActivityStreams?,
        totalDistance: Double,
        distancesMetres: [Double] = []
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
            let rawValues = TrackBlob.decodeScalars(blob)
            guard !rawValues.isEmpty else { return nil }

            let values = Simplify.downsample(rawValues, to: maxChartPoints)
            // Thinned in step with the values, so a sample keeps its own
            // distance rather than an interpolated one.
            let distances = distancesMetres.count == rawValues.count
                ? Simplify.downsample(distancesMetres, to: maxChartPoints)
                : []

            let span = max(values.count - 1, 1)
            let points = values.enumerated().map { index, value in
                let distanceKm: Double
                if index < distances.count {
                    distanceKm = distances[index] / 1000
                } else if totalDistance > 0 {
                    distanceKm = (totalDistance / 1000) * Double(index) / Double(span)
                } else {
                    distanceKm = 0
                }
                return StreamPoint(id: index, distanceKm: distanceKm, value: Double(value))
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
        let domain = yDomain(for: serie)

        return Chart {
            ForEach(serie.points) { point in
                if serie.isFilled {
                    // Anchored to the bottom of the axis, not to zero. A
                    // one-argument AreaMark fills down to zero, which now sits
                    // far below the plot — the fill then spills out of the chart
                    // and over whatever follows it.
                    AreaMark(
                        x: .value("km", point.distanceKm),
                        yStart: .value(serie.label, domain.lowerBound),
                        yEnd: .value(serie.label, point.value)
                    )
                    .opacity(0.15)
                }
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
        .chartYScale(domain: domain)
        // Belt and braces: nothing a chart draws may bleed onto its neighbours.
        .clipped()
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
