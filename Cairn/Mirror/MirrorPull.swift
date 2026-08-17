import Foundation
import SwiftData

/// Reading Supabase back into the store — the mirror's other direction.
///
/// Deliberately narrower than the push, and the asymmetry is the design, not
/// an unfinished corner: the Mac is the authority on everything Strava sends
/// it, and nothing but the Mac writes an activity, a lap or a weight. The web
/// writes exactly one thing, a day's note, so exactly one table is read back.
/// A pull covering all eighteen would need eighteen row-to-model conversions
/// that nothing has a use for, each one a chance to overwrite Strava's own
/// data with a stale copy of itself.
///
/// The day the web learns to record a meal, this file gains a second table
/// and nothing else changes.
extension MirrorEngine {
    /// Tables read back, and by whom they are written on the other side.
    /// Kept next to the code that walks it rather than folded into
    /// `bootstrapOrder`: that list is what goes *up*, and the two are not the
    /// same set — conflating them is how a pull would start inventing local
    /// activities out of rows the Mac itself sent.
    static let pullOrder: [String] = ["journal_note"]

    /// Rows per page. Smaller than `batchSize`'s 200 for no deep reason
    /// beyond the shape of the data: a page of notes is text, a page that
    /// fails costs one round trip, and a journal never changes 100 notes
    /// between two launches anyway.
    private static var pullPageSize: Int { 100 }

    /// One row of `journal_note`, as PostgREST returns it.
    ///
    /// `updated_at` and `edited_at` arrive as strings and stay strings here:
    /// Postgres writes microseconds, and `ISO8601DateFormatter` is picky
    /// enough about fractional digits that decoding them through `Date` would
    /// make the shape of the JSON a correctness question. `date(from:)` below
    /// owns that problem in one place.
    private struct JournalNoteRow: Decodable {
        let uuid: String
        let date_key_raw: String
        let text: String
        let updated_at: String
        let edited_at: String?
        let deleted_at: String?
    }

    /// Postgres timestamps, whatever precision they come back with.
    ///
    /// Two formatters, tried in order: `timestamptz` renders fractional
    /// seconds only when it has them, so `2026-08-17T09:12:00+00:00` and
    /// `2026-08-17T09:12:00.482913+00:00` are both routine, and a single
    /// `ISO8601DateFormatter` configured for one flatly refuses the other.
    static func date(from text: String) -> Date? {
        MirrorClient.iso8601.date(from: text) ?? plainISO8601.date(from: text)
    }

    /// `nonisolated(unsafe)` on the same grounds as `MirrorClient.iso8601`:
    /// never mutated after creation.
    nonisolated(unsafe) private static let plainISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Applies everything Supabase has changed since the last pull.
    ///
    /// Safe to interrupt and safe to repeat, like `bootstrap()` and `push()`,
    /// and for a related reason: the cursor advances only past rows already
    /// written to the store, and applying the same row twice reaches the same
    /// state as applying it once. What it costs to be safe is re-reading the
    /// last row of every page — see `MirrorClient.fetchChanged`'s `gte`.
    ///
    /// Never sets `lastPushAt`: this is not a push, and a pull that quietly
    /// marked the mirror as caught up would hide an outbox that never left.
    func pull() async throws {
        do {
            guard await client.userID != nil else { throw MirrorError.notConfigured }
            var applied = 0
            await setPhase(.pulling(done: applied))
            for table in Self.pullOrder {
                try Task.checkCancellation()
                applied += try await pullTable(table, appliedSoFar: applied)
            }
            await setPhase(.idle)
        } catch is CancellationError {
            // Same reading as `bootstrap()` and `push()`: interrupting on
            // purpose is not a failure, and the cursor already sits wherever
            // the last applied page left it.
            await setPhase(.idle)
            throw CancellationError()
        } catch {
            await setPhase(.failed(error.localizedDescription))
            throw error
        }
    }

    private func pullTable(_ table: String, appliedSoFar: Int) async throws -> Int {
        var applied = 0
        // Advanced page by page rather than once at the end: a pull
        // interrupted after four pages must not start those four again.
        var since = cursor.lastPulledAt(for: table)

        while true {
            try Task.checkCancellation()
            let body = try await client.fetchChanged(
                table: table, since: since, limit: Self.pullPageSize
            )
            let outcome = try apply(table: table, body: body)
            applied += outcome.applied
            await setPhase(.pulling(done: appliedSoFar + applied))

            guard let newest = outcome.newestUpdatedAt else { return applied }
            cursor.setLastPulledAt(newest, for: table)

            // A short page is the end of the changes. A full page whose
            // newest row is no newer than what we asked for is the one way
            // this loop could spin: `gte` means a page can come back holding
            // nothing but rows already applied, and if a hundred rows ever
            // shared one microsecond the cursor would never move. Rare to the
            // point of theoretical, and a stopping condition costs one line.
            if outcome.rowCount < Self.pullPageSize { return applied }
            if let since, newest <= since { return applied }
            since = newest
        }
    }

    private struct PullOutcome {
        var rowCount = 0
        var applied = 0
        var newestUpdatedAt: Date?
    }

    /// Decodes one page and writes it to the store.
    ///
    /// Synchronous, and holding its own short-lived `ModelContext`: nothing
    /// here awaits, so the context never spans a network round trip, and the
    /// notes it registers are released with it at the end of the page.
    private func apply(table: String, body: Data) throws -> PullOutcome {
        switch table {
        case "journal_note": return try applyJournalNotes(body)
        default:
            // `pullOrder` is a closed, hand-written list and this `switch`
            // is meant to cover every entry in it. Thrown, never asserted,
            // on the same measurement `MirrorError.unknownTable` records.
            throw MirrorError.unknownTable(table)
        }
    }

    private func applyJournalNotes(_ body: Data) throws -> PullOutcome {
        let rows: [JournalNoteRow]
        do {
            rows = try JSONDecoder().decode([JournalNoteRow].self, from: body)
        } catch {
            throw MirrorError.decodingFailed(String(describing: error))
        }

        var outcome = PullOutcome(rowCount: rows.count)
        let context = ModelContext(container)
        var existing: [String: JournalNote] = [:]
        for note in try context.fetch(FetchDescriptor<JournalNote>()) {
            existing[note.uuid] = note
        }

        for row in rows {
            if let updated = Self.date(from: row.updated_at) {
                outcome.newestUpdatedAt = max(outcome.newestUpdatedAt ?? updated, updated)
            }
            // The author's clock, which is what `updatedAt` holds locally.
            // A row without one predates the column being written and cannot
            // be arbitrated against anything — left alone rather than
            // guessed at, since guessing here means overwriting a note.
            guard let editedAt = Self.date(from: row.edited_at ?? "") else { continue }

            let local = existing[row.uuid]

            if row.deleted_at != nil {
                guard let local, editedAt > local.updatedAt else { continue }
                context.delete(local)
                existing[row.uuid] = nil
                outcome.applied += 1
                continue
            }

            if let local {
                // Strictly newer, never equal: a row the Mac itself pushed
                // comes back with the very `edited_at` it sent, and applying
                // it would be a no-op that still counted as a change.
                guard editedAt > local.updatedAt else { continue }
                local.applyMirrored(text: row.text, editedAt: editedAt)
            } else {
                guard let dateKey = DateKey(raw: row.date_key_raw) else { continue }
                let note = JournalNote(dateKey: dateKey, text: row.text)
                // The remote identity, not a fresh one: a note given a new
                // `uuid` here would be pushed back as a second row, and the
                // day would end up told twice.
                note.uuid = row.uuid
                note.applyMirrored(text: row.text, editedAt: editedAt)
                context.insert(note)
                existing[row.uuid] = note
            }
            outcome.applied += 1
        }

        guard outcome.applied > 0 else { return outcome }
        // Exempt from the outbox, and this is the line that keeps the two
        // sides from talking past each other: without it `MirrorRecorder`
        // would see every applied note as a local edit and queue it for the
        // next push — the Mac sending back, under its own clock, exactly what
        // it just received.
        try MirrorBookkeeping.perform { try context.save() }
        return outcome
    }
}
