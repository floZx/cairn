import Testing
import SwiftData
import Foundation
@testable import Cairn

@Suite("ActivityEditorSheet.Mode")
@MainActor
struct ActivityEditorSheetModeTests {
    @Test("l'id diffère entre deux activités et entre édition et création")
    func idsAreDistinct() throws {
        // `Mode` feeds `sheet(item:)`: two ids that collided would present the
        // wrong sheet — the edit form for the activity just closed, say —
        // with nothing on screen to say it happened.
        let context = ModelContext(try AppModelContainer.inMemory())
        let first = Activity(stravaID: 1, name: "Sortie A", sportType: .run)
        let second = Activity(stravaID: 2, name: "Sortie B", sportType: .ride)
        context.insert(first)
        context.insert(second)

        let editFirst = ActivityEditorSheet.Mode.edit(first).id
        let editSecond = ActivityEditorSheet.Mode.edit(second).id
        let create = ActivityEditorSheet.Mode.create.id

        #expect(editFirst != editSecond)
        #expect(editFirst != create)
        #expect(editSecond != create)
    }

    @Test("le mode édition applique le brouillon sur la même activité")
    func editModeAppliesInPlace() throws {
        let context = ModelContext(try AppModelContainer.inMemory())
        let activity = Activity(stravaID: 1, name: "Sortie", sportType: .run)
        activity.distance = 10_000
        activity.movingTime = 3_600
        context.insert(activity)

        // A round trip with nothing changed: converting the activity to a
        // draft and back through the mode must not move any value.
        let draft = ActivityDraft(activity)
        let result = ActivityEditorSheet.Mode.edit(activity).apply(draft)

        #expect(result === activity)
        #expect(result.name == "Sortie")
        #expect(result.distance == 10_000)
        #expect(result.movingTime == 3_600)
        #expect(result.editedFields.isEmpty)
    }

    @Test("le mode création renvoie une nouvelle activité locale portant les valeurs du brouillon")
    func createModeReturnsFreshActivity() throws {
        var draft = ActivityDraft(startingOn: Date(timeIntervalSince1970: 1_700_000_000))
        draft.name = "Renforcement"
        draft.sport = .workout
        draft.movingMinutes = 45

        let result = ActivityEditorSheet.Mode.create.apply(draft)

        #expect(result.name == "Renforcement")
        #expect(result.sportType == .workout)
        #expect(result.source == .manual)
        #expect(result.stravaID == 0)
        // Not inserted by `apply` itself — that stays the caller's job, since
        // only the caller holds the `ModelContext`. An activity nobody has
        // inserted belongs to no context, which a fetch could not have
        // falsified — it would come back empty from an empty context whether
        // or not `apply` inserted into some *other* context.
        #expect(result.modelContext == nil)
    }
}
