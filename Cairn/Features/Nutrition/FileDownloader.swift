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
            // Either the .part is already the whole file (crash after the
            // last byte, before promotion), or the remote size changed and
            // the .part is garbage.
            if remoteSize(from: response) == resumeFrom, resumeFrom > 0 {
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
            for try await chunk in bodyStream {
                try Task.checkCancellation()
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
/// task whose delegate forwards each received chunk into an AsyncStream.
private final class StreamingFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var responseContinuation: CheckedContinuation<HTTPURLResponse, Error>?

    static func run(
        _ request: URLRequest
    ) async throws -> (HTTPURLResponse, AsyncThrowingStream<Data, Error>) {
        let delegate = StreamingFetch()
        let session = URLSession(
            configuration: .ephemeral, delegate: delegate, delegateQueue: nil
        )
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            delegate.continuation = continuation
            continuation.onTermination = { @Sendable _ in
                session.invalidateAndCancel()
            }
        }
        let task = session.dataTask(with: request)
        let response = try await withCheckedThrowingContinuation { continuation in
            delegate.responseContinuation = continuation
            task.resume()
        }
        return (response, stream)
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
        continuation?.yield(data)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            responseContinuation?.resume(throwing: error)
            responseContinuation = nil
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        session.finishTasksAndInvalidate()
    }
}
