import Foundation

/// Writes an activity back out as GPX 1.1.
///
/// The point of the whole journal: data you hold locally is only really yours if
/// you can get it out again. So this exports what Cairn actually stored — the
/// full recorded track when the streams are there, the simplified one when they
/// are not — rather than refusing an activity whose details were never fetched.
enum GPXWriter {
    /// XML text, ready to write to disk.
    static func document(for activity: Activity) -> String {
        let points = self.points(for: activity)
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="Cairn" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "  <metadata>",
            "    <name>\(escape(activity.name))</name>",
            "    <time>\(iso8601.string(from: activity.startDate))</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(escape(activity.name))</name>",
            "    <type>\(escape(activity.sportType.rawValue))</type>",
            "    <trkseg>",
        ]
        lines.append(contentsOf: points.map(element(for:)))
        lines.append(contentsOf: ["    </trkseg>", "  </trk>", "</gpx>", ""])
        return lines.joined(separator: "\n")
    }

    /// A file name that is safe on disk and still says which outing it is.
    static func fileName(for activity: Activity) -> String {
        let date = DateFormatter()
        date.dateFormat = "yyyy-MM-dd"
        date.locale = Locale(identifier: "en_US_POSIX")

        // Slashes and colons are the two characters the file system objects to,
        // and an activity named "12/07 — sortie" is entirely ordinary.
        let cleaned = activity.name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleaned.isEmpty ? "activité" : cleaned
        return "\(date.string(from: activity.startLocalDate)) \(name).gpx"
    }

    /// The best track available, richest source first.
    ///
    /// The full stream carries altitude and timestamps; the simplified track is
    /// geometry alone. Exporting the simplified one is a real loss, but a much
    /// smaller one than exporting nothing.
    static func points(for activity: Activity) -> [GPXPoint] {
        if let streams = activity.streams {
            let coordinates = streams.coordinates
            if !coordinates.isEmpty {
                let altitudes = streams.altitude.map(TrackBlob.decodeScalars) ?? []
                let offsets = streams.time.map(TrackBlob.decodeTimes) ?? []
                return coordinates.enumerated().map { index, coordinate in
                    GPXPoint(
                        coordinate: coordinate,
                        elevation: index < altitudes.count
                            ? Double(altitudes[index]) : nil,
                        // Strava's time stream is seconds since the start, not
                        // absolute instants.
                        time: index < offsets.count
                            ? activity.startDate.addingTimeInterval(Double(offsets[index]))
                            : nil
                    )
                }
            }
        }
        return activity.simplifiedCoordinates.map {
            GPXPoint(coordinate: $0, elevation: nil, time: nil)
        }
    }

    /// `nonisolated(unsafe)` because `ISO8601DateFormatter` is not `Sendable`,
    /// while Foundation documents its formatters as thread-safe for formatting
    /// and parsing once configured. Rebuilding one per point instead would cost
    /// more than the parse itself on a 20 000-point file.
    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func element(for point: GPXPoint) -> String {
        // Six decimals is about ten centimetres — past what any consumer GPS
        // resolves, and short enough to keep a 20 000-point file readable.
        var lines = [
            String(
                format: "      <trkpt lat=\"%.6f\" lon=\"%.6f\">",
                point.coordinate.latitude, point.coordinate.longitude
            )
        ]
        if let elevation = point.elevation {
            lines.append(String(format: "        <ele>%.1f</ele>", elevation))
        }
        if let time = point.time {
            lines.append("        <time>\(iso8601.string(from: time))</time>")
        }
        lines.append("      </trkpt>")
        return lines.joined(separator: "\n")
    }

    private static func escape(_ text: String) -> String {
        // Ampersand first: escaping it after the others would double-escape
        // the entities they just introduced.
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
