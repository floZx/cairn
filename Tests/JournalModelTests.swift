import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Modèles du journal")
struct JournalModelTests {
    /// Les étiquettes étaient dérivées à la construction, ce qu'un `@Model` ne
    /// permet pas. Elles deviennent une colonne — donc quelque chose doit la
    /// tenir à jour, et c'est `setText`.
    @Test func ecrireUnTexteMetLesEtiquettesAJour() {
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "")
        #expect(note.tags.isEmpty)

        note.setText("Sortie longue #course avec #cotes")

        #expect(note.tags.count == 2)
        #expect(note.tagsRaw.sorted() == ["cotes", "course"])
    }

    /// Un texte sans étiquette en vide la colonne, plutôt que d'y laisser
    /// celles du texte précédent.
    @Test func retirerUneEtiquetteLaRetireDeLaColonne() {
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "#course")
        note.setText("plus rien")
        #expect(note.tagsRaw.isEmpty)
    }

    /// La règle qui existait sur la structure et qui reste vraie : une note
    /// blanche est une note vide.
    @Test func uneNoteBlancheEstVide() {
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "  \n\n ")
        #expect(note.isEmpty)
    }

    /// Écrite puis relue, une note garde son identité et son texte.
    @Test func uneNoteSurvitAuDisque() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "bonjour")
        let expected = note.uuid
        context.insert(note)
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<JournalNote>())
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.uuid == expected)
        #expect(reloaded.first?.text == "bonjour")
    }

    /// Les octets d'une pièce jointe vivent en stockage externe, comme les
    /// photos de sorties, et son nom de fichier est sa clé.
    @Test func unePieceJointeGardeSesOctetsEtSonNom() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let bytes = Data(repeating: 0xAB, count: 512)
        context.insert(JournalAttachment(fileName: "2026-08-17-1.jpg", data: bytes))
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<JournalAttachment>())
        #expect(reloaded.first?.fileName == "2026-08-17-1.jpg")
        #expect(reloaded.first?.data == bytes)
    }

    /// Caractérise un comportement de SwiftData, pas de `JournalNote` : une
    /// chaîne portant un caractère NUL littéral est tronquée à l'écriture,
    /// sur ce magasin en mémoire comme sur le vrai magasin SQLite (confirmé
    /// hors de ce dépôt, sur un `@Model` neuf). Ce test n'existe pas pour
    /// vérifier que Cairn fait quelque chose de particulier — il documente
    /// le bug dont `JournalImport.encodeBytesLosslessly` et `escapingNUL` se
    /// protègent en ne produisant jamais U+0000. S'il se met à échouer un
    /// jour, c'est qu'Apple a corrigé la troncature, et ce contournement
    /// devient un candidat au retrait.
    @Test func laPersistanceTronqueUneChaineAuPremierNul() throws {
        let container = try AppModelContainer.inMemory()
        let context = ModelContext(container)
        let note = JournalNote(dateKey: DateKey(raw: "2026-08-17")!, text: "avant\0apres")
        context.insert(note)
        try context.save()

        let reloaded = try context.fetch(FetchDescriptor<JournalNote>())
        #expect(reloaded.first?.text == "avant")
        #expect(reloaded.first?.text.unicodeScalars.count == 5)
    }
}
