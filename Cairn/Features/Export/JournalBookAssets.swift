import AppKit
import Charts
import MapKit
import SwiftUI

/// The book's pictures: one map per outing, its charts, its photos.
///
/// The only piece of the export that touches the network and the view layer,
/// and the only slow one — a map snapshot is a round trip to Apple's tile
/// servers. It is kept apart from the HTML for exactly that reason: everything
/// that decides what the book *says* stays pure and testable, and everything
/// that merely draws lives here.
@MainActor
enum JournalBookAssets {
    /// Rendered wide: the page is 178 mm of usable width, and an image narrower
    /// than that would be stretched by the stylesheet.
    private static let mapSize = CGSize(width: 1000, height: 560)
    private static let chartSize = CGSize(width: 1000, height: 220)

    /// - Parameter progress: called after each picture, `(done, total)`, on the
    ///   main actor — the sheet stays up and shows it, because ten seconds of a
    ///   window saying nothing reads as a freeze.
    static func illustrations(
        for book: JournalBook, progress: @escaping (Int, Int) -> Void
    ) async -> [Int64: JournalBookHTML.Illustrations] {
        let outings = book.days.flatMap(\.activities)
        var plans: [(activity: Activity, series: [StreamSeries], photos: [Data])] = []
        for activity in outings {
            let model = ActivityTrackModelCache.model(for: activity)
            // Altitude and heart rate only. Power and cadence are what a
            // dashboard shows; a book keeps the two curves that say what the
            // ground and the body did.
            let series = model.series.filter {
                $0.id == "altitude" || $0.id == "heartrate"
            }
            let photos = activity.orderedPhotos.compactMap(\.data)
            plans.append((activity, series, photos))
        }

        let total = plans.reduce(0) { $0 + 1 + $1.series.count + $1.photos.count }
        var done = 0
        func step() {
            done += 1
            progress(done, total)
        }

        var result: [Int64: JournalBookHTML.Illustrations] = [:]
        for plan in plans {
            var illustrations = JournalBookHTML.Illustrations()

            illustrations.map = await map(for: plan.activity)
            step()

            for series in plan.series {
                if let uri = chart(series, color: plan.activity.sportType.color) {
                    illustrations.charts.append(uri)
                }
                step()
            }

            for data in plan.photos {
                if let uri = photo(data) {
                    illustrations.photos.append(uri)
                }
                step()
            }

            result[plan.activity.stravaID] = illustrations
        }
        return result
    }

    // MARK: - La carte

    /// A snapshot with the track drawn over it, or the vector fallback.
    ///
    /// The fallback is not an error path taken lightly: an export made on a
    /// train has no tiles, and a book of empty grey rectangles would be worse
    /// than a book of drawn outlines.
    private static func map(for activity: Activity) async -> String? {
        let coordinates = activity.displayCoordinates
        guard coordinates.count > 1 else { return nil }
        let color = NSColor(activity.sportType.color)
        if let image = await snapshot(of: coordinates, color: color),
           let uri = pngDataURI(image) {
            return uri
        }
        return JournalBookTrackSVG.svg(
            for: coordinates, size: mapSize, hex: hex(of: color)
        )
    }

    /// One map, drawn light: a book is printed on white paper, and a dark
    /// snapshot would come out of a printer as a grey slab.
    private static func snapshot(
        of coordinates: [Coordinate], color: NSColor
    ) async -> NSImage? {
        let points = coordinates.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        var rect = MKMapRect.null
        for point in points {
            let mapPoint = MKMapPoint(point)
            rect = rect.union(
                MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0)
            )
        }
        guard !rect.isNull, rect.size.width > 0 || rect.size.height > 0 else {
            return nil
        }

        let options = MKMapSnapshotter.Options()
        // Air around the track: a line drawn against the edge of the frame
        // reads as a line that carries on past it.
        options.mapRect = rect.insetBy(
            dx: -max(rect.size.width, 1) * 0.15,
            dy: -max(rect.size.height, 1) * 0.15
        )
        options.size = mapSize
        options.appearance = NSAppearance(named: .aqua)
        options.showsBuildings = false

        guard let snapshot = try? await MKMapSnapshotter(options: options).start()
        else { return nil }

        let image = NSImage(size: snapshot.image.size)
        image.lockFocus()
        snapshot.image.draw(
            at: .zero, from: .zero, operation: .copy, fraction: 1
        )
        let path = NSBezierPath()
        path.lineWidth = 4
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        for (index, point) in points.enumerated() {
            let position = snapshot.point(for: point)
            if index == 0 {
                path.move(to: position)
            } else {
                path.line(to: position)
            }
        }
        color.setStroke()
        path.stroke()
        image.unlockFocus()
        return image
    }

    // MARK: - Les courbes

    private static func chart(_ series: StreamSeries, color: Color) -> String? {
        let renderer = ImageRenderer(
            content: BookChart(series: series).frame(
                width: chartSize.width, height: chartSize.height
            )
        )
        // Twice the size, so the curve stays smooth when the PDF is zoomed.
        renderer.scale = 2
        guard let image = renderer.nsImage else { return nil }
        return pngDataURI(image)
    }

    /// The same series the detail pane plots, drawn for paper: no interaction,
    /// no hover, and a light background whatever the app's appearance.
    private struct BookChart: View {
        let series: StreamSeries

        private var domain: ClosedRange<Double> {
            let values = series.points.map(\.value)
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            // A flat series would otherwise ask for an empty range.
            return low == high ? low - 1...high + 1 : low...high
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(series.label) (\(series.unit))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Chart(series.points) { point in
                    if series.isFilled {
                        AreaMark(
                            x: .value("km", point.distanceKm),
                            yStart: .value(series.label, domain.lowerBound),
                            yEnd: .value(series.label, point.value)
                        )
                        .foregroundStyle(series.color.opacity(0.15))
                    }
                    LineMark(
                        x: .value("km", point.distanceKm),
                        y: .value(series.label, point.value)
                    )
                    .foregroundStyle(series.color)
                }
                .chartYScale(domain: domain)
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let km = value.as(Double.self) {
                                Text("\(Int(km.rounded())) km")
                            }
                        }
                    }
                }
            }
            .padding(8)
            .background(.white)
            .environment(\.colorScheme, .light)
        }
    }

    // MARK: - Les photos

    /// The bytes as they are stored — Strava sends JPEG, and re-encoding a
    /// photograph to put it in a book would only lose detail.
    private static func photo(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let isPNG = data.count > 4 && Array(data.prefix(4)) == png
        return "data:image/\(isPNG ? "png" : "jpeg");base64,"
            + data.base64EncodedString()
    }

    // MARK: - Les petites briques

    private static func pngDataURI(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    /// A CSS colour for the vector fallback, in sRGB — a colour asked for its
    /// components in another space answers nil and would draw nothing.
    private static func hex(of color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }
}
