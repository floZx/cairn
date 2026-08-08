// Tests/FileDownloaderTests.swift
import Testing
import Foundation
@testable import Cairn

@Suite("FileDownloader")
struct FileDownloaderTests {
    private func makeDestination() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "download-\(UUID().uuidString)")
            .appending(path: "file.gz")
    }

    private func body(_ chunks: [Data]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }

    private func response(
        _ status: Int, headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://exemple.test/file.gz")!,
            statusCode: status, httpVersion: nil, headerFields: headers
        )!
    }

    /// A transport whose answers are scripted per call, recording requests.
    private final class Script: @unchecked Sendable {
        var requests: [URLRequest] = []
        var responses: [(HTTPURLResponse, AsyncThrowingStream<Data, Error>)] = []
        var transport: FileDownloader.Transport {
            FileDownloader.Transport { [self] request in
                requests.append(request)
                return responses.removeFirst()
            }
        }
    }

    @Test("un téléchargement frais écrit le validateur puis promeut")
    func freshDownloadPromotes() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        let script = Script()
        script.responses = [(
            response(200, headers: ["ETag": "\"v1\"", "Content-Length": "10"]),
            body([Data("hello ".utf8), Data("moon".utf8)])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(try String(contentsOf: destination, encoding: .utf8) == "hello moon")
        // Ni .part ni validateur ne survivent à un succès.
        #expect(!FileManager.default.fileExists(
            atPath: destination.path + ".part"))
        #expect(!FileManager.default.fileExists(
            atPath: destination.path + ".part.etag"))
        // Pas d'en-tête Range sur un départ à zéro.
        #expect(script.requests[0].value(forHTTPHeaderField: "Range") == nil)
    }

    @Test("une reprise envoie Range et If-Range et appende")
    func resumeSendsRangeAndAppends() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("hello ".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        try Data("\"v1\"".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part.etag"))
        let script = Script()
        script.responses = [(
            response(206, headers: ["Content-Range": "bytes 6-9/10"]),
            body([Data("moon".utf8)])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(script.requests[0].value(forHTTPHeaderField: "Range") == "bytes=6-")
        #expect(script.requests[0].value(forHTTPHeaderField: "If-Range") == "\"v1\"")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "hello moon")
    }

    @Test("un .part sans validateur repart de zéro")
    func partWithoutValidatorRestarts() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stale".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        let script = Script()
        script.responses = [(
            response(200, headers: ["Content-Length": "5"]),
            body([Data("fresh".utf8)])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(script.requests[0].value(forHTTPHeaderField: "Range") == nil)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "fresh")
    }

    @Test("200 sur une reprise = fichier distant changé, on repart")
    func fullResponseOnResumeRestarts() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("old-".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        try Data("\"v1\"".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part.etag"))
        let script = Script()
        script.responses = [(
            response(200, headers: ["ETag": "\"v2\"", "Content-Length": "8"]),
            body([Data("nouveau!".utf8)])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        // Pas de collage v1+v2 : le contenu est UNIQUEMENT la réponse 200.
        #expect(try String(contentsOf: destination, encoding: .utf8) == "nouveau!")
    }

    @Test("416 avec la taille du .part = déjà complet, promotion")
    func http416MatchingSizePromotes() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("0123456789".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        try Data("\"v1\"".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part.etag"))
        let script = Script()
        script.responses = [(
            response(416, headers: ["Content-Range": "bytes */10"]),
            body([])
        )]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(try String(contentsOf: destination, encoding: .utf8) == "0123456789")
    }

    @Test("416 avec une autre taille = .part invalide, on recommence")
    func http416MismatchRestarts() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("partiel".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        try Data("\"v1\"".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part.etag"))
        let script = Script()
        script.responses = [
            (response(416, headers: ["Content-Range": "bytes */99"]), body([])),
            (
                response(200, headers: ["Content-Length": "4"]),
                body([Data("neuf".utf8)])
            ),
        ]

        try await FileDownloader.download(
            from: URL(string: "https://exemple.test/file.gz")!,
            to: destination, transport: script.transport
        )

        #expect(script.requests.count == 2)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "neuf")
    }

    @Test("un double 416 échoue au lieu de boucler")
    func doubleHTTP416Fails() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("partiel".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part"))
        try Data("\"v1\"".utf8).write(
            to: URL(fileURLWithPath: destination.path + ".part.etag"))
        let script = Script()
        script.responses = [
            (response(416, headers: ["Content-Range": "bytes */99"]), body([])),
            (response(416, headers: ["Content-Range": "bytes */99"]), body([])),
        ]

        await #expect(throws: FileDownloader.DownloadError.self) {
            try await FileDownloader.download(
                from: URL(string: "https://exemple.test/file.gz")!,
                to: destination, transport: script.transport
            )
        }
        #expect(script.requests.count == 2)
    }

    @Test("incomplet : erreur, le .part reste pour reprendre")
    func incompleteKeepsPartAndThrows() async throws {
        let destination = makeDestination()
        defer { try? FileManager.default.removeItem(
            at: destination.deletingLastPathComponent()) }
        let script = Script()
        script.responses = [(
            response(200, headers: ["ETag": "\"v1\"", "Content-Length": "10"]),
            body([Data("moitié".utf8.prefix(4))])
        )]

        await #expect(throws: FileDownloader.DownloadError.self) {
            try await FileDownloader.download(
                from: URL(string: "https://exemple.test/file.gz")!,
                to: destination, transport: script.transport
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(
            atPath: destination.path + ".part"))
        #expect(FileManager.default.fileExists(
            atPath: destination.path + ".part.etag"))
    }
}
