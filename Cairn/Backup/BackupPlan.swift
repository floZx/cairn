import Foundation

/// When a backup is worth making, and which old ones to let go.
///
/// Pure arithmetic, apart from the copying itself: deciding *whether* to run
/// is the part that has to be right every single launch, and it is the part
/// that can be tested without touching three hundred megabytes.
enum BackupPlan {
    /// A day between automatic backups.
    ///
    /// Not every launch: the store is over a hundred megabytes and the app is
    /// opened several times a day, which would spend the morning uploading
    /// copies of a library that has not moved.
    static let interval: TimeInterval = 24 * 60 * 60

    /// How many dated snapshots are kept.
    ///
    /// Three rather than one, because the danger a backup guards against is
    /// not only a dead Mac: it is also noticing a week late that something was
    /// deleted by mistake. One snapshot would have been overwritten by then.
    static let keep = 3

    /// Whether an automatic backup should run now.
    ///
    /// - Parameters:
    ///   - lastBackup: when one last succeeded, nil if never.
    ///   - storeModified: when the library was last written to.
    static func shouldBackUp(
        lastBackup: Date?, storeModified: Date?, now: Date,
        interval: TimeInterval = interval
    ) -> Bool {
        guard let lastBackup else { return true }
        // Nothing written since the last one: copying it again would spend the
        // bandwidth to produce a duplicate.
        if let storeModified, storeModified <= lastBackup { return false }
        return now.timeIntervalSince(lastBackup) >= interval
    }

    /// The snapshots to delete, oldest first, so that `keep` remain.
    ///
    /// Sorted by name rather than by file date: the names carry the date they
    /// were taken, and a file date is whatever the last copy or sync decided.
    static func snapshotsToDelete(
        _ names: [String], keep: Int = keep
    ) -> [String] {
        let ordered = names.sorted()
        guard ordered.count > keep else { return [] }
        return Array(ordered.dropLast(keep))
    }

    /// The name of the snapshot taken at `date`, sortable as a string.
    static func snapshotName(for date: Date) -> String {
        "journal-\(stamp.string(from: date)).sqlite"
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed locale and a fixed pattern: this string is sorted and parsed,
        // never read aloud, so it must not follow the user's region.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}
