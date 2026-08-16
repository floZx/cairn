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
/// here: `updated_at` (the Postgres trigger's own clock), `edited_at` and
/// `deleted_at` (stamped by the engine at push time — tasks 6 and 9), and
/// `field_edited_at` (empty until a later tranche). `uuid` and `user_id`, by
/// contrast, are this protocol's job.
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
