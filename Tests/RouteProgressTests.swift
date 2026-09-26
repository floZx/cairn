import Testing
import Foundation
@testable import Cairn

@Suite("Parcours similaires : progression")
struct RouteProgressTests {
    /// m/s d'une allure en min:s au kilomètre.
    private func pace(_ minutes: Int, _ seconds: Int) -> Double {
        1000 / Double(minutes * 60 + seconds)
    }

    @Test("la moyenne est celle des allures, pas des vitesses")
    func averagesPaces() throws {
        let progress = try #require(RouteProgress(speeds: [pace(5, 0), pace(6, 0), pace(7, 0)]))
        #expect(Format.speed(progress.average, sport: .run) == "6:00/km")
        #expect(progress.fastest == pace(5, 0))
        #expect(progress.slowest == pace(7, 0))
    }

    @Test("la tendance lisse sur cinq sorties, plus étroite aux bouts")
    func trendWindow() throws {
        let speeds = [1.0, 2, 3, 4, 5, 6]
        let progress = try #require(RouteProgress(speeds: speeds))
        #expect(progress.trend.count == 6)
        // Le premier point n'a que lui et ses deux suivants.
        #expect(abs(progress.trend[0] - RouteProgress.meanSpeed([1, 2, 3])) < 1e-9)
        #expect(abs(progress.trend[2] - RouteProgress.meanSpeed([1, 2, 3, 4, 5])) < 1e-9)
        #expect(abs(progress.trend[5] - RouteProgress.meanSpeed([4, 5, 6])) < 1e-9)
    }

    @Test("moins de trois sorties, pas de graphique")
    func needsThree() {
        #expect(RouteProgress(speeds: [3, 4]) == nil)
        #expect(RouteProgress(speeds: [3, 0, 4]) == nil)
    }

    @Test("l'écart se dit dans la langue du sport")
    func comparison() {
        // Strava : 5:31/km face à une moyenne de 5:40/km, « -9s/km ».
        #expect(
            RouteProgress.comparison(pace(5, 31), average: pace(5, 40), sport: .run)
                == "9 s/km plus vite que la moyenne"
        )
        #expect(
            RouteProgress.comparison(pace(6, 0), average: pace(5, 40), sport: .run)
                == "20 s/km plus lent que la moyenne"
        )
        #expect(
            RouteProgress.comparison(30 / 3.6, average: 28.8 / 3.6, sport: .ride)
                == "1,2 km/h plus vite que la moyenne"
        )
        #expect(RouteProgress.comparison(pace(5, 40), average: pace(5, 40), sport: .run) == nil)
    }
}
