import Testing
@testable import Cairn

@Suite("Personnes : toujours quelqu'un d'ouvert")
struct PeopleSelectionTests {
    @Test("sans sélection, la première personne s'ouvre")
    func opensFirst() {
        #expect(PeopleView.selectionGardee(cles: ["tom", "sam"], actuelle: nil) == "tom")
    }

    @Test("une personne encore là reste ouverte")
    func keepsCurrent() {
        #expect(PeopleView.selectionGardee(cles: ["tom", "sam"], actuelle: "sam") == nil)
    }

    @Test("une personne qui n'est plus citée laisse la place à la première")
    func replacesGone() {
        #expect(PeopleView.selectionGardee(cles: ["tom"], actuelle: "lou") == "tom")
        #expect(PeopleView.selectionGardee(cles: [], actuelle: nil) == nil)
    }
}
