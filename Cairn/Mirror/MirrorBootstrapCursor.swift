import Foundation
import SwiftData

/// Where a bootstrap has gotten to, per table: the `uuid` of the last row
/// successfully upserted. Lives in `UserDefaults`, not the SwiftData store,
/// for the same reason `SyncState` lives in the store while describing the
/// relationship with Strava rather than the user's data: this describes the
/// Mac's relationship with Supabase, and a JSON export or a restore of the
/// library must never carry it along.
///
/// Also holds `lastPushAt` — not a per-table cursor, but the same kind of
/// fact (the Mac's relationship with Supabase, not the user's data) and the
/// same storage, so a second `UserDefaults`-backed type was not worth
/// opening for one more key.
///
/// Injected rather than hard-coded to `.standard`, so tests can point it at a
/// throwaway suite instead of the suite the test *runner* itself uses —
/// `Tests/JournalStoreTests.swift` follows the same rule for the same reason.
/// No default value on `MirrorEngine.init` falls back to `.standard`
/// either — see the note there.
struct MirrorBootstrapCursor: Sendable {
    // `UserDefaults` is thread-safe by Apple's own documentation but not
    // marked `Sendable` in this SDK — the same gap `PaneGeometry` and
    // `BackupService` sidestep by taking it as a plain default-argument
    // rather than storing it across an isolation boundary. Storing it here
    // is unavoidable — the cursor has to outlive a single call — so this is
    // the one place in the mirror that asserts, rather than lets the
    // compiler prove, that the type is safe to share.
    nonisolated(unsafe) private let defaults: UserDefaults

    static let lastPushAtKey = "mirror.lastPushAt"
    static let cursorKeyPrefix = "mirror.bootstrapCursor."
    static let pullKeyPrefix = "mirror.pullCursor."

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func key(for table: String) -> String {
        "\(Self.cursorKeyPrefix)\(table)"
    }

    func lastUUID(for table: String) -> String? {
        defaults.string(forKey: key(for: table))
    }

    func setLastUUID(_ uuid: String, for table: String) {
        defaults.set(uuid, forKey: key(for: table))
    }

    /// Repart du début de la table au prochain envoi complet.
    func resetTable(_ table: String) {
        defaults.removeObject(forKey: key(for: table))
    }

    /// `nil` when the mirror has never finished a bootstrap or a push.
    /// `UserDefaults.double(forKey:)` answers `0` for a missing key —
    /// `Tests/PaneGeometryTests.swift` already documents the same trap —
    /// so `0` reads back as "never", not as the epoch.
    func lastPushAt() -> Date? {
        let epoch = defaults.double(forKey: Self.lastPushAtKey)
        return epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
    }

    func setLastPushAt(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastPushAtKey)
    }

    /// The server clock of the newest row this table has ever pulled — the
    /// `updated_at` a next call asks for everything at or after.
    ///
    /// A different key space from `lastUUID`, and deliberately: a bootstrap
    /// walks `uuid` ascending through what the Mac holds, a pull walks
    /// `updated_at` ascending through what Supabase holds. Two orders, two
    /// positions, and a single key would have one overwrite the other.
    ///
    /// `nil` when this table has never been pulled, on the same reasoning as
    /// `lastPushAt()`: `0` from a missing key reads as "never", not as 1970.
    func lastPulledAt(for table: String) -> Date? {
        let epoch = defaults.double(forKey: Self.pullKey(for: table))
        return epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
    }

    func setLastPulledAt(_ date: Date, for table: String) {
        defaults.set(date.timeIntervalSince1970, forKey: Self.pullKey(for: table))
    }

    static func pullKey(for table: String) -> String {
        "\(pullKeyPrefix)\(table)"
    }

    /// Erases every position this cursor has ever recorded: every table's
    /// `lastUUID` and `lastPushAt`. `AppEnvironment.forgetMirror()`'s
    /// counterpart, on the store side, to `SecretStore.clearMirror()` on the
    /// keychain side.
    ///
    /// Without this, forgetting a mirror and reconfiguring a *different*
    /// Supabase project would leave the old project's progress in place:
    /// `sendBatches` only ever fetches `uuid > cursor` (see its own doc
    /// comment), so a bootstrap against the new project would silently skip
    /// every row sorting before the stale cursor — rows the new project has
    /// never received, mistaken for ones already sent because a project it
    /// has nothing to do with once received them.
    ///
    /// Walks `UserDefaults`' own dictionary rather than a fixed table list
    /// (`MirrorEngine.bootstrapOrder`, say): a table that used to be part of
    /// that list and no longer is would otherwise leave an orphaned key
    /// behind forever, and nothing here should have to be kept in sync with
    /// that list to stay correct.
    func clear() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.cursorKeyPrefix) || key.hasPrefix(Self.pullKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: Self.lastPushAtKey)
    }
}
