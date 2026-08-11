import AppKit

/// Remembers how wide the detail pane was, under a key that outlives a rebuild.
///
/// AppKit already autosaves split-view geometry, but under a name it derives
/// from the *mangled Swift type* of the root view with its whole modifier chain
/// and a window ordinal:
///
///     NSSplitView Subview Frames SwiftUI.ModifiedContent<SwiftUI.Modified…
///     Content<Cairn.RootView, …_EnvironmentKeyWritingModifier<…>>,
///     SwiftUI._TaskModifier2>-1-AppWindow-1, SidebarNavigationSplitView
///
/// Every part of that changes for reasons that have nothing to do with window
/// geometry: adding a single `.task` to the root view mints a new key, and so
/// did renaming the module from StravaLocal to Cairn. Three generations of
/// orphaned keys were sitting in the preferences, each holding widths nothing
/// would ever read again — which is why the detail pane kept reopening at its
/// default size after a build.
///
/// Renaming AppKit's own autosave is not enough: restoration happens when the
/// split view joins the window, before any probe of ours can run, so a renamed
/// key can be written but never read back. Hence keeping the one width that
/// matters here, and restoring it ourselves.
enum DetailPaneWidth {
    /// Which pane the column is holding, and therefore whose width this is.
    ///
    /// They share a column but not a purpose: the activity pane carries a
    /// map, a strip of photographs and four rows of figures, the food
    /// journal's panel a small calendar and a day's totals, the journal's an
    /// editor. One width for all of them meant dragging the food journal's
    /// panel narrow dragged the activity pane with it — a divider knows
    /// nothing of what is behind it.
    enum Kind: String, CaseIterable, Sendable {
        case activity
        case nutrition
        case journal

        var defaultsKey: String {
            switch self {
            // Left as it was, so a width already dragged survives the split.
            case .activity: "detailPaneWidth.v1"
            case .nutrition: "nutritionPaneWidth.v1"
            case .journal: "journalPaneWidth.v1"
            }
        }

        /// Below this, the pane is not narrow — it is shut.
        ///
        /// `RootView` collapses the detail column to zero whenever it has
        /// nothing to show, and that collapse arrives as an ordinary resize.
        /// Saving it would mean reopening at zero forever, so anything under
        /// a plausible width for *this* pane is read as the collapse it is.
        /// The journal's panel is allowed to be far narrower, so its floor
        /// has to be lower or its honest widths would be discarded as shuts.
        var minimumSaved: Double {
            switch self {
            case .activity: 120
            case .nutrition: 80
            // An editor filling the pane: narrower than the activity pane's
            // map and figures, wider than the food journal's small calendar.
            case .journal: 120
            }
        }
    }

    static let defaultsKey = Kind.activity.defaultsKey

    static func save(
        _ width: Double, for kind: Kind = .activity,
        to defaults: UserDefaults = .standard
    ) {
        guard width >= kind.minimumSaved else { return }
        defaults.set(width, forKey: kind.defaultsKey)
    }

    static func saved(
        for kind: Kind = .activity, from defaults: UserDefaults = .standard
    ) -> Double? {
        let width = defaults.double(forKey: kind.defaultsKey)
        return width >= kind.minimumSaved ? width : nil
    }

    /// Where the last divider goes so the detail pane gets `width`, or nil when
    /// it cannot without squeezing the middle pane past `minimumMiddle`.
    ///
    /// Returning nil rather than clamping: a window narrower than the widths it
    /// was left at is a case where AppKit's own layout is the better answer, and
    /// forcing a position would push the list to nothing.
    static func dividerPosition(
        detailWidth: Double, totalWidth: Double,
        dividerThickness: Double, sidebarWidth: Double, minimumMiddle: Double
    ) -> Double? {
        let position = totalWidth - detailWidth - dividerThickness
        guard position - sidebarWidth - dividerThickness >= minimumMiddle else {
            return nil
        }
        return position
    }
}
