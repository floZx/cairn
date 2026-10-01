import Testing
import Foundation
@testable import Cairn

@Suite("BestEfforts")
struct BestEffortsTests {
    /// Une sortie à vitesse constante, un point par seconde.
    private func steady(metresPerSecond speed: Double, seconds: Int) -> ([Double], [Int32]) {
        let time = (0...seconds).map { Int32($0) }
        let distance = time.map { Double($0) * speed }
        return (distance, time)
    }

    @Test func steadyPaceGivesExactTimes() {
        let (distance, time) = steady(metresPerSecond: 4, seconds: 3000) // 12 km
        let efforts = BestEfforts.compute(distance: distance, time: time)
        #expect(abs(efforts[.m400]! - 100) < 0.01)
        #expect(abs(efforts[.km1]! - 250) < 0.01)
        // Sans interpolation : la fenêtre finit sur un point mesuré, 1 612 m.
        #expect(efforts[.mile] == 403)
        #expect(abs(efforts[.km10]! - 2500) < 0.01)
        #expect(efforts[.km15] == nil)
    }

    @Test func findsTheFastestWindow() {
        // 2 km à 3 m/s, puis 1 km à 5 m/s, puis 2 km à 3 m/s.
        var distance: [Double] = [0], time: [Int32] = [0]
        var d = 0.0
        for second in 1...1534 {
            let speed = (d >= 2000 && d < 3000) ? 5.0 : 3.0
            d += speed
            distance.append(d); time.append(Int32(second))
        }
        let efforts = BestEfforts.compute(distance: distance, time: time)
        #expect(abs(efforts[.km1]! - 200) <= 1)
    }

    @Test func pausesCount() {
        // 1 km en 250 s, arrêt de 60 s au milieu.
        var distance: [Double] = [], time: [Int32] = []
        for second in 0...310 {
            let moving = second <= 125 ? second : max(125, second - 60)
            distance.append(Double(moving * 4)); time.append(Int32(second))
        }
        let efforts = BestEfforts.compute(distance: distance, time: time)
        #expect(abs(efforts[.km1]! - 310) < 0.01)
    }

    @Test func gpsJumpsAreRejected() {
        // Un saut de 400 m en 5 s : 80 m/s, pas un record.
        var distance: [Double] = [], time: [Int32] = []
        for second in 0...100 {
            distance.append(second >= 50 ? 400 : 0)
            time.append(Int32(second))
        }
        #expect(BestEfforts.compute(distance: distance, time: time)[.m400] == nil)
    }

    @Test func velocityIntegratesToDistance() {
        let time = (0...10).map { Int32($0 * 2) }
        let velocity = [Float](repeating: 3.5, count: 11)
        let distance = BestEfforts.integrate(velocity: velocity, time: time)
        #expect(distance.last == 70)
    }

    @Test func streamsWithoutDistanceFallBackOnVelocity() {
        let streams = ActivityStreams()
        let time = (0...1000).map { Int32($0) }
        streams.time = TrackBlob.encode(times: time)
        streams.velocitySmooth = TrackBlob.encode(scalars: [Float](repeating: 4, count: time.count))
        streams.pointCount = time.count
        #expect(BestEfforts.compute(streams: streams)[.km1] == 250)
    }

    @Test func standingsRankAndBreakTiesByDate() {
        let early = Date(timeIntervalSince1970: 0), late = Date(timeIntervalSince1970: 1000)
        let standings = EffortStandings([
            ActivityEfforts(uuid: "a", date: late, times: [.km5: 1300]),
            ActivityEfforts(uuid: "b", date: early, times: [.km5: 1300, .km10: 2800]),
            ActivityEfforts(uuid: "c", date: early, times: [.km5: 1200]),
            ActivityEfforts(uuid: "d", date: early, times: [.km5: 1400]),
        ])
        #expect(standings.top(.km5).map(\.uuid) == ["c", "b", "a"])
        let medals = standings.medals()
        #expect(medals["c"] == [EffortMedal(distance: .km5, rank: 1, seconds: 1200)])
        #expect(medals["b"]?.count == 2)
        #expect(medals["d"] == nil)
    }

    @Test func encodesInDistanceOrder() {
        #expect(BestEfforts.encode([:]) == nil)
        let encoded = try! #require(BestEfforts.encode([.m400: 97, .km10: 2659]))
        #expect(encoded.count == EffortDistance.allCases.count)
        #expect(encoded[EffortDistance.m400.rawValue] == 97)
        #expect(encoded[EffortDistance.km10.rawValue] == 2659)
        #expect(encoded[EffortDistance.km5.rawValue] == 0)
    }

    @Test func raceTimeFormat() {
        #expect(Format.raceTime(1294) == "21:34")
        #expect(Format.raceTime(6127) == "1:42:07")
    }
}
