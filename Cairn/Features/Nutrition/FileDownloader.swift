// Cairn/Features/Nutrition/FileDownloader.swift
import Foundation

/// Resumable download with a validated `.part`, ported from suivinut's
/// `data/download.py`. Resuming is only safe when the remote file has not
/// changed in between: the validator (ETag or Last-Modified) is remembered
/// beside the partial file and sent back as `If-Range` — if the server sees
/// a change it answers 200 with the whole file, and we start over instead
/// of gluing bytes of two different versions together.
enum FileDownloader {
    struct Transport: Sendable {
        var fetch: @Sendable (URLRequest) async throws
            -> (response: HTTPURLResponse, body: AsyncThrowingStream<Data, Error>)

        static let live = Transport { request in
            try await StreamingFetch.run(request)
        }
    }

    struct DownloadError: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }

    static func download(
        from url: URL, to destination: URL,
        transport: Transport = .live,
        onProgress: (@Sendable (_ bytes: Int64, _ total: Int64?) -> Void)? = nil
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let partURL = URL(fileURLWithPath: destination.path + ".part")
        let metaURL = URL(fileURLWithPath: destination.path + ".part.etag")

        var resumeFrom: Int64 = 0
        if let size = try? fileManager
            .attributesOfItem(atPath: partURL.path)[.size] as? Int64 {
            resumeFrom = size
        }
        var validator = (try? String(contentsOf: metaURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if validator?.isEmpty == true { validator = nil }
        // A .part with no remembered validator cannot be verified: resuming
        // it could splice two versions. Start over.
        if resumeFrom > 0 && validator == nil { resumeFrom = 0 }

        var request = URLRequest(url: url)
        if resumeFrom > 0, let validator {
            request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range")
            request.setValue(validator, forHTTPHeaderField: "If-Range")
        }

        let (response, bodyStream): (HTTPURLResponse, AsyncThrowingStream<Data, Error>)
        do {
            (response, bodyStream) = try await transport.fetch(request)
        } catch {
            throw error
        }

        if response.statusCode == 416 {
            // A 416 only makes sense as the answer to a Range request. On a
            // fresh request (resumeFrom == 0) it is a genuine server error,
            // not a resume signal — raise instead of restarting, mirroring
            // the Python original's `if exc.code != 416 or not resume_from:
            // raise` guard. This also bounds the restart-on-416 recursion
            // below: after a restart resumeFrom is back to 0, so a second
            // 416 throws instead of recursing forever.
            guard resumeFrom > 0 else {
                throw DownloadError(message: "Le serveur a répondu 416.")
            }
            // Either the .part is already the whole file (crash after the
            // last byte, before promotion), or the remote size changed and
            // the .part is garbage.
            if remoteSize(from: response) == resumeFrom {
                try promote(partURL, to: destination, cleaning: metaURL)
                return
            }
            try? fileManager.removeItem(at: partURL)
            try? fileManager.removeItem(at: metaURL)
            try await download(
                from: url, to: destination, transport: transport,
                onProgress: onProgress
            )
            return
        }
        guard (200...299).contains(response.statusCode) else {
            throw DownloadError(
                message: "Le serveur a répondu \(response.statusCode)."
            )
        }

        var appending = resumeFrom > 0
        // 200 while we asked for a range: the remote file changed (If-Range)
        // or the server ignores ranges — it sends everything, start fresh.
        if appending && response.statusCode == 200 {
            appending = false
            resumeFrom = 0
        }
        var downloaded = resumeFrom
        let total = expectedTotal(of: response, resumingFrom: resumeFrom)

        if !appending {
            // Remembered BEFORE the stream: an interruption must leave a
            // coherent (.part, validator) pair for the next resume.
            let newValidator = response.value(forHTTPHeaderField: "ETag")
                ?? response.value(forHTTPHeaderField: "Last-Modified")
            if let newValidator {
                try newValidator.write(
                    to: metaURL, atomically: true, encoding: .utf8
                )
            } else {
                try? fileManager.removeItem(at: metaURL)
            }
            fileManager.createFile(atPath: partURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: partURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        do {
            // No explicit `Task.checkCancellation()` here on purpose: it
            // would fire *between* chunks, after the transport already
            // produced one, and unwind straight out of this loop without
            // ever calling into the transport again — for `.live`, that
            // abandons `StreamingFetch` with no chance to cancel its task,
            // invalidate its session, or unblock its backpressure semaphore
            // (see StreamingFetch.nextChunk's doc comment). Cancellation is
            // instead discovered on the *next* pull, which the transport
            // itself can react to and clean up after.
            for try await chunk in bodyStream {
                try handle.write(contentsOf: chunk)
                downloaded += Int64(chunk.count)
                onProgress?(downloaded, total)
            }
        } catch is CancellationError {
            // The .part stays: cancellation is a pause, not a failure.
            throw CancellationError()
        }

        if let total, downloaded != total {
            throw DownloadError(
                message: "Téléchargement incomplet : \(downloaded)/\(total) octets "
                    + "reçus. Relancez pour reprendre."
            )
        }
        try promote(partURL, to: destination, cleaning: metaURL)
    }

    private static func promote(
        _ part: URL, to destination: URL, cleaning meta: URL
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: part, to: destination)
        try? fileManager.removeItem(at: meta)
    }

    /// Total size according to the headers, nil when unknown. On a 206 the
    /// Content-Length is only the remaining bytes; Content-Range carries the
    /// full size.
    private static func expectedTotal(
        of response: HTTPURLResponse, resumingFrom resumeFrom: Int64
    ) -> Int64? {
        if let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
           let tail = contentRange.split(separator: "/").last,
           let size = Int64(tail.trimmingCharacters(in: .whitespaces)) {
            return size
        }
        if let length = response.value(forHTTPHeaderField: "Content-Length"),
           let size = Int64(length.trimmingCharacters(in: .whitespaces)) {
            return resumeFrom + size
        }
        return nil
    }

    /// The remote size a 416 announces (`Content-Range: bytes */N`).
    private static func remoteSize(from response: HTTPURLResponse) -> Int64? {
        guard let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
              let tail = contentRange.split(separator: "/").last
        else { return nil }
        return Int64(tail.trimmingCharacters(in: .whitespaces))
    }
}

/// URLSession streaming without buffering the gigabyte in memory: a data
/// task whose delegate forwards each received chunk into a *bounded* pull
/// pipeline.
///
/// Waiting is expressed with continuations, not a blocking `NSCondition`:
/// Swift 6 marks `NSLock`/`NSCondition`'s `lock()`/`wait()`/`unlock()`
/// `noasync`, so they cannot be called directly inside an `async` function
/// body. Calling them inside the *synchronous* closure that
/// `withCheckedThrowingContinuation` runs is legal — that closure isn't
/// itself `async` — so the FIFO's lock only ever gets taken from there and
/// from the (equally synchronous) delegate callbacks.
private final class StreamingFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var responseContinuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?

    // A gigabyte download must never buffer faster than the disk drains it.
    // `capacity` is a 64-slot counting semaphore: `didReceive` blocks on it
    // before enqueuing a chunk, which blocks URLSession's own delegate queue
    // and, transitively, its socket reads — real backpressure, not an
    // unbounded buffer racing ahead of `FileHandle.write`. `lock` guards the
    // FIFO, the single parked pull continuation, and `terminated` (see
    // `shutdown()`).
    private let capacity = DispatchSemaphore(value: 64)
    private let lock = NSLock()
    private var queue: [Data] = []
    private var finished = false
    private var streamError: Error?
    private var pendingPull: CheckedContinuation<Data?, Error>?
    private var terminated = false

    static func run(
        _ request: URLRequest
    ) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        let delegate = StreamingFetch()
        let session = URLSession(
            configuration: .ephemeral, delegate: delegate, delegateQueue: nil
        )
        let task = session.dataTask(with: request)
        delegate.task = task
        delegate.session = session
        let stream = AsyncThrowingStream<Data, Error>(unfolding: {
            try await delegate.nextChunk()
        })
        // Cancelling the surrounding Task while we're only waiting for
        // headers must not hang: withTaskCancellationHandler cancels the
        // URLSessionTask, which makes didCompleteWithError fire and resume
        // the continuation with an error instead of leaving it suspended
        // forever.
        let response: HTTPURLResponse
        do {
            response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.responseContinuation = continuation
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            // `onCancel`'s `task.cancel()` makes URLSession fail the task
            // with URLError(.cancelled), a plain error — not Swift's
            // CancellationError. Left as-is, that error propagates through
            // FileDownloader.download's `try await transport.fetch(request)`
            // as a raw NSError and CatalogUpdater's `catch is
            // CancellationError` misses it entirely, painting a red failure
            // for what is really just « Annuler ». Map it back to Swift's
            // cancellation vocabulary so every catcher downstream (including
            // ones that only know `is CancellationError`) sees a pause,
            // not a failure. Guarded by Task.isCancelled so a genuine
            // network-level cancel (unrelated to our Task) still surfaces.
            if (error as? URLError)?.code == .cancelled, Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
        return (response, stream)
    }

    /// Pulled by the consumer (`FileDownloader`'s `for try await`) once per
    /// chunk. Returns immediately if a chunk is already queued or the
    /// stream already finished; otherwise parks a continuation that
    /// `didReceive` / `didCompleteWithError` resume once there is something
    /// to report.
    ///
    /// Cancellation has two entry points here, both required: (1) if the
    /// surrounding Task is *already* cancelled when this is called — the
    /// common case, since `FileDownloader.download()`'s loop discovers
    /// cancellation between chunks, after `nextChunk()` already returned —
    /// checking `Task.isCancelled` up front catches it on the very next
    /// pull and runs `shutdown()` before anything is parked; (2) if
    /// cancellation happens *while* this call is suspended waiting for more
    /// data, `withTaskCancellationHandler`'s `onCancel` runs `shutdown()`
    /// from outside. Either way `shutdown()` is what actually cancels the
    /// task, invalidates the session, and unblocks a delegate-queue thread
    /// that might be parked in `capacity.wait()` — without it, an abandoned
    /// stream would leak the task/session and leave a GCD thread blocked
    /// forever once `didReceive` fills the 64-slot capacity semaphore and
    /// nobody is left to drain it.
    private func nextChunk() async throws -> Data? {
        if Task.isCancelled {
            shutdown()
            throw CancellationError()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if terminated {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let chunk = dequeueLocked() {
                    lock.unlock()
                    continuation.resume(returning: chunk)
                } else if finished {
                    let error = streamError
                    lock.unlock()
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    pendingPull = continuation
                    lock.unlock()
                }
            }
        } onCancel: { [weak self] in
            self?.shutdown()
        }
    }

    /// Must be called with `lock` held. Dequeues a chunk and frees the
    /// capacity slot it held, or returns nil if the queue is empty.
    private func dequeueLocked() -> Data? {
        guard !queue.isEmpty else { return nil }
        let chunk = queue.removeFirst()
        capacity.signal()
        return chunk
    }

    /// Resumes a parked pull once there is a chunk or a terminal state.
    /// Only ever called from delegate callbacks, which URLSession serializes
    /// on its own delegate queue, so at most one call runs at a time.
    private func deliverIfPending() {
        lock.lock()
        guard let continuation = pendingPull else {
            lock.unlock()
            return
        }
        if let chunk = dequeueLocked() {
            pendingPull = nil
            lock.unlock()
            continuation.resume(returning: chunk)
        } else if finished {
            pendingPull = nil
            let error = streamError
            lock.unlock()
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: nil)
            }
        } else {
            lock.unlock()
        }
    }

    /// Cancellation cleanup, safe to call more than once (idempotent via
    /// `terminated`) and from either `nextChunk()`'s upfront check or its
    /// `onCancel` handler. Cancels the network task, invalidates the
    /// session, resumes any parked pull with `CancellationError`, and
    /// signals `capacity` once to rescue a delegate-queue thread that may
    /// already be blocked inside `didReceive`'s `capacity.wait()` — at most
    /// one such call can be in flight at a time, since URLSession serializes
    /// delegate callbacks on its own queue.
    private func shutdown() {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return
        }
        terminated = true
        queue.removeAll()
        let pending = pendingPull
        pendingPull = nil
        lock.unlock()
        pending?.resume(throwing: CancellationError())
        task?.cancel()
        session?.invalidateAndCancel()
        capacity.signal()
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            responseContinuation?.resume(returning: http)
            responseContinuation = nil
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
    ) {
        lock.lock()
        let alreadyTerminated = terminated
        lock.unlock()
        guard !alreadyTerminated else { return }

        // Blocks the delegate queue — and so URLSession's socket reads —
        // until the consumer has drained a slot. `shutdown()` rescues this
        // with one extra `capacity.signal()` if nobody will ever drain
        // again.
        capacity.wait()
        lock.lock()
        if terminated {
            lock.unlock()
            // Nobody will consume this chunk: give the slot back instead of
            // leaking it, in case more data arrives before the task
            // actually stops.
            capacity.signal()
            return
        }
        queue.append(data)
        lock.unlock()
        deliverIfPending()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            responseContinuation?.resume(throwing: error)
            responseContinuation = nil
        }
        lock.lock()
        streamError = error
        finished = true
        lock.unlock()
        deliverIfPending()
        session.finishTasksAndInvalidate()
    }
}
