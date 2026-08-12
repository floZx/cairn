import Testing
import Foundation
@testable import Cairn

@Suite("La trace en SVG, pour le carnet sans carte")
@MainActor
struct JournalBookTrackSVGTests {
    private let square = CGSize(width: 200, height: 200)

    private var loop: [Coordinate] {
        [
            Coordinate(latitude: 45.75, longitude: 4.83),
            Coordinate(latitude: 45.76, longitude: 4.84),
            Coordinate(latitude: 45.75, longitude: 4.85),
        ]
    }

    @Test("une trace donne un SVG à ses dimensions")
    func drawsTheTrack() {
        let svg = JournalBookTrackSVG.svg(for: loop, size: square, hex: "#ff6600")
        #expect(svg?.hasPrefix("<svg") == true)
        #expect(svg?.contains("width=\"200\"") == true)
        #expect(svg?.contains("height=\"200\"") == true)
        #expect(svg?.contains("#ff6600") == true)
        // Une polyligne, pas une image : le PDF la garde nette à l'impression.
        #expect(svg?.contains("<polyline") == true)
    }

    @Test("sans trace, pas de SVG")
    func nothingToDraw() {
        #expect(JournalBookTrackSVG.svg(for: [], size: square, hex: "#000") == nil)
        #expect(
            JournalBookTrackSVG.svg(
                for: [Coordinate(latitude: 45.75, longitude: 4.83)],
                size: square, hex: "#000"
            ) == nil
        )
    }

    @Test("les points restent dans le cadre")
    func staysInsideTheBox() {
        let svg = JournalBookTrackSVG.svg(for: loop, size: square, hex: "#000")!
        // Les coordonnées du `points="x,y x,y"` : aucune hors du cadre.
        let numbers = svg
            .components(separatedBy: "points=\"")[1]
            .components(separatedBy: "\"")[0]
            .components(separatedBy: CharacterSet(charactersIn: " ,"))
            .compactMap(Double.init)
        #expect(!numbers.isEmpty)
        #expect(numbers.allSatisfy { $0 >= 0 && $0 <= 200 })
    }
}
