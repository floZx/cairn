import Foundation

/// Disk cache for raster tiles.
///
/// Reintroduced on its own, and that matters: an earlier attempt bundled a
/// cache with a four-connection cap, an aggressive policy and retries, tiles
/// stopped arriving, and the whole lot was reverted. The culprit turned out to
/// be elsewhere — MapKit properties rewritten on every view update. So this
/// adds the cache and nothing else: no connection limit, no retries.
enum TileCache {
    private static let directory = URL.cachesDirectory
        .appending(path: "StravaLocal/Tiles")

    static let session: URLSession = {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 1024 * 1024 * 1024,
            directory: directory
        )
        // A cached tile is used whatever its age, and the network is touched
        // only when there is none. Map tiles change on the scale of months, and
        // the point is to stop re-fetching the same few départements forever.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        // OpenStreetMap-family services ask that clients identify themselves.
        configuration.httpAdditionalHeaders = [
            "User-Agent": "StravaLocal (personal use)"
        ]
        return URLSession(configuration: configuration)
    }()

    /// Bytes currently held, so the setting can show it rather than claim it.
    static var diskUsage: Int {
        guard let files = try? FileManager.default.subpathsOfDirectory(
            atPath: directory.path(percentEncoded: false)
        ) else { return 0 }
        return files.reduce(0) { total, name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            let size = (try? FileManager.default.attributesOfItem(atPath: path))
                .flatMap { $0[.size] as? Int } ?? 0
            return total + size
        }
    }

    static func clear() {
        session.configuration.urlCache?.removeAllCachedResponses()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }
}
