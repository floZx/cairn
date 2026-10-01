import Testing
@testable import Cairn

@Suite("Sélection sur le profil d'altitude")
struct ProfileSelectionTests {
    /// Monte de 100 m sur le premier kilomètre, redescend de 50 m sur le second.
    private let points: [StreamPoint] = [
        StreamPoint(id: 0, distanceKm: 0, value: 400),
        StreamPoint(id: 1, distanceKm: 0.5, value: 450),
        StreamPoint(id: 2, distanceKm: 1, value: 500),
        StreamPoint(id: 3, distanceKm: 1.5, value: 475),
        StreamPoint(id: 4, distanceKm: 2, value: 450),
    ]

    @Test("la montée seule : 1 km, +100 m, 10 %")
    func climb() throws {
        let s = try #require(ProfileSelection.compute(points: points, from: 0, to: 1))
        #expect(abs(s.distanceKm - 1) < 1e-9)
        #expect(abs(s.gain - 100) < 1e-9)
        #expect(s.loss == 0)
        #expect(abs(s.grade - 10) < 1e-9)
    }

    @Test("tirée de droite à gauche, entre deux points : interpolée aux bornes")
    func reversedAndInterpolated() throws {
        let s = try #require(ProfileSelection.compute(points: points, from: 1.25, to: 0.25))
        #expect(abs(s.distanceKm - 1) < 1e-9)
        // 425 m à 0,25 km, 487,5 m à 1,25 km, sommet à 500 m entre les deux.
        #expect(abs(s.gain - 75) < 1e-9)
        #expect(abs(s.loss - 12.5) < 1e-9)
        #expect(abs(s.grade - 6.25) < 1e-9)
    }

    @Test("une plage vide ne mesure rien")
    func empty() {
        #expect(ProfileSelection.compute(points: points, from: 1, to: 1) == nil)
    }
}
