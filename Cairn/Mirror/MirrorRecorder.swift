import Foundation
import SwiftData
import os

/// Marks the saves the mirror makes about its own progress, so that the
/// recorder can tell them apart from the ones the user causes.
///
/// The mirror writes to models that themselves cross to Supabase: stamping
/// `ActivityPhoto.mirroredAt` or `ActivityStreams.mirroredAt` after a blob
/// goes up is a change to a `MirrorRow`, and without this it would land in
/// the outbox like any other. A full blob bootstrap would then leave one
/// entry per photo and per stream — over a thousand rows — and task 9 would
/// re-upsert the two heaviest tables for nothing. Worse, the day the push
/// stamps anything on a mirrored model, the loop would never close: pushing
/// would record a change, which would be pushed, which would record a change.
///
/// A **task-local** rather than a process-wide flag, and the difference
/// matters: the exemption follows the task that asked for it and no other, so
/// a save the user causes on a different task, at the same moment as a blob
/// upload, is still recorded. Measured: the flag reads `true` inside the
/// engine's own save, `false` for a user save before or after it, and `false`
/// inside a detached task started from within the exemption.
///
/// It works because `ModelContext.willSave` is delivered *synchronously*,
/// inside `save()`, on the calling task — so the value set just outside is
/// still in scope when the recorder reads it.
enum MirrorBookkeeping {
    @TaskLocal static var isActive = false

    /// Runs a save the mirror makes for its own bookkeeping. Wrap the `save()`
    /// itself, not the mutations: only what happens inside is exempt.
    static func perform<T>(_ body: () throws -> T) rethrows -> T {
        try $isActive.withValue(true, operation: body)
    }
}

/// Turns every local save into a trail the mirror can replay. One hook, on
/// `ModelContext.willSave`, instead of a `changedAt` posed by hand at each of
/// the hundreds of places this application writes to the store.
///
/// What the notification actually provides, measured rather than assumed:
/// its `object` is the saving `ModelContext`, its `userInfo` is `nil`, and the
/// context's `insertedModelsArray`, `changedModelsArray` and
/// `deletedModelsArray` are all populated and readable at that point — a
/// deleted object's `uuid` included, cascaded children too, which is what
/// makes a tombstone possible. It is delivered synchronously, on whichever
/// thread called `save()`, before the store is touched.
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
///
/// ## When to start it
///
/// **Only once the mirror is configured**, and that is a decision rather than
/// an oversight. Nothing here prunes the outbox: entries are removed by the
/// push (task 9) when it manages to send them. On a Mac where Supabase is
/// never set up, the push never runs, so a recorder started at launch would
/// grow the store by one row per write, for ever, in the service of a feature
/// the user does not use. Task 10, which does the wiring, owes the outbox
/// either a configured mirror or no recorder at all.
///
/// Starting late is safe: what is written while the recorder is stopped is
/// simply not in the trail, and `MirrorEngine.bootstrap()` is what re-establishes
/// a coherent state. Starting it *after* the mirror is configured but *before*
/// that bootstrap is the intended order.
@MainActor
final class MirrorRecorder {
    private let container: ModelContainer

    /// Held outside actor isolation so `deinit` — which is `nonisolated` on a
    /// `@MainActor` class — can still unsubscribe. It is only ever mutated
    /// from `start()` and `stop()`, both main-actor bound, and read in
    /// `deinit`, which by definition runs when no other reference survives:
    /// there is no moment when two things touch it.
    private nonisolated(unsafe) var token: (any NSObjectProtocol)?

    /// How many times since launch the outbox could not be written. Not
    /// persisted, and deliberately not an error thrown at the user: a failure
    /// here costs a stale row in Supabase, never anything local. Task 11's
    /// settings indicator reads it, which is the only reason it exists —
    /// before it, the one `print` in all of `Cairn/` was the only trace.
    /// `nonisolated`, all three: the callback that increments it runs on
    /// whichever thread saved, and a settings view should be able to read it
    /// without hopping.
    nonisolated static var failureCount: Int { failures.withLock { $0 } }

    private nonisolated static let failures = OSAllocatedUnfairLock(initialState: 0)

    /// For tests, which must not inherit another test's tally.
    nonisolated static func resetFailureCount() { failures.withLock { $0 = 0 } }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Unsubscribes an enregistreur that was dropped without `stop()`.
    ///
    /// Without this the observer outlives the object that owns it and becomes
    /// impossible to remove — the block does not retain the recorder, so the
    /// token dies with it while `NotificationCenter` keeps both the closure
    /// and, through it, the `ModelContainer` alive for the life of the
    /// process. Harmless for a single permanent recorder; a silent trap in a
    /// test, or for any later code that makes one per screen.
    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
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
        // The mirror's own bookkeeping is not a change the mirror needs to
        // hear about. First, before any work: this is the common case during
        // a blob upload.
        guard !MirrorBookkeeping.isActive else { return }

        // Only this container's saves. A global observer would otherwise fire
        // for every other store in the process — which, in a test run, means
        // every in-memory container the rest of the suite builds.
        guard let context = notification.object as? ModelContext,
              context.container === container
        else { return }

        let entries = pendingEntries(in: context)
        guard !entries.isEmpty else { return }

        let side = ModelContext(container)
        for entry in entries { side.insert(entry) }
        do {
            try side.save()
        } catch {
            // Deliberately swallowed, see above — but counted, so that the
            // settings indicator can say the mirror is falling behind.
            failures.withLock { $0 += 1 }
        }
    }

    /// One outbox entry per changed row, deletions included.
    ///
    /// Only models conforming to `MirrorRow` are kept: that protocol *is* the
    /// list of what crosses to Supabase, so `SyncState` — the one library
    /// model that stays local — is excluded without a list to maintain.
    private nonisolated static func pendingEntries(in context: ModelContext) -> [MirrorOutbox] {
        // Keyed by table and row so a single save that both inserts and
        // mutates the same object leaves one entry, not two, and so a
        // deletion always wins over a change recorded for the same row in the
        // same transaction.
        var byRow: [String: MirrorOutbox] = [:]

        func note(_ model: any PersistentModel, isDeletion: Bool) {
            // The recursion guard, stated rather than inferred. Saving the
            // outbox posts `willSave` again; that nested notification carries
            // `MirrorOutbox` objects, and if they ever produced entries the
            // save would recurse until the stack ran out — during a user's
            // save, at that. It holds today because `MirrorOutbox` is not a
            // `MirrorRow` and must never become one, but a guard that depends
            // on a conformance staying absent is a guard one contributor can
            // remove by accident. This line does not depend on it.
            guard !(model is MirrorOutbox) else { return }
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
