import Foundation

/// What a `@Model` becomes on its way to Supabase: a table name and a row of
/// `MirrorValue`s, one call, no network and no store involved. Conformed by
/// the sixteen models that traverse — every `@Model` in `AppModelContainer.schema`
/// except `SyncState`, which describes the relationship with Strava and stays
/// local.
///
/// `mirrorRow(userID:)` never omits a column: PostgREST's upsert only writes
/// the columns present in the payload, so a column left out keeps whatever
/// value the mirror already held for it. An absent value is therefore encoded
/// as `.null`, spelled out, never dropped from the dictionary.
///
/// Four columns every mirrored table carries are deliberately never produced
/// here, and what actually writes each of them is worth being exact about:
///
/// - `updated_at` — the Postgres trigger's own clock, never this Mac's.
/// - `edited_at` — added by `MirrorEngine`, twice over: `pushRows` stamps it
///   from the outbox entry's `changedAt`, and `sendBatches` stamps it during a
///   bootstrap from `Activity.editedAt`, for the one model that holds the fact
///   locally. A row never edited keeps it null.
/// - `deleted_at` — written only by `MirrorClient.softDelete`, on the `PATCH`
///   a deletion sends. A bootstrap never writes one; nothing here ever does.
/// - `field_edited_at` — empty until a later tranche writes anything to it.
///
/// `uuid` and `user_id`, by contrast, are this protocol's job.
protocol MirrorRow {
    /// The Postgres table this model's rows belong to — `"activity"`,
    /// `"weight_entry"`, and so on, matching `supabase/schema.sql` exactly.
    static var mirrorTable: String { get }

    var uuid: String { get }

    /// This instance's row, ready to hand to `MirrorClient.upsert`.
    func mirrorRow(userID: String) -> [String: MirrorValue]
}

/// Convenience constructors for the common case: a Swift `Optional` becomes
/// either the matching `MirrorValue` case or an explicit `.null`. Kept apart
/// from `MirrorValue` itself, which task 4 already shipped and tested — these
/// are additive sugar for the conformances below, not a change to its cases
/// or its JSON encoding.
extension MirrorValue {
    static func from(_ value: String?) -> MirrorValue {
        value.map(MirrorValue.string) ?? .null
    }

    static func from(_ value: Double?) -> MirrorValue {
        value.map(MirrorValue.double) ?? .null
    }

    /// `Int64` is `MirrorValue`'s own integer case; every model property this
    /// converts is a Swift `Int`, hence the widening here rather than at each
    /// call site.
    static func from(_ value: Int?) -> MirrorValue {
        value.map { MirrorValue.int(Int64($0)) } ?? .null
    }

    static func from(_ value: Date?) -> MirrorValue {
        value.map(MirrorValue.date) ?? .null
    }
}
