import Testing
import Foundation
import SwiftData
@testable import Cairn

/// The rule the pane and `cairn-note` share: what a text does to a day's row.
///
/// An in-memory container, so nothing here can reach the real library.
@Suite("JournalNoteWrite")
struct JournalNoteWriteTests {
    private let day = DateKey(raw: "2026-08-14")!

    private func context() throws -> ModelContext {
        ModelContext(try AppModelContainer.inMemory())
    }

    private func rows(_ context: ModelContext) throws -> [JournalNote] {
        try context.fetch(FetchDescriptor<JournalNote>())
    }

    @Test("A text on a day with no note makes one")
    func creates() throws {
        let context = try context()
        #expect(JournalNoteWrite.apply("Sortie longue.", for: day, in: context) == .created)
        try context.save()

        let notes = try rows(context)
        #expect(notes.count == 1)
        #expect(notes.first?.dateKeyRaw == day.raw)
        #expect(notes.first?.text == "Sortie longue.")
    }

    @Test("A text on a day that has one rewrites it")
    func updates() throws {
        let context = try context()
        JournalNoteWrite.apply("Premier jet.", for: day, in: context)
        try context.save()

        #expect(JournalNoteWrite.apply("Second jet.", for: day, in: context) == .updated)
        try context.save()

        let notes = try rows(context)
        #expect(notes.count == 1)
        #expect(notes.first?.text == "Second jet.")
    }

    /// The rule that came from the folder: a note emptied to nothing must not
    /// leave a blank day behind, as an emptied file left the vault.
    @Test("A note emptied to nothing is taken out")
    func deletesWhenEmptied() throws {
        let context = try context()
        JournalNoteWrite.apply("Quelque chose.", for: day, in: context)
        try context.save()

        #expect(JournalNoteWrite.apply("  \n ", for: day, in: context) == .deleted)
        try context.save()

        #expect(try rows(context).isEmpty)
    }

    @Test("Whitespace on a day with no note leaves no row at all")
    func nothingFromNothing() throws {
        let context = try context()
        #expect(JournalNoteWrite.apply("\n\n", for: day, in: context) == .nothing)
        try context.save()

        #expect(try rows(context).isEmpty)
    }

    /// `setText` is the one path that keeps `tagsRaw` in step with the text —
    /// going around it is what would drop a note out of the sidebar's filters.
    @Test("The tags follow the text")
    func tags() throws {
        let context = try context()
        JournalNoteWrite.apply("Séance avec #sam.", for: day, in: context)
        try context.save()

        #expect(try rows(context).first?.tags == Set([JournalTag(name: "sam")!]))
    }

    /// Two days are two rows: the fetch is keyed on the day, and writing one
    /// must not reach the other.
    @Test("Each day has its own row")
    func perDay() throws {
        let context = try context()
        let other = DateKey(raw: "2026-08-15")!
        JournalNoteWrite.apply("Le 14.", for: day, in: context)
        JournalNoteWrite.apply("Le 15.", for: other, in: context)
        try context.save()

        #expect(try rows(context).count == 2)
        #expect(JournalNoteWrite.row(for: day, in: context)?.text == "Le 14.")
        #expect(JournalNoteWrite.row(for: other, in: context)?.text == "Le 15.")
    }

    // MARK: - Un jour, une note

    /// Les deux textes ont été écrits pour de bon et aucun n'a vu l'autre :
    /// en garder un seul reviendrait à jeter ce que quelqu'un a écrit.
    @Test("Deux notes du même jour sont recollées en une")
    func foldRecolleLesDeuxTextes() throws {
        let context = try context()
        let ancienne = JournalNote(dateKey: day, text: "Écrit sur le Mac.")
        ancienne.applyMirrored(
            text: "Écrit sur le Mac.", editedAt: Date(timeIntervalSince1970: 1_000)
        )
        let recente = JournalNote(dateKey: day, text: "Écrit sur le téléphone.")
        recente.applyMirrored(
            text: "Écrit sur le téléphone.", editedAt: Date(timeIntervalSince1970: 2_000)
        )
        context.insert(ancienne)
        context.insert(recente)
        try context.save()

        #expect(JournalNoteWrite.foldDuplicateDays(in: context) == 1)
        try context.save()

        let notes = try rows(context)
        #expect(notes.count == 1)
        // La plus récente survit, et le texte se lit dans l'ordre où il a été
        // écrit.
        #expect(notes.first?.uuid == recente.uuid)
        #expect(notes.first?.text == "Écrit sur le Mac.\n\nÉcrit sur le téléphone.")
    }

    @Test("Un jour qui n'a qu'une note n'est pas touché")
    func foldNeToucheRienSansDoublon() throws {
        let context = try context()
        JournalNoteWrite.apply("Sortie longue.", for: day, in: context)
        try context.save()

        #expect(JournalNoteWrite.foldDuplicateDays(in: context) == 0)
        #expect(try rows(context).first?.text == "Sortie longue.")
    }

    /// La ligne écartée dort encore dans le miroir et peut en revenir : sans
    /// le test de contenance, chaque passage rallongerait la note d'une copie
    /// d'elle-même.
    @Test("Un texte déjà contenu ne s'ajoute pas une seconde fois")
    func fusionNeRepetePasCeQuelleContientDeja() {
        let fondu = JournalNoteWrite.fusion(["Le matin.", "Le matin.\n\nLe soir."])
        #expect(fondu == "Le matin.\n\nLe soir.")
        #expect(JournalNoteWrite.fusion([fondu, "Le matin."]) == fondu)
    }

    @Test("Un texte vide ne compte pas dans la fusion")
    func fusionIgnoreLeVide() {
        #expect(JournalNoteWrite.fusion(["   ", "Le soir."]) == "Le soir.")
    }
}
