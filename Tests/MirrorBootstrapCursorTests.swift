import Testing
import Foundation
@testable import Cairn

/// `MirrorBootstrapCursor.clear()` — added after review of task 10, for
/// `AppEnvironment.forgetMirror()`: a curseur left in place after forgetting
/// a project would make a bootstrap against a *different* project silently
/// skip every row sorting before it. Exercised directly on the cursor, on a
/// throwaway `UserDefaults` suite (`freshCursor()`/`discard()` from
/// `Tests/MirrorTestSupport.swift`), never `UserDefaults.standard` — the same
/// rule every other mirror test follows, and the reason `AppEnvironment`
/// itself is not constructed here: its `init` hard-codes `.standard` for
/// this very cursor, exactly to keep a stray key from surviving between
/// test runs.
@Suite("Curseur d'amorçage")
struct MirrorBootstrapCursorTests {
    @Test func effacerOteLaPositionDeChaqueTable() {
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }

        cursor.setLastUUID("AAA", for: "activity")
        cursor.setLastUUID("BBB", for: "weight_entry")
        cursor.setLastPushAt(Date())

        #expect(cursor.lastUUID(for: "activity") != nil)
        #expect(cursor.lastUUID(for: "weight_entry") != nil)
        #expect(cursor.lastPushAt() != nil)

        cursor.clear()

        #expect(cursor.lastUUID(for: "activity") == nil)
        #expect(cursor.lastUUID(for: "weight_entry") == nil)
        #expect(cursor.lastPushAt() == nil)
    }

    /// A cursor that never recorded anything is already in the state
    /// `clear()` is meant to produce — calling it anyway must not throw or
    /// crash, since `forgetMirror()` has no way of knowing in advance
    /// whether a bootstrap ever ran.
    @Test func effacerUnCurseurViergeNeFaitRien() {
        let (cursor, suiteName) = freshCursor()
        defer { discard(suiteName) }

        cursor.clear()

        #expect(cursor.lastUUID(for: "activity") == nil)
        #expect(cursor.lastPushAt() == nil)
    }
}
