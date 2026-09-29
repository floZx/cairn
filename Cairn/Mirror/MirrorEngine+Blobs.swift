import Foundation
import SwiftData

// The bytes behind the rows: photos, journal pictures and streams, sent to
// Storage before the rows that name them.
extension MirrorEngine {
    /// Uploads every blob Storage does not have yet: `ActivityPhoto.data`
    /// first, then `ActivityStreams`' eleven streams packaged into the one
    /// JSON object per row task 5's schema comment describes. Called by
    /// `bootstrap()`, and safe to call on its own — `Tests/MirrorBlobTests.swift`
    /// does exactly that.
    ///
    /// A row with no bytes yet — a photo whose Strava download hasn't landed,
    /// an `ActivityStreams` GPX import still in flight — is left untouched
    /// rather than marked done: `mirroredAt` only ever moves from `nil` to a
    /// date, never back, so leaving it `nil` is what lets a later call catch
    /// the bytes once they exist. Visiting it again costs a fetch, never an
    /// HTTP request — the whole point, since 852 activities synced before
    /// their photos would otherwise cost 852 requests for nothing every
    /// bootstrap.
    ///
    /// One upload at a time, never in parallel: 342 photos launched together
    /// would saturate the link and the free egress quota alike.
    ///
    /// An upload that fails is **counted, not thrown**: it leaves `mirroredAt`
    /// nil so a later call retries it, and the sweep carries on to the next
    /// object. Storage's own policies are the one part of this mirror never
    /// exercised against a real project — `owner = auth.uid()` against
    /// `owner_id` on recent Supabase — and a durable 403 there would
    /// otherwise fail `bootstrap()` before a single scalar row had left the
    /// Mac, since blobs go first. A row pointing at an object that is not
    /// there is a degraded read for the web; nothing at all is no read. The
    /// tally reaches the user through `MirrorProgress.failedUploads`.
    ///
    /// Returns that tally, so `Tests/MirrorBlobTests.swift` can assert on it
    /// without going through the main actor.
    ///
    /// Reports its own progress through `.uploadingBlobs`, exactly as
    /// `sendBatches` reports `.bootstrapping` — it did not, once, and that
    /// was the bug: 342 photos and 852 traces at one request apiece run
    /// minutes ahead of the first row, all of it before `bootstrap()`
    /// reaches `sendTable()`, so a caller that never hears from this method
    /// sees `phase` sitting at `.idle` — the *resting* mirror's own text —
    /// for the entire wait, `MirrorSettingsView`'s buttons never grey out,
    /// and a second click lands in `AppEnvironment.runMirror`'s silent
    /// `guard mirrorTask == nil` with nothing on screen to explain why. Fixed
    /// here, not there: `runMirror`'s guard is the same shape `runSync`
    /// already uses for Strava, and a visible phase is what makes that
    /// silence read as "busy" instead of "broken".
    @discardableResult
    func uploadPendingBlobs() async throws -> Int {
        guard let userID = await client.userID else {
            throw MirrorError.notConfigured
        }
        var failures = 0
        failures += try await uploadPendingPhotos(userID: userID)
        failures += try await uploadPendingStreams(userID: userID)
        failures += try await uploadPendingJournalPictures(userID: userID)
        // Assigned, never accumulated: a run that finally gets its objects
        // through must clear what the previous one reported.
        await MainActor.run { progress.failedUploads = failures }
        return failures
    }

    /// Pages through `ActivityPhoto` by `uuid`, `blobBatchSize` at a time,
    /// uploading whichever of them still has `data` and marking it with
    /// `mirroredAt`. Structured exactly like `sendBatches`: a fresh
    /// `ModelContext` per page, an explicit `.lexical` comparator on the
    /// sort, `try Task.checkCancellation()` before every page — the same
    /// three fixes that section's doc comment explains, for the same
    /// reasons, applied to a table that carries actual image bytes rather
    /// than a `storage_path` string.
    ///
    /// Paged by `uuid > lastUUID` with `lastUUID` advanced to the last row of
    /// *every* page — including one where every photo was skipped for having
    /// no bytes — rather than by `mirroredAt == nil` alone: without that
    /// advance, a page consisting entirely of not-yet-downloaded photos would
    /// never change from one iteration to the next, looping forever instead
    /// of finishing the sweep and returning control to `bootstrap()`.
    ///
    /// Returns how many uploads failed — see `uploadPendingBlobs()` for why a
    /// failure is counted rather than thrown.
    ///
    /// `total` is a count taken once, before the loop — the same shape
    /// `sendBatches` uses for its own `total` — so `done`/`total` describes
    /// this sweep's fixed target throughout, not a shrinking one as rows get
    /// their `mirroredAt` stamped underneath it. `done` advances by
    /// `page.count`, whole pages at a time, counting rows *visited*
    /// (uploaded or skipped for lacking bytes) rather than rows sent — it
    /// has to, since a page of not-yet-downloaded photos would otherwise
    /// never move `done` at all, misreporting a sweep that is in fact making
    /// progress through the table as stuck. Reported through `setPhase`,
    /// never left silent: 342 photos at one request apiece take minutes, and
    /// that is exactly the run `MirrorProgress.statusText`'s own doc comment
    /// says must not read the same as a mirror at rest.
    func uploadPendingPhotos(userID: String) async throws -> Int {
        let total = try ModelContext(container).fetchCount(
            FetchDescriptor<ActivityPhoto>(predicate: #Predicate<ActivityPhoto> { $0.mirroredAt == nil })
        )
        guard total > 0 else { return 0 }

        var failures = 0
        var done = 0
        var lastUUID: String?
        await setPhase(.uploadingBlobs(kind: "photos", done: done, total: total))
        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            var descriptor: FetchDescriptor<ActivityPhoto>
            if let cursorUUID = lastUUID {
                descriptor = FetchDescriptor<ActivityPhoto>(
                    predicate: #Predicate<ActivityPhoto> {
                        $0.mirroredAt == nil && $0.uuid > cursorUUID
                    }
                )
            } else {
                descriptor = FetchDescriptor<ActivityPhoto>(
                    predicate: #Predicate<ActivityPhoto> { $0.mirroredAt == nil }
                )
            }
            descriptor.sortBy = [SortDescriptor(\.uuid, comparator: .lexical)]
            descriptor.fetchLimit = Self.blobBatchSize
            let page = try context.fetch(descriptor)
            if page.isEmpty { break }
            lastUUID = page.last?.uuid

            for photo in page {
                try Task.checkCancellation()
                guard let data = photo.data else { continue }
                do {
                    try await client.upload(
                        bucket: Self.photosBucket,
                        path: photo.blobStoragePath(userID: userID),
                        data: data,
                        // Nothing downstream of the Strava fetch records the
                        // real MIME type; every photo Strava has ever served
                        // this app has been a JPEG in practice.
                        contentType: "image/jpeg"
                    )
                    photo.mirroredAt = Date()
                } catch is CancellationError {
                    // Interrupting is not failing: it must reach `bootstrap()`
                    // as itself, never as one more counted upload.
                    throw CancellationError()
                } catch {
                    // `mirroredAt` deliberately left nil: this object is owed,
                    // and the next sweep is what pays it.
                    failures += 1
                }
            }
            // Bookkeeping, not a change to mirror: `ActivityPhoto` is itself a
            // `MirrorRow`, so without this the recorder would file one outbox
            // entry per photo uploaded and the next push would re-upsert the
            // whole table for nothing.
            try MirrorBookkeeping.perform { try context.save() }
            done += page.count
            await setPhase(.uploadingBlobs(kind: "photos", done: done, total: total))
        }
        return failures
    }

    /// The journal's pictures, on `uploadPendingPhotos`' pattern exactly:
    /// same paging by key, same cursor, same bookkeeping exemption.
    ///
    /// One difference worth its line: the content type is derived from the
    /// file name rather than assumed. A journal picture is whatever the user
    /// dropped — `JournalAttachmentRules.allowedExtensions` allows JPEG, PNG
    /// and HEIC — where a Strava photo has only ever been a JPEG in practice.
    ///
    /// Returns how many uploads failed, same terms as `uploadPendingPhotos`.
    func uploadPendingJournalPictures(userID: String) async throws -> Int {
        let total = try ModelContext(container).fetchCount(
            FetchDescriptor<JournalAttachment>(
                predicate: #Predicate<JournalAttachment> { $0.mirroredAt == nil }
            )
        )
        guard total > 0 else { return 0 }

        var failures = 0
        var done = 0
        var lastUUID: String?
        await setPhase(.uploadingBlobs(kind: "images du journal", done: done, total: total))
        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            var descriptor: FetchDescriptor<JournalAttachment>
            if let cursorUUID = lastUUID {
                descriptor = FetchDescriptor<JournalAttachment>(
                    predicate: #Predicate<JournalAttachment> {
                        $0.mirroredAt == nil && $0.uuid > cursorUUID
                    }
                )
            } else {
                descriptor = FetchDescriptor<JournalAttachment>(
                    predicate: #Predicate<JournalAttachment> { $0.mirroredAt == nil }
                )
            }
            descriptor.sortBy = [SortDescriptor(\.uuid, comparator: .lexical)]
            descriptor.fetchLimit = Self.blobBatchSize
            let page = try context.fetch(descriptor)
            if page.isEmpty { break }
            lastUUID = page.last?.uuid

            for picture in page {
                try Task.checkCancellation()
                guard let data = picture.data else { continue }
                do {
                    try await client.upload(
                        bucket: Self.photosBucket,
                        path: picture.blobStoragePath(userID: userID),
                        data: data,
                        contentType: Self.contentType(forFileName: picture.fileName)
                    )
                    picture.mirroredAt = Date()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures += 1
                }
            }
            try MirrorBookkeeping.perform { try context.save() }
            done += page.count
            await setPhase(
                .uploadingBlobs(kind: "images du journal", done: done, total: total)
            )
        }
        return failures
    }

    /// What a journal picture's extension says it is. Falls back to JPEG,
    /// which is what `JournalAttachmentRules` writes whenever it re-encodes.
    static func contentType(forFileName name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png": "image/png"
        case "heic": "image/heic"
        default: "image/jpeg"
        }
    }

    /// `ActivityStreams`' counterpart to `uploadPendingPhotos`: same paging,
    /// same cursor-advances-regardless-of-skips reasoning, but each row
    /// contributes at most one upload — its `packagedStreams` JSON object,
    /// skipped only when every one of the eleven streams is empty (a row
    /// created before any GPX or Strava data arrived).
    ///
    /// Returns how many uploads failed, same terms as `uploadPendingPhotos`.
    ///
    /// `total`/`done` follow `uploadPendingPhotos`'s own reasoning exactly —
    /// a count taken once, advanced by whole pages, reported through
    /// `setPhase` under `kind: "traces"` rather than `"photos"`, its own
    /// sweep of `MirrorProgress.statusText`.
    func uploadPendingStreams(userID: String) async throws -> Int {
        let total = try ModelContext(container).fetchCount(
            FetchDescriptor<ActivityStreams>(predicate: #Predicate<ActivityStreams> { $0.mirroredAt == nil })
        )
        guard total > 0 else { return 0 }

        var failures = 0
        var done = 0
        var lastUUID: String?
        await setPhase(.uploadingBlobs(kind: "traces", done: done, total: total))
        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            var descriptor: FetchDescriptor<ActivityStreams>
            if let cursorUUID = lastUUID {
                descriptor = FetchDescriptor<ActivityStreams>(
                    predicate: #Predicate<ActivityStreams> {
                        $0.mirroredAt == nil && $0.uuid > cursorUUID
                    }
                )
            } else {
                descriptor = FetchDescriptor<ActivityStreams>(
                    predicate: #Predicate<ActivityStreams> { $0.mirroredAt == nil }
                )
            }
            descriptor.sortBy = [SortDescriptor(\.uuid, comparator: .lexical)]
            descriptor.fetchLimit = Self.blobBatchSize
            let page = try context.fetch(descriptor)
            if page.isEmpty { break }
            lastUUID = page.last?.uuid

            for streams in page {
                try Task.checkCancellation()
                let pieces = streams.packagedStreams
                guard !pieces.isEmpty else { continue }
                let payload = pieces.mapValues { $0.base64EncodedString() }
                let body: Data
                do {
                    body = try JSONSerialization.data(withJSONObject: payload)
                } catch {
                    throw MirrorError.encodingFailed(String(describing: error))
                }
                do {
                    try await client.upload(
                        bucket: Self.streamsBucket,
                        path: streams.blobStoragePath(userID: userID),
                        data: body,
                        contentType: "application/json"
                    )
                    streams.mirroredAt = Date()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Counted, not fatal — `uploadPendingBlobs()` explains why.
                    failures += 1
                }
            }
            // Bookkeeping, as in `uploadPendingPhotos` above.
            try MirrorBookkeeping.perform { try context.save() }
            done += page.count
            await setPhase(.uploadingBlobs(kind: "traces", done: done, total: total))
        }
        return failures
    }
}
