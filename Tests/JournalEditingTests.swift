import Testing
@testable import Cairn

@Suite("Édition d'une note du journal")
struct JournalEditingTests {
    private let mardi = DateKey(raw: "2026-08-11")!
    private let mercredi = DateKey(raw: "2026-08-12")!

    @Test("une note s'ouvre en lecture")
    func startsReading() {
        let editing = JournalEditing()
        #expect(editing.note == nil)
        #expect(!editing.isEditing(mardi))
    }

    @Test("l'éditeur demandé ne s'ouvre que sur la note demandée")
    func requestNamesTheNote() {
        var editing = JournalEditing()
        editing.requested(for: mardi)
        #expect(editing.isEditing(mardi))
        #expect(!editing.isEditing(mercredi))
    }

    @Test("changer de note revient en lecture")
    func leavingReturnsToReading() {
        var editing = JournalEditing()
        editing.requested(for: mardi)
        editing.left(mardi)
        #expect(!editing.isEditing(mardi))
        #expect(!editing.isEditing(mercredi))
    }

    @Test("demande puis changement de note : l'éditeur s'ouvre")
    func requestThenNoteChange() {
        // ⌘N depuis une autre note : les deux évènements arrivent ensemble, et
        // SwiftUI ne promet pas dans quel ordre. Ici la demande passe la
        // première et a déjà inscrit la note du jour.
        var editing = JournalEditing()
        editing.requested(for: mardi)
        editing.requested(for: mercredi)
        editing.left(mardi)
        #expect(editing.isEditing(mercredi))
    }

    @Test("changement de note puis demande : l'éditeur s'ouvre aussi")
    func noteChangeThenRequest() {
        // Le même ⌘N, dans l'autre ordre. C'est le bogue qu'un simple booléen
        // laissait passer : le nettoyage annulait la demande.
        var editing = JournalEditing()
        editing.requested(for: mardi)
        editing.left(mardi)
        editing.requested(for: mercredi)
        #expect(editing.isEditing(mercredi))
    }

    @Test("revenir sur une note qu'on éditait l'ouvre en lecture")
    func comingBackOpensReading() {
        // Sans quoi la note se rouvrirait dans l'éditeur sans qu'on l'ait
        // demandé, des notes plus tard.
        var editing = JournalEditing()
        editing.requested(for: mardi)
        editing.left(mardi)
        editing.left(mercredi)
        #expect(!editing.isEditing(mardi))
    }

    @Test("échap termine l'édition")
    func escapeEndsIt() {
        var editing = JournalEditing()
        editing.requested(for: mardi)
        editing.ended()
        #expect(editing.note == nil)
    }
}
