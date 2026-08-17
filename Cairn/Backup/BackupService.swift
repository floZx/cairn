import Foundation
import SwiftData

/// Copies the library somewhere it survives this Mac.
///
/// A backup, deliberately, and not a sync: a synchronised store propagates a
/// deletion within seconds, which is no protection at all against the mistake
/// a backup is most often needed for. Dated snapshots, a few of them kept.
///
/// Three things are copied, and they are copied differently because they
/// behave differently. The store is one SQLite file the app has open at all
/// times, so it is extracted with `VACUUM INTO` — a consistent point-in-time
/// copy taken through a read-only connection, which never touches the file in
/// use. The photographs are thousands of files that never change once
/// written, so they are mirrored, and only the ones missing at the far end
/// are sent. The journal's notes live in that same SQLite file, but a row in
/// a `.sqlite.gz` nobody opens except to restore is not what "your notes come
/// back out in Markdown" was supposed to mean — so they also come out a
/// second time, in the open, through a read-only connection of their own.
enum BackupService {
    enum Failure: LocalizedError {
        case noICloudDrive
        case snapshotFailed(String)
        /// The Markdown half alone failed; everything else is in place. Its
        /// own case, and its own sentence, because the two do not mean the
        /// same thing to a reader: one says the backup did not happen, this
        /// one says it did and that the readable copy beside it did not.
        case journalMarkdownFailed(String)

        var errorDescription: String? {
            switch self {
            case .noICloudDrive:
                "iCloud Drive est introuvable sur ce Mac. Activez-le dans "
                    + "Réglages Système, rubrique iCloud."
            case let .snapshotFailed(detail):
                "La copie de la base a échoué : \(detail)"
            case let .journalMarkdownFailed(detail):
                "La sauvegarde est en place, mais l'export Markdown du "
                    + "journal a échoué : \(detail)"
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

        // Held rather than thrown, and rethrown at the very end: the Markdown
        // half is a bonus — the same notes are already inside the `.sqlite.gz`
        // written just above — and it opens a second `ModelContainer`, so it
        // is also the one step here that can fail for a reason having nothing
        // to do with the disk. Throwing it from where it stands used to take
        // the photographs, the rotation *and* `lastRunKey` down with it: the
        // snapshots then piled up, one a day, never pruned, because `rotate`
        // is the only thing that prunes them and it never ran again.
        var markdownFailure: Error?
        do {
            try writeJournalMarkdown(
                journalContext(at: store), into: destination,
                stamp: BackupPlan.timestamp(for: now)
            )
        } catch {
            markdownFailure = error
        }

        try mirrorPhotos(from: photos, into: destination.appending(path: "Photos"))
        rotate(in: destination)
        try? restoreInstructions.write(
            to: destination.appending(path: "COMMENT-RESTAURER.txt"),
            atomically: true, encoding: .utf8
        )

        defaults.set(now, forKey: lastRunKey)
        // Said, not swallowed: a Markdown export that has been failing for a
        // month is worth knowing about, and the marker above is already set,
        // so tomorrow's run happens on schedule whether or not this throws.
        if let markdownFailure {
            throw Failure.journalMarkdownFailed(markdownFailure.localizedDescription)
        }
        return now
    }

    // MARK: - The store

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

    // MARK: - The journal's notes

    /// Every folder this writes starts with this, `rotate` filters on it, and
    /// nothing else in the destination ever gets this prefix — so the two
    /// stay each other's exact inverse.
    private static let markdownPrefix = "journal-markdown-"

    /// Writes the journal out as `journal-markdown-<stamp>/`, beside the
    /// sqlite snapshot named from that same `stamp`
    /// (`BackupPlan.timestamp(for:)`) — so a reader can tell at a glance
    /// which backup the two came from.
    ///
    /// Takes the stamp rather than a `Date`, and a `ModelContext` rather than
    /// a store URL: what actually writes the files is
    /// `JournalMarkdownExport.write`, already proven byte-for-byte faithful
    /// by its own round-trip test. This is only the naming and the wiring.
    static func writeJournalMarkdown(
        _ context: ModelContext, into destination: URL, stamp: String
    ) throws {
        try JournalMarkdownExport.write(
            context, to: destination.appending(path: markdownPrefix + stamp)
        )
    }

    /// A context on the same store the sqlite snapshot above just read,
    /// opened `allowsSave: false` for the same reason `writeSnapshot` opens
    /// its own connection read-only: the app's live connection is never
    /// disturbed, and this one can never turn into a second writer by
    /// accident. Apple's own pattern for a widget reading its host app's
    /// store — this just reads back in-process instead of across an App
    /// Group.
    private static func journalContext(at store: URL) throws -> ModelContext {
        let configuration = ModelConfiguration(url: store, allowsSave: false)
        let container = try ModelContainer(
            for: AppModelContainer.schema, configurations: configuration
        )
        return ModelContext(container)
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

    /// Deletes what the retention policy no longer keeps, each family counted
    /// on its own.
    ///
    /// Not `private`: this is the one function here that *deletes backups*,
    /// and its filter — `journal-` minus `markdownPrefix` on one side, the
    /// prefix itself on the other — is the whole of what separates the two
    /// families. `Tests/JournalBackupTests.swift` used to reproduce that
    /// filter in the test instead of calling this, and so stayed green over
    /// any rotation, right or wrong.
    static func rotate(in destination: URL) {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(
            atPath: destination.path(percentEncoded: false)
        )) ?? []
        // Each family rotated on its own, same `keep` policy applied twice:
        // one alphabetical list mixing both would let a run of Markdown
        // folders crowd every sqlite snapshot out of the last three kept, or
        // the other way around, well before either was actually three deep.
        let sqliteSnapshots = names.filter {
            $0.hasPrefix("journal-") && !$0.hasPrefix(markdownPrefix)
        }
        let markdownExports = names.filter { $0.hasPrefix(markdownPrefix) }
        let stale = BackupPlan.snapshotsToDelete(sqliteSnapshots)
            + BackupPlan.snapshotsToDelete(markdownExports)
        for name in stale {
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
            La base : activités, journal alimentaire, pesées, notes du
            journal. La plus récente est la dernière par ordre alphabétique.
            Les trois dernières sont conservées, les plus anciennes sont
            effacées automatiquement.

        journal-markdown-AAAA-MM-JJ-HHMM/
            Les mêmes notes du journal, en clair : un fichier Markdown par
            jour, ouvrable dans Obsidian ou n'importe quel éditeur de texte.
            Même politique que la base : les trois derniers dossiers sont
            conservés, les plus anciens effacés automatiquement.

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
