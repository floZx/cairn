import Testing

@Suite("Geo")
struct GeoTests {
    @Test("la cible de test est câblée")
    func harnessRuns() {
        #expect(1 + 1 == 2)
    }
}
