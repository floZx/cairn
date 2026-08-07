import Foundation

/// Reads a GPX file into a `GPXTrack`.
///
/// `XMLParser` rather than a dependency: GPX is a handful of elements, and the
/// parts that actually differ between exporters are the ones a library would
/// hide — namespaces on extensions, waypoints mixed in with track points, a
/// `<name>` at file level rather than on the track.
///
/// Deliberately lenient. A point with no elevation, a track split into several
/// segments, a `<rte>` instead of a `<trk>`: all of these are real files people
/// have, and refusing them would be refusing the data this journal exists to
/// keep. Only a file with no usable point at all is an error.
final class GPXParser: NSObject {
    private var points: [GPXPoint] = []
    private var trackName: String?
    private var trackType: String?
    /// The name seen at file level, kept as a fallback: many exporters put the
    /// outing's title on `<metadata>` and leave the track itself unnamed.
    private var metadataName: String?

    private var currentCoordinate: Coordinate?
    private var currentElevation: Double?
    private var currentTime: Date?
    private var text = ""
    /// Depth inside a `<trk>` or `<rte>`, so a `<name>` belonging to a waypoint
    /// elsewhere in the file cannot be mistaken for the track's.
    private var insideTrack = false
    private var insideMetadata = false

    static func parse(data: Data) throws -> GPXTrack {
        let parser = GPXParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldProcessNamespaces = true
        guard xml.parse() else { throw GPXError.unreadable }
        guard !parser.points.isEmpty else { throw GPXError.noPoints }
        return GPXTrack(
            name: parser.trackName ?? parser.metadataName,
            type: parser.trackType,
            points: parser.points
        )
    }

    /// GPX timestamps are ISO 8601 UTC, with or without fractional seconds
    /// depending on the device. Both formatters are tried rather than guessing.
    /// `nonisolated(unsafe)` because `ISO8601DateFormatter` is not `Sendable`,
    /// while Foundation documents its formatters as thread-safe for formatting
    /// and parsing once configured. Rebuilding one per point instead would cost
    /// more than the parse itself on a 20 000-point file.
    private nonisolated(unsafe) static let dateFormatters: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [plain, fractional]
    }()

    static func date(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}

extension GPXParser: XMLParserDelegate {
    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        text = ""
        switch elementName {
        case "trk", "rte":
            insideTrack = true
        case "metadata":
            insideMetadata = true
        case "trkpt", "rtept":
            currentElevation = nil
            currentTime = nil
            guard let latitude = attributeDict["lat"].flatMap(Double.init),
                  let longitude = attributeDict["lon"].flatMap(Double.init)
            else {
                currentCoordinate = nil
                return
            }
            currentCoordinate = Coordinate(latitude: latitude, longitude: longitude)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String,
        namespaceURI: String?, qualifiedName: String?
    ) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "ele":
            currentElevation = Double(value)
        case "time":
            currentTime = Self.date(from: value)
        case "name":
            if insideMetadata {
                metadataName = value.isEmpty ? nil : value
            } else if insideTrack, trackName == nil {
                trackName = value.isEmpty ? nil : value
            }
        case "type":
            if insideTrack, trackType == nil {
                trackType = value.isEmpty ? nil : value
            }
        case "trkpt", "rtept":
            if let coordinate = currentCoordinate {
                points.append(
                    GPXPoint(
                        coordinate: coordinate,
                        elevation: currentElevation,
                        time: currentTime
                    )
                )
            }
            currentCoordinate = nil
        case "metadata":
            insideMetadata = false
        case "trk", "rte":
            // Left true would be wrong for a file holding several tracks, but
            // their points all belong to the same outing here, so only the
            // naming needs to stop at the first one.
            insideTrack = false
        default:
            break
        }
        text = ""
    }
}
