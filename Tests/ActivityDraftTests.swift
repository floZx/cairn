import Testing
@testable import StravaLocal

@Suite("ActivityField et ActivitySource")
struct ActivityFieldTests {
    @Test("chaque champ a une clé stable et un libellé")
    func fieldsAreStable() {
        // The raw values are persisted in `Activity.editedFields`. Renaming one
        // would silently unprotect every activity already edited, and the only
        // symptom would be an overwritten edit at the next sync.
        #expect(ActivityField.name.rawValue == "name")
        #expect(ActivityField.startDate.rawValue == "startDate")
        #expect(ActivityField.totalElevationGain.rawValue == "totalElevationGain")
        #expect(ActivityField.allCases.count == 9)
        #expect(ActivityField.allCases.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("seule la source Strava est concernée par la synchro")
    func onlyStravaIsSynced() {
        #expect(ActivitySource.strava.isSynced)
        #expect(ActivitySource.manual.isSynced == false)
        #expect(ActivitySource.file.isSynced == false)
        #expect(ActivitySource(rawValue: "strava") == .strava)
        // An unknown raw value must not crash a store written by a later version.
        #expect(ActivitySource(rawValue: "healthkit") == nil)
    }
}
