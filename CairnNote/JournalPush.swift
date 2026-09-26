import Foundation
import SwiftData

/// Sends the journal's share of the outbox to Supabase, from the terminal.
///
/// Without it a note written here reached the mirror only at Cairn's next
/// launch — and Cairn cannot be open while the tool runs, so the phone and
/// the web waited on a Mac application nobody had a reason to start.
///
/// Only `journal_note`, and every pending entry of it rather than just the
/// day just written: a note from an earlier run that could not leave —
/// offline, say — goes out with this one instead of waiting for the app.
/// The other tables stay the application's business: their push needs the
/// blob uploads and the Strava reconciliation `MirrorEngine.push()` does
/// first, and none of that belongs in a note editor.
///
/// The same rules as `MirrorEngine.pushRows`, restated for one table:
/// the latest entry per row decides, `edited_at` is the entry's own
/// `changedAt`, a deletion is a soft delete, and an entry leaves the outbox
/// only once the request carrying it came back successful. Whatever fails
/// stays in the outbox, and the application sends it as it always did.
enum JournalPush {
    static let table = JournalNote.mirrorTable

    /// How many rows went out. Throws on the first request that fails;
    /// everything sent before it is already purged.
    @MainActor
    static func run(client: MirrorClient, container: ModelContainer) async throws -> Int {
        guard let userID = await client.userID else { throw MirrorError.notConfigured }

        let context = ModelContext(container)
        let table = Self.table
        // The snapshot `purge` is allowed to delete from, taken once, before
        // any request: the same guarantee `MirrorEngine.purge` spells out.
        let entries = try context.fetch(
            FetchDescriptor<MirrorOutbox>(predicate: #Predicate { $0.table == table })
        )
        guard !entries.isEmpty else { return 0 }

        // Asked before anything is read for sending: a journal encrypted on
        // Supabase must never receive a note in clear from here.
        let cipher = try await sealing(client)

        let byRow = Dictionary(grouping: entries, by: \.rowUUID)
        let latest = byRow.values.compactMap { row in row.max { $0.changedAt < $1.changedAt } }

        var sent = 0
        let updates = latest.filter { !$0.isDeletion }
        if !updates.isEmpty {
            let changedAt = Dictionary(uniqueKeysWithValues: updates.map { ($0.rowUUID, $0.changedAt) })
            let notes = try context.fetch(FetchDescriptor<JournalNote>())
                .filter { changedAt[$0.uuid] != nil }
            // A row named by an entry but gone from the store has nothing
            // left to send; its entry is purged all the same.
            if !notes.isEmpty {
                let rows = try notes.map { note -> [String: MirrorValue] in
                    var row = note.mirrorRow(userID: userID)
                    row["edited_at"] = changedAt[note.uuid].map(MirrorValue.date) ?? .null
                    if let cipher {
                        row["text"] = .string(try cipher.seal(note.text))
                        // Drawn from the text, the tags would give part of it
                        // away in clear; the phone finds them again by
                        // decrypting.
                        row["tags_raw"] = .stringArray([])
                    }
                    return row
                }
                try await client.upsert(table: table, rows: rows)
            }
            try purge(updates.map(\.rowUUID), from: byRow, in: context)
            sent += notes.count
        }

        for deletion in latest.filter(\.isDeletion) {
            try await client.softDelete(
                table: table, uuid: deletion.rowUUID, userID: userID, deletedAt: deletion.changedAt
            )
            try purge([deletion.rowUUID], from: byRow, in: context)
            sent += 1
        }
        return sent
    }

    /// The cipher to seal with, or nil when the journal travels in clear.
    ///
    /// The same decision as `MirrorEngine.journalSealing()`, which cannot be
    /// called from here — it lives on the engine, and the engine drags every
    /// table in with it. A `journal_crypto` table that does not exist yet
    /// means clear, as it does there. Encrypted without the key on this Mac
    /// is a refusal, and the entries wait in the outbox for the application.
    private static func sealing(_ client: MirrorClient) async throws -> JournalCipher? {
        let config: JournalCryptoConfig?
        do {
            config = try await client.fetchJournalCrypto()
        } catch MirrorError.http(status: 404, _) {
            config = nil
        }
        guard let config else { return nil }
        guard let key = await client.journalKey, key.salt == config.salt,
              JournalCipher(keyData: key.keyData).matches(verifier: config.verifier)
        else { throw JournalPushError.locked }
        return JournalCipher(keyData: key.keyData)
    }

    private static func purge(
        _ uuids: [String], from byRow: [String: [MirrorOutbox]], in context: ModelContext
    ) throws {
        for uuid in uuids {
            for entry in byRow[uuid] ?? [] { context.delete(entry) }
        }
        try context.save()
    }
}

enum JournalPushError: LocalizedError {
    /// Encrypted on Supabase, and the passphrase never entered on this Mac.
    case locked

    var errorDescription: String? {
        switch self {
        case .locked: "journal chiffré, et la phrase secrète n'est pas saisie sur ce Mac"
        }
    }
}
