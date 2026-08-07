import Testing
import SwiftUI
import AppKit
@testable import Cairn

@Suite("Apparence des sports")
@MainActor
struct SportAppearanceTests {
    @Test("la gouttière est assez large pour le plus large des symboles")
    func theGutterFitsTheWidestSymbol() throws {
        // The reason this exists: SF Symbols are not monospaced, so `Label`
        // started each title wherever its symbol happened to end. Measured at a
        // 13 pt body font, `bicycle` is 24 pt against 12 for `figure.walk`.
        // A gutter narrower than the widest symbol would clip it.
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let widest = (SportType.allCases.map(\.symbolName)
            + ActivityLabel.allCases.map(\.symbolName))
            .compactMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                    .withSymbolConfiguration(configuration)?.size.width
            }
            .max() ?? 0

        #expect(widest > 0)
        #expect(widest <= GutteredLabel("x", systemImage: "bicycle").gutterWidthForTesting)
    }

    @Test("chaque sport a un symbole et une couleur")
    func everySportIsCovered() {
        // Both are exhaustive `switch`es, so a new case cannot compile without
        // an answer — this only guards against an empty or placeholder one.
        #expect(SportType.allCases.allSatisfy { !$0.symbolName.isEmpty })
        #expect(SportType.allCases.count == 14)
    }

    @Test("les quatre vélos partagent une icône et se distinguent par la couleur")
    func bikesShareASymbolAndDifferInColour() {
        let bikes: [SportType] = [.ride, .eBikeRide, .mountainBikeRide, .gravelRide]
        // `bicycle.circle` was the same drawing inside a ring, which read as a
        // badge on a road bike rather than as another sport.
        #expect(bikes.allSatisfy { $0.symbolName == "bicycle" })
        // Sharing the symbol only works if the colour carries the difference.
        #expect(Set(bikes.map(\.color)).count == bikes.count)
    }

    @Test("aucune couleur n'est portée par deux sports")
    func coloursAreDistinct() {
        // Two sports sharing a colour and a symbol would be indistinguishable in
        // the list — which is exactly what just happened to the bikes.
        let byColour = Dictionary(grouping: SportType.allCases, by: \.color)
        let collisions = byColour.filter { $0.value.count > 1 }.values.flatMap { $0 }
        #expect(collisions.isEmpty, "sports de même couleur : \(collisions)")
    }

    @Test("deux sports de même icône n'ont jamais la même couleur")
    func sameSymbolNeverMeansSameColour() {
        for (_, sports) in Dictionary(grouping: SportType.allCases, by: \.symbolName)
        where sports.count > 1 {
            #expect(Set(sports.map(\.color)).count == sports.count)
        }
    }
}
