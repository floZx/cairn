import Foundation
import SwiftData

/// A photo taken on an activity, kept as bytes rather than as a link.
///
/// Strava's photo URLs are signed and expire, so storing the address would leave
/// a journal full of dead links within months — the exact failure this whole app
/// exists to avoid. The image itself is downloaded and held in external storage,
/// beside the tracks.
@Model
final class ActivityPhoto {
    /// Strava's `unique_id`, which is what makes a re-sync recognise a photo it
    /// already has instead of downloading it a second time.
    var uniqueID: String = ""
    /// Where it came from, kept for reference only. Never used to display the
    /// photo: by the time anyone looks, it has usually expired.
    var sourceURL: String?
    var caption: String?
    var takenAt: Date?
    /// Position within the activity, so the order survives a re-sync that
    /// returns the photos in a different one.
    var sortIndex: Int = 0

    @Attribute(.externalStorage) var data: Data?

    var activity: Activity?
    /// The owning activity's `uuid`, kept alongside the relationship.
    ///
    /// Not redundancy for its own sake: the sync writes photos from its own
    /// `ModelContext`, and a to-many relationship on an activity already
    /// materialised in the interface's context does not come back refreshed —
    /// the photos landed on disk and the pane stayed empty until relaunch. A
    /// `@Query` keyed on this field re-runs on any store change, which the
    /// relationship does not.
    var activityUUID: String = ""

    init(uniqueID: String) {
        self.uniqueID = uniqueID
    }

    /// Picks the largest image among the sizes Strava offers.
    ///
    /// `urls` is a map from a pixel size to an address — `["100": …, "600": …]`
    /// on the documented endpoint, larger keys on the undocumented one. The keys
    /// are strings, so they are compared as numbers: sorting them as text would
    /// put "100" above "600".
    static func largestURL(in urls: [String: String]?) -> String? {
        guard let urls, !urls.isEmpty else { return nil }
        let numbered = urls.compactMap { key, value in
            Int(key).map { (size: $0, url: value) }
        }
        // No numeric key at all — Strava does use one non-numeric size name for
        // the original — so any address is better than none.
        guard !numbered.isEmpty else { return urls.values.sorted().last }
        return numbered.max { $0.size < $1.size }?.url
    }
}
