import Foundation

/// Copies the library somewhere it survives this Mac.
///
/// A backup, deliberately, and not a sync: a synchronised store propagates a
/// deletion within seconds, which is no protection at all against the mistake
/// a backup is most often needed for. Dated snapshots, a few of them kept.
///
/// Two things are copied, and they are copied differently because they behave
/// differently. The journal is one SQLite file the app has open at all times,
/// so it is extracted with `VACUUM INTO` — a consistent point-in-time copy
/// taken through a read-only connection, which never touches the file in use.
/// The photographs are thousands of files that never change once written, so
/// they are mirrored, and only the ones missing at the far end are sent.
enum BackupService {
    enum Failure: LocalizedError {
        case noICloudDrive
        case snapshotFailed(String)

        var errorDescription: String? {
            switch self {
            case .noICloudDrive:
                "iCloud Drive est introuvable sur ce Mac. Activez-le dans "
                    + "Réglages Système, rubrique iCloud."
            case let .snapshotFailed(detail):
                "La copie de la base a échoué : \(detail)"
            }
        }
    }

    /// Where the snapshots go. Nil when iCloud Drive is not set up, which is
    /// the one failure worth naming: everything else is a disk error.
    static var destination: URL? {
        let icloud = URL.homeDirectory
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs")
        // Not `path()`, which percent-encodes: "Mobile Documents" came back
        // as "Mobile%20Documents" and the folder was reported missing. The
        // same trap would have hidden "Application Support" from SQLite.
        guard FileManager.default.fileExists(
            atPath: icloud.path(percentEncoded: false)
        ) else { return nil }
        return icloud.appending(path: "Cairn")
    }

    static let lastRunKey = "backupLastRun"

    static func lastRun(from defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastRunKey) as? Date
    }

    /// When the library was last written to, so an unchanged one is not
    /// copied a second time.
    static func storeModified(at store: URL) -> Date? {
        try? store.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    /// Runs a backup, or decides there is nothing to do.
    ///
    /// Returns the date of the backup it made, or nil when it judged one
    /// unnecessary. Never throws for "not yet": only a real failure throws.
    @discardableResult
    static func run(
        store: URL, photos: URL, force: Bool,
        now: Date = Date(), defaults: UserDefaults = .standard
    ) throws -> Date? {
        // Never the demo library. It is generated on the spot and identical
        // for everyone, so backing it up would put a synthetic year of
        // outings in the user's iCloud Drive and nothing of value in it.
        guard !DemoData.isEnabled else { return nil }
        guard force || BackupPlan.shouldBackUp(
            lastBackup: lastRun(from: defaults),
            storeModified: storeModified(at: store),
            now: now
        ) else { return nil }

        guard let destination else { throw Failure.noICloudDrive }
        try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true
        )

        try writeSnapshot(of: store, into: destination, at: now)
        try mirrorPhotos(from: photos, into: destination.appending(path: "Photos"))
        rotate(in: destination)
        try? restoreInstructions.write(
            to: destination.appending(path: "COMMENT-RESTAURER.txt"),
            atomically: true, encoding: .utf8
        )

        defaults.set(now, forKey: lastRunKey)
        return now
    }

    // MARK: - The journal

    private static func writeSnapshot(
        of store: URL, into destination: URL, at date: Date
    ) throws {
        let name = BackupPlan.snapshotName(for: date)
        // Built beside the destination and moved into place at the end: a
        // half-written snapshot in the folder is worse than no snapshot, and
        // iCloud would start uploading it while it grows.
        let staging = FileManager.default.temporaryDirectory
            .appending(path: "cairn-backup-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(
                at: staging.appendingPathExtension("gz")
            )
        }

        // Read-only, so the connection the app is using is never disturbed.
        // Measured on a 126 MB library: four tenths of a second.
        let source = try SQLiteDatabase(
            path: store.path(percentEncoded: false), readOnly: true
        )
        let escaped = staging.path(percentEncoded: false)
            .replacingOccurrences(of: "'", with: "''")
        do {
            try source.execute("VACUUM INTO '\(escaped)'")
        } catch {
            throw Failure.snapshotFailed(error.localizedDescription)
        }

        // Compressed before it travels: 112 MB of SQLite becomes 39, and
        // three of those are what live in iCloud.
        try gzip(staging)
        try replaceItem(
            at: destination.appending(path: name + ".gz"),
            with: staging.appendingPathExtension("gz")
        )
    }

    private static func gzip(_ file: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        task.arguments = ["-6", file.path(percentEncoded: false)]
        // Nobody reads gzip's chatter, and an undrained pipe would block it.
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw Failure.snapshotFailed("gzip a répondu \(task.terminationStatus)")
        }
    }

    // MARK: - The photographs

    /// Copies across only what is missing.
    ///
    /// SwiftData writes each large value once, under a name of its own, and
    /// never edits it. So a file already at the far end is the same file, and
    /// re-sending three hundred megabytes of unchanged photographs every day
    /// would be the whole cost of this feature for none of its benefit.
    private static func mirrorPhotos(from source: URL, into destination: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path(percentEncoded: false))
        else { return }
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let walker = manager.enumerator(
            at: source, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return }
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?
                .isRegularFile == true else { continue }
            let target = destination.appending(path: file.lastPathComponent)
            guard !manager.fileExists(atPath: target.path(percentEncoded: false))
            else { continue }
            try? manager.copyItem(at: file, to: target)
        }
    }

    // MARK: - Housekeeping

    private static func rotate(in destination: URL) {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(
            atPath: destination.path(percentEncoded: false)
        ))?.filter { $0.hasPrefix("journal-") } ?? []
        for name in BackupPlan.snapshotsToDelete(names) {
            try? manager.removeItem(at: destination.appending(path: name))
        }
    }

    private static func replaceItem(at target: URL, with source: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: target.path(percentEncoded: false)) {
            try manager.removeItem(at: target)
        }
        try manager.moveItem(at: source, to: target)
    }

    /// Left in the folder, because a backup nobody knows how to restore is
    /// not a backup. Written in French, like everything the user reads.
    private static let restoreInstructions = """
        Sauvegarde de Cairn
        ===================

        journal-AAAA-MM-JJ-HHMM.sqlite.gz
            La base : activités, journal alimentaire, pesées. La plus récente
            est la dernière par ordre alphabétique. Les trois dernières sont
            conservées, les plus anciennes sont effacées automatiquement.

        Photos/
            Les photos des activités, une par fichier. Rien n'y est jamais
            modifié : seuls les nouveaux fichiers sont ajoutés.

        Restaurer
        ---------
        1. Quitter Cairn.
        2. Décompresser la sauvegarde :
               gunzip -k journal-AAAA-MM-JJ-HHMM.sqlite.gz
        3. La remettre en place, en écrasant la base existante :
               cp journal-AAAA-MM-JJ-HHMM.sqlite \\
                  ~/Library/Application\\ Support/Cairn/Cairn.store
           Supprimer aussi les fichiers Cairn.store-wal et Cairn.store-shm
           s'ils existent : ils décrivent l'ancienne base.
        4. Recopier le contenu de Photos/ dans
               ~/Library/Application\\ Support/Cairn/.Cairn_SUPPORT/
        5. Rouvrir Cairn.

        Le catalogue Open Food Facts n'est pas sauvegardé : il se retélécharge
        depuis les réglages.
        """
}
