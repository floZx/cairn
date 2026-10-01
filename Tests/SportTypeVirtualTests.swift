import Testing
@testable import Cairn

@Suite("Types virtuels de Strava")
struct SportTypeVirtualTests {
    @Test("une course Zwift est une course, une sortie Zwift un vélo")
    func virtualTypesMap() {
        #expect(SportType(stravaValue: "VirtualRun") == .run)
        #expect(SportType(stravaValue: "VirtualRide") == .ride)
    }
}
