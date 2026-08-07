import Testing
import SwiftUI
@testable import Cairn

@Suite("Apparence des sports")
struct SportAppearanceTests {
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
