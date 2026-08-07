import Foundation

/// Moves the library left behind by the app's former name.
///
/// The app shipped as *StravaLocal* and kept its data in
/// `Application Support/StravaLocal/StravaLocal.store`. Renaming the app without
/// this would silently open an empty store beside a full one — the worst
/// outcome, because it looks like the data is gone.
enum LegacyStoreMigration {
    static let legacyDirectoryName = "StravaLocal"

    /// The new name for a file in the old directory, or nil to leave it alone.
    ///
    /// Core Data locates external blobs in a sibling `.<store>_SUPPORT`
    /// directory derived from the store's own file name, so the support folders
    /// have to be renamed in step with the stores — otherwise every track and
    /// stream stored outside the database becomes unreachable.
    static func renamed(_ name: String) -> String? {
        for (old, new) in [(legacyDirectoryName, "Cairn"), (".\(legacyDirectoryName)", ".Cairn")]
        where name.hasPrefix(old) {
            return new + name.dropFirst(old.count)
        }
        return nil
    }

    /// Moves every recognised entry from `legacy` into `directory`.
    ///
    /// Returns the new names actually moved — empty when there was nothing to do,
    /// which is the normal case on every launch after the first.
    ///
    /// Paths are read unencoded throughout. `URL.path()` percent-encodes, and the
    /// real library lives under "Application Support": that one space was enough
    /// to make every existence check answer no and the migration quietly do
    /// nothing, while a temporary directory in a test has no space to expose it.
    @discardableResult
    static func run(
        from legacy: URL, to directory: URL, fileManager: FileManager = .default
    ) throws -> [String] {
        let legacyPath = legacy.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: legacyPath) else { return [] }

        var moved: [String] = []
        for name in try fileManager.contentsOfDirectory(atPath: legacyPath).sorted() {
            guard let newName = renamed(name) else { continue }
            let destination = directory.appending(path: newName)
            guard !occupied(destination, fileManager: fileManager) else { continue }
            // `occupied` has already cleared this as an empty placeholder, but
            // `moveItem` refuses any existing destination, zero bytes included.
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: legacy.appending(path: name), to: destination)
            moved.append(newName)
        }
        // The empty shell is removed only once everything is out of it, so a
        // failure part-way through leaves the remaining files where they are.
        if try fileManager.contentsOfDirectory(atPath: legacyPath).isEmpty {
            try? fileManager.removeItem(at: legacy)
        }
        return moved
    }

    /// Whether something at `url` must be left alone rather than replaced.
    ///
    /// An existing Cairn store is the live one, and clobbering it with an older
    /// StravaLocal copy would lose everything recorded since the rename. A
    /// zero-byte file is the exception: SQLite creates one on any stray open, and
    /// such a placeholder would otherwise block the real library from ever being
    /// adopted — which is exactly what happened once, from a `sqlite3` command run
    /// to check the migration had worked.
    private static func occupied(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let path = url.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        guard !isDirectory.boolValue else { return true }
        let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int) ?? nil
        return (size ?? 1) > 0
    }
}
