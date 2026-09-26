import Testing
import Foundation
import SwiftData
@testable import Cairn

@Suite("Restaurations de textes en attente")
struct PendingRestorationsTests {
    private func file(_ json: String) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "cairn-restaurations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "restaurations-mentions.json")
        try Data(json.utf8).write(to: url)
        return url
    }

    @Test("les mentions reviennent là où le texte n'a pas bougé, et nulle part ailleurs")
    func restoresUntouchedNotes() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .walk)
        activity.activityDescription = "Balade avec Sam"
        let journal = JournalNote(dateKey: DateKey(Date()), text: "Dîner avec Tom")
        let edited = JournalNote(dateKey: DateKey(Date().addingTimeInterval(-86_400)), text: "Écrit depuis")
        let meal = MealNote(dateKey: DateKey(Date()), mealSlot: nil, note: "Chez Maman")
        context.insert(activity)
        context.insert(journal)
        context.insert(edited)
        context.insert(meal)
        try context.save()

        let url = try file("""
            {"restorations": [
              {"kind": "activity", "uuid": "\(activity.uuid)", "text": "Balade avec @Sam", "expected": "Balade avec Sam"},
              {"kind": "journal", "uuid": "\(journal.uuid)", "text": "Dîner avec @Tom", "expected": "Dîner avec Tom"},
              {"kind": "journal", "uuid": "\(edited.uuid)", "text": "Avant @Lou", "expected": "Avant Lou"},
              {"kind": "meal", "uuid": "\(meal.uuid)", "text": "Chez @Maman", "expected": "Chez Maman"},
              {"kind": "journal", "uuid": "inconnue", "text": "x", "expected": "y"}
            ]}
            """)

        let restored = try StoreMaintenance.applyPendingRestorations(in: context, file: url)

        #expect(restored == 3)
        #expect(activity.activityDescription == "Balade avec @Sam")
        #expect(journal.text == "Dîner avec @Tom")
        #expect(journal.tagsRaw.isEmpty)
        #expect(edited.text == "Écrit depuis")
        #expect(meal.note == "Chez @Maman")
        // Jamais relu : le fichier est mis de côté sous un autre nom.
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(
            atPath: url.deletingPathExtension().appendingPathExtension("appliquee.json").path
        ))
        #expect(try StoreMaintenance.applyPendingRestorations(in: context, file: url) == 0)
    }

    @Test("sans fichier, rien ne se passe")
    func noFile() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "absent-\(UUID()).json")
        #expect(try StoreMaintenance.applyPendingRestorations(in: context, file: url) == 0)
    }
}
