import Foundation
import SwiftData

/// One line of the trail: a row of the library changed locally, and the
/// mirror does not know about it yet. Task 9 replays these against Supabase
/// and deletes the ones it managed to push.
///
/// Deliberately **not** a `MirrorRow`. This model never crosses — there is no
/// `mirror_outbox` table in `supabase/schema.sql`, and there must never be
/// one. It is bookkeeping about the mirror, not part of the library being
/// mirrored, and `Tests/MirrorRowSchemaTests.swift` fails if it ever gains a
/// conformance by accident.
///
/// Adding it to `AppModelContainer.schema` is a lightweight migration, on the
/// same terms as the nutrition block already noted there: a new model, no
/// change to any existing one.
@Model
final class MirrorOutbox {
    /// The Postgres table the changed row belongs to — the same string
    /// `MirrorRow.mirrorTable` produces, so task 9 can group by it without a
    /// lookup back into the type system.
    var table: String = ""

    /// The changed row's `uuid`. A string rather than a `PersistentIdentifier`
    /// on purpose: for a deletion, the object is gone by the time this is
    /// replayed, and only the `uuid` still identifies the row in the mirror.
    var rowUUID: String = ""

    /// True when the row was deleted locally. A tombstone, on the same
    /// reasoning as `DiscardedActivity`: without it a row erased on the Mac
    /// would sit in the mirror forever, since nothing else would ever mention
    /// it again.
    var isDeletion: Bool = false

    /// When the change was recorded. Task 9 replays in this order, so that a
    /// create followed by a delete cannot be replayed the other way round.
    var changedAt: Date = Date()

    init(table: String, rowUUID: String, isDeletion: Bool, changedAt: Date = Date()) {
        self.table = table
        self.rowUUID = rowUUID
        self.isDeletion = isDeletion
        self.changedAt = changedAt
    }
}
