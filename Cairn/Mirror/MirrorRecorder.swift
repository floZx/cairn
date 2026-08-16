import Foundation
import SwiftData

/// Turns every local save into a trail the mirror can replay. One hook, on
/// `ModelContext.willSave`, instead of a `changedAt` posed by hand at each of
/// the hundreds of places this application writes to the store.
///
/// What the notification actually provides, measured rather than assumed:
/// its `object` is the saving `ModelContext`, its `userInfo` is empty, and the
/// context's `insertedModelsArray`, `changedModelsArray` and
/// `deletedModelsArray` are all populated and readable at that point — a
/// deleted object's `uuid` included, which is what makes a tombstone possible.
/// It is delivered synchronously, on whichever thread called `save()`, before
/// the store is touched.
///
/// Three consequences shape the code below:
///
/// - **The callback is nonisolated.** A save may well happen off the main
///   thread, so the closure touches no main-actor state; it captures only the
///   `ModelContainer`, which is `Sendable`, and builds everything else
///   locally. Only `start()` and `stop()`, which own the observer token, are
///   main-actor bound.
/// - **The outbox is written from a second `ModelContext`**, created inside
///   the callback and discarded with it. Inserting into the context that is
///   in the middle of its own `willSave` is not documented to work.
/// - **The write is local and synchronous.** No network, no `await`: a save
///   in the application never waits on Supabase, which is the whole plan's
///   first constraint.
@MainActor
final class MirrorRecorder {
    private let container: ModelContainer
    private var token: (any NSObjectProtocol)?

    init(container: ModelContainer) {
        self.container = container
    }

    /// Begins recording. Calling it twice is a no-op rather than a second
    /// subscription, which would double every outbox entry.
    func start() {
        guard token == nil else { return }
        let container = self.container
        token = NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: nil, queue: nil
        ) { notification in
            Self.record(notification, into: container)
        }
    }

    /// Stops recording. Safe to call when never started, and safe to call
    /// twice — the tests rely on both, since they `defer` it.
    func stop() {
        guard let token else { return }
        NotificationCenter.default.removeObserver(token)
        self.token = nil
    }

    /// The body of the observer, kept `static` so it cannot reach any
    /// main-actor state by accident.
    ///
    /// Nothing here throws outward: a notification callback has nowhere to
    /// throw to, and a failure to note a change must never be a failure to
    /// save. The local library stays authoritative; a change the mirror
    /// missed is a stale row in Supabase, not lost data on the Mac.
    private nonisolated static func record(
        _ notification: Notification, into container: ModelContainer
    ) {
        // Only this container's saves. A global observer would otherwise fire
        // for every other store in the process — which, in a test run, means
        // every in-memory container the rest of the suite builds.
        guard let context = notification.object as? ModelContext,
              context.container === container
        else { return }

        let entries = pendingEntries(in: context)
        // Before touching a second context: an empty save has nothing to
        // record, and this is also what stops the recursion. Saving the
        // outbox posts `willSave` again, that nested notification carries
        // only `MirrorOutbox` objects, none of them a `MirrorRow`, so it
        // lands here with nothing to do and returns.
        guard !entries.isEmpty else { return }

        let side = ModelContext(container)
        for entry in entries { side.insert(entry) }
        do {
            try side.save()
        } catch {
            // Deliberately swallowed, see above.
            print("MirrorRecorder: outbox non écrite — \(error)")
        }
    }

    /// One outbox entry per changed row, deletions included.
    ///
    /// Only models conforming to `MirrorRow` are kept: that protocol *is* the
    /// list of what crosses to Supabase. `MirrorOutbox` does not conform, and
    /// must not — that single fact is what keeps the notification from
    /// feeding on its own writes. `SyncState`, the one library model that
    /// stays local, is excluded by the same test.
    private nonisolated static func pendingEntries(in context: ModelContext) -> [MirrorOutbox] {
        // Keyed by table and row so a single save that both inserts and
        // mutates the same object leaves one entry, not two, and so a
        // deletion always wins over a change recorded for the same row in the
        // same transaction.
        var byRow: [String: MirrorOutbox] = [:]

        func note(_ model: any PersistentModel, isDeletion: Bool) {
            guard let row = model as? any MirrorRow else { return }
            let table = type(of: row).mirrorTable
            let key = "\(table)|\(row.uuid)"
            if let existing = byRow[key], existing.isDeletion { return }
            byRow[key] = MirrorOutbox(table: table, rowUUID: row.uuid, isDeletion: isDeletion)
        }

        for model in context.insertedModelsArray { note(model, isDeletion: false) }
        for model in context.changedModelsArray { note(model, isDeletion: false) }
        // Last, and reading `uuid` while the object is still there to be read:
        // once the save goes through, nothing else will ever mention this row
        // again, so this entry is the mirror's only chance to learn it is gone.
        for model in context.deletedModelsArray { note(model, isDeletion: true) }

        return Array(byRow.values)
    }
}
