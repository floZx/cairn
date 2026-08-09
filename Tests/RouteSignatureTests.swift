import Testing
import Foundation
@testable import Cairn

@Suite("RouteSignature")
struct RouteSignatureTests {
    /// ~111 m par millième de degré de latitude ; à 45° de latitude un
    /// millième de degré de longitude vaut ~79 m.
    private func track(
        _ points: [(Double, Double)], offsetLatMetres: Double = 0
    ) -> [Coordinate] {
        points.map { lat, lon in
            Coordinate(
                latitude: lat + offsetLatMetres / 111_195,
                longitude: lon
            )
        }
    }

    /// Un aller simple de ~4,4 km vers le nord, en 5 points irréguliers.
    private var line: [Coordinate] {
        track([(45.0, 5.0), (45.001, 5.0), (45.01, 5.0), (45.02, 5.0), (45.04, 5.0)])
    }

    @Test("la signature échantillonne à pas constant, du départ à l'arrivée")
    func signatureIsEvenlySpaced() throws {
        let signature = try #require(RouteSignature.signature(of: line))
        #expect(signature.count == RouteSignature.sampleCount)
        #expect(signature.first == line.first)
        // Dernier échantillon : l'arrivée, à un chouïa d'arithmétique près.
        let last = try #require(signature.last)
        #expect(last.distance(to: Coordinate(latitude: 45.04, longitude: 5.0)) < 1)
        // Pas constant : chaque intervalle vaut total/(n-1).
        let steps = zip(signature, signature.dropFirst()).map { $0.distance(to: $1) }
        let expected = TrackMetrics.distance(of: line) / Double(RouteSignature.sampleCount - 1)
        for step in steps {
            #expect(abs(step - expected) < 1)
        }
    }

    @Test("pas de signature sans tracé ou sans longueur")
    func degenerateTracksHaveNoSignature() {
        #expect(RouteSignature.signature(of: []) == nil)
        #expect(RouteSignature.signature(of: track([(45, 5)])) == nil)
        #expect(RouteSignature.signature(of: track([(45, 5), (45, 5)])) == nil)
    }

    @Test("le même parcours à 30 m près matche, une rue parallèle à 500 m non")
    func gpsDriftMatchesParallelStreetDoesNot() throws {
        let reference = try #require(RouteSignature.signature(of: line))
        let drifted = try #require(
            RouteSignature.signature(of: track(
                [(45.0, 5.0), (45.001, 5.0), (45.01, 5.0), (45.02, 5.0), (45.04, 5.0)],
                offsetLatMetres: 30
            ))
        )
        let distance = TrackMetrics.distance(of: line)
        #expect(RouteSignature.matches(
            reference, drifted, distanceA: distance, distanceB: distance
        ))
        let parallel = try #require(
            RouteSignature.signature(of: track(
                [(45.0, 5.0), (45.001, 5.0), (45.01, 5.0), (45.02, 5.0), (45.04, 5.0)],
                offsetLatMetres: 500
            ))
        )
        #expect(!RouteSignature.matches(
            reference, parallel, distanceA: distance, distanceB: distance
        ))
    }

    @Test("une longueur trop différente disqualifie avant même la forme")
    func lengthGateComesFirst() throws {
        let reference = try #require(RouteSignature.signature(of: line))
        #expect(!RouteSignature.matches(
            reference, reference, distanceA: 4_400, distanceB: 3_500
        ))
    }

    @Test("une boucle inversée ne matche pas, un aller-retour si")
    func directionMattersExceptForOutAndBack() throws {
        // Boucle carrée ~1,6 km : N, E, S, O.
        let loop = track([
            (45.000, 5.000), (45.004, 5.000), (45.004, 5.006),
            (45.000, 5.006), (45.000, 5.000),
        ])
        let reversedLoop = Array(loop.reversed())
        let loopSig = try #require(RouteSignature.signature(of: loop))
        let reversedSig = try #require(RouteSignature.signature(of: reversedLoop))
        let loopDistance = TrackMetrics.distance(of: loop)
        #expect(!RouteSignature.matches(
            loopSig, reversedSig, distanceA: loopDistance, distanceB: loopDistance
        ))

        // Aller-retour : symétrique, identique dans les deux sens.
        let outAndBack = track([
            (45.000, 5.000), (45.010, 5.000), (45.020, 5.000),
            (45.010, 5.000), (45.000, 5.000),
        ])
        let backAndOut = Array(outAndBack.reversed())
        let outSig = try #require(RouteSignature.signature(of: outAndBack))
        let backSig = try #require(RouteSignature.signature(of: backAndOut))
        let outDistance = TrackMetrics.distance(of: outAndBack)
        #expect(RouteSignature.matches(
            outSig, backSig, distanceA: outDistance, distanceB: outDistance
        ))
    }
}
