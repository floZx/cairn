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
    static let defaultsKey = "detailPaneWidth.v1"

    /// Below this, the pane is not narrow — it is shut.
    ///
    /// `RootView` collapses the detail column to zero whenever there is nothing
    /// to show in it, and that collapse arrives as an ordinary resize. Saving it
    /// would mean reopening at zero forever, so anything under a plausible pane
    /// width is treated as the collapse it is rather than as a choice.
    static let minimumSaved: Double = 120

    static func save(_ width: Double, to defaults: UserDefaults = .standard) {
        guard width >= minimumSaved else { return }
        defaults.set(width, forKey: defaultsKey)
    }

    static func saved(from defaults: UserDefaults = .standard) -> Double? {
        let width = defaults.double(forKey: defaultsKey)
        return width >= minimumSaved ? width : nil
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
