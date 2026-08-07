import Testing
import Foundation
@testable import StravaLocal

@Suite("StravaDTO")
struct StravaDTOTests {
    @Test("décode une activité résumée complète")
    func decodesSummary() throws {
        let dto = try Fixture.decode(SummaryActivityDTO.self, "summary_activity")
        #expect(dto.id == 10_123_456_789)
        #expect(dto.name == "Sortie matinale")
        #expect(dto.sport_type == "Ride")
        #expect(dto.distance == 45_231.4)
        #expect(dto.moving_time == 5412)
        #expect(dto.average_heartrate == 138.4)
        #expect(dto.gear_id == "b1234567")
        #expect(dto.map?.summary_polyline == "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(dto.start_latlng == [45.764043, 4.835659])
        #expect(dto.start_date == ISO8601DateFormatter().date(from: "2025-06-14T05:32:11Z"))
        #expect(dto.start_date_local == ISO8601DateFormatter().date(from: "2025-06-14T07:32:11Z"))
    }

    @Test("décode une activité manuelle sans capteur ni trace")
    func decodesManual() throws {
        let dto = try Fixture.decode(SummaryActivityDTO.self, "manual_activity")
        #expect(dto.manual == true)
        #expect(dto.average_heartrate == nil)
        #expect(dto.average_watts == nil)
        #expect(dto.kudos_count == nil)
        #expect(dto.map?.summary_polyline == nil)
        #expect(dto.start_latlng == [])
    }

    @Test("décode un jeu de streams")
    func decodesStreams() throws {
        let dto = try Fixture.decode(StreamSetDTO.self, "streams")
        #expect(dto.latlng?.data.count == 3)
        #expect(dto.latlng?.data.first == [45.764043, 4.835659])
        #expect(dto.altitude?.data == [172.4, 175.1, 180.9])
        #expect(dto.time?.data == [0, 5, 11])
        #expect(dto.heartrate?.data == [96, 104, 118])
        #expect(dto.moving?.data == [false, true, true])
        #expect(dto.watts == nil)
    }

    @Test("décode un athlète")
    func decodesAthlete() throws {
        let dto = try Fixture.decode(AthleteDTO.self, "athlete")
        #expect(dto.id == 1_234_567)
        #expect(dto.firstname == "Camille")
        #expect(dto.city == "Lyon")
        #expect(dto.weight == 72.5)
    }
}
