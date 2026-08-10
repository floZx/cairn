import Testing
import Foundation
@testable import Cairn

@Suite("SportTally")
struct SportTallyTests {
    @Test("les sports les plus pratiqués d'abord")
    func mostUsedFirst() {
        let rows = SportTally.rows(for: [.run, .run, .run, .ride, .ride, .swim])
        #expect(rows.map(\.sport) == [.run, .ride, .swim])
        #expect(rows.map(\.count) == [3, 2, 1])
    }

    @Test("à nombre égal, le nom départage, et toujours de la même façon")
    func tiesAreBrokenByName() {
        // « Randonnée » avant « Vélo » : c'est le cas réel qui a fait bouger
        // les lignes toutes seules, les deux à 55.
        let sports: [SportType] = [.hike, .hike, .ride, .ride]
        let rows = SportTally.rows(for: sports)
        #expect(rows.map(\.sport) == [.hike, .ride])
        // L'ordre de la source ne doit rien y changer.
        #expect(SportTally.rows(for: sports.reversed()).map(\.sport) == [.hike, .ride])
        #expect(SportTally.rows(for: [.ride, .hike, .ride, .hike]).map(\.sport)
                == [.hike, .ride])
    }

    @Test("le même jeu de données donne toujours le même ordre")
    func orderIsStableAcrossCalls() {
        // Beaucoup d'égalités : de quoi faire ressortir un ordre de Dictionary.
        let sports: [SportType] = [
            .run, .ride, .hike, .walk, .swim, .trailRun, .rowing, .workout,
        ]
        let reference = SportTally.rows(for: sports).map(\.sport)
        for _ in 0..<20 {
            #expect(SportTally.rows(for: sports.shuffled()).map(\.sport) == reference)
        }
    }

    @Test("sans activité, aucune ligne")
    func noActivitiesMeansNoRows() {
        #expect(SportTally.rows(for: []).isEmpty)
    }
}
