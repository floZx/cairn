import SwiftUI



/// Decides which column absorbs a width change, and gives the geometry a name
/// that survives a rebuild.
///
/// Collapsing the sidebar frees its width, and AppKit hands that space to
/// whichever pane resists least — by default the detail pane, so the width the
/// user had dragged never survived a sidebar toggle. Holding priorities invert
/// that: "the view with the lowest priority will be the first to take on
/// additional width if the split view grows or shrinks".
///
/// SwiftUI exposes none of this, so a probe reaches into the AppKit hierarchy.
/// Measured on macOS 15: `NavigationSplitView` is a plain `NSSplitView` with
/// three panes whose delegate is a private `NavigationSplitViewController`, so
/// the priorities go on that controller's items. Nothing about that is
/// contractual, so finding nothing is treated as normal: no priorities are set
/// and the layout behaves exactly as it did before.
///
/// Three corrections were needed to get here, each found by measuring rather
/// than by reasoning:
///
/// - The work ran from `updateNSView`, deferred by one main-queue hop. SwiftUI
///   calls that exactly once, while the probe is still detached from any window,
///   so nothing was ever found. Hence `viewDidMoveToWindow`, plus retries: a
///   window is assigned before its columns exist.
/// - The search walked *up* from the probe. But `.background()` places the probe
///   behind the split view, making it a sibling — an ancestor walk could never
///   reach the columns. Hence a sweep of the window's descendants.
/// - The detail pane was given `.defaultHigh`. Since a holding priority *is* the
///   priority of a width constraint, that outranked the constraint AppKit
///   installs while dragging a divider, and the pane became unresizable. Only
///   the ordering matters, so the values stay a hair apart.
struct SplitViewHoldingPriorities: NSViewRepresentable {
    /// The list absorbs, the detail pane resists — by ten points, deliberately.
    /// `holdingPriority` defaults to `.defaultLow` (250) on every item, so the
    /// list keeps that default and only the detail pane is nudged above it. The
    /// sidebar is left alone: it is the pane being collapsed, never a candidate
    /// for the width it frees.
    static let listPriority = NSLayoutConstraint.Priority.defaultLow
    static let detailPriority = NSLayoutConstraint.Priority.defaultLow + 10

    /// Spread over half a second: a window is assigned before its split view is
    /// populated, and AppKit posts no "the columns are ready" notification. In
    /// practice the first attempt succeeds; the rest are insurance.
    private static let retryDelays: [Duration] = [
        .zero, .milliseconds(50), .milliseconds(250), .milliseconds(750),
    ]

    /// L'écran affiché, sous lequel les largeurs sont rangées.
    var ecran: PaneGeometry.Ecran = .activites

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let probe = ProbeView()
        let coordinator = context.coordinator
        coordinator.ecran = ecran
        probe.onAttachToWindow = { [weak probe] in
            Task { @MainActor in
                guard let probe else { return }
                await Self.applyWhenReady(from: probe, coordinator: coordinator)
            }
        }
        return probe
    }

    /// Holds the split view between updates, and which pane it is showing.
    @MainActor
    final class Coordinator {
        fileprivate weak var splitView: NSSplitView?
        fileprivate var ecran: PaneGeometry.Ecran = .activites

        /// The width the column owes the pane now showing, until it can take
        /// it.
        ///
        /// A hand-over cannot simply set the width: switching section shuts
        /// the column to nothing for a moment — measured at two full seconds
        /// — and a pane of zero width is one `RootView` has deliberately
        /// closed, which nothing may reopen. So the width waits here and is
        /// laid on at the first resize that finds the column open again.
        private var pendingWidth: Double?

        /// True while the column is rearranging itself after a hand-over.
        ///
        /// Everything the switch provokes — the column's minimum changing with
        /// the pane, AppKit pushing the divider to obey it, the position we
        /// then set ourselves — arrives as an ordinary resize, and an observer
        /// cannot tell any of it from a drag. Recorded as one, the floor the
        /// column had just been clamped to overwrote the very width that was
        /// about to be restored, and the pane came back at its minimum for
        /// good.
        private var isSettling = false

        /// How wide the column was at the last resize, so the one that reopens
        /// it can be told from the rest.
        private var lastWidth: Double = 0

        /// Hands the column from one pane to the other: what the user left
        /// behind is filed under the pane they dragged it for, and the pane
        /// arriving comes back at its own width.
        fileprivate func handOver(to nouvel: PaneGeometry.Ecran) {
            guard nouvel != ecran, let splitView else {
                ecran = nouvel
                return
            }
            saveCurrentWidth(of: splitView)
            ecran = nouvel
            isSettling = true
            // La latérale se pose tout de suite : elle ne se ferme pas quand on
            // change de section — seule celle de droite le fait — donc rien ne
            // justifie de la faire attendre.
            SplitViewHoldingPriorities.setSidebarWidth(
                PaneGeometry.saved(nouvel, .laterale), of: splitView
            )
            // Read now rather than when it is finally applied: the churn this
            // switch is about to cause would have had time to answer with
            // something else.
            pendingWidth = PaneGeometry.saved(nouvel, .detail)
            // Attempted one hop later, because the column's minimum changes
            // with the pane in this very update and a position set before
            // AppKit has taken the new constraint gets clamped to the old
            // floor. If the column is shut by then, the width simply waits.
            Task { @MainActor [weak self, weak splitView] in
                if let splitView { self?.applyPendingWidth(to: splitView) }
                try? await Task.sleep(for: .milliseconds(50))
                self?.isSettling = false
            }
        }

        /// Lays the owed width on the column, if it is open to take it.
        fileprivate func applyPendingWidth(to splitView: NSSplitView) {
            guard let width = pendingWidth,
                  splitView.arrangedSubviews.count >= 3,
                  splitView.arrangedSubviews[2].frame.width > 0
            else { return }
            pendingWidth = nil
            SplitViewHoldingPriorities.setDetailWidth(width, of: splitView)
        }

        /// Takes a resize into account: the column may have just reopened, and
        /// a pane whose column reopens is owed the width it was left at.
        ///
        /// Hand-overs are not the only moment a width has to be asked for
        /// again. The journal's column shuts at every deselection and reopens
        /// at the next note, all without changing pane, so `handOver` never
        /// runs and the width posted at the section switch was spent on the
        /// first note opened. Everything after that came back at whatever
        /// width AppKit chose.
        fileprivate func columnDidResize(_ splitView: NSSplitView) {
            guard splitView.arrangedSubviews.count >= 3 else { return }
            let width = splitView.arrangedSubviews[2].frame.width
            if PaneGeometry.shouldRestore(
                previousWidth: lastWidth, newWidth: width
            ), let saved = PaneGeometry.saved(ecran, .detail) {
                pendingWidth = saved
            }
            // Before applying, not after: setting the position posts another
            // resize, and the width read back then is the restored one — which
            // must not read as a second reopening.
            lastWidth = width
            applyPendingWidth(to: splitView)
        }

        /// Called at startup, once the split view has been found.
        fileprivate func restoreOnLaunch(_ splitView: NSSplitView) {
            if splitView.arrangedSubviews.count >= 3 {
                lastWidth = splitView.arrangedSubviews[2].frame.width
            }
            pendingWidth = PaneGeometry.saved(ecran, .detail)
            applyPendingWidth(to: splitView)
            SplitViewHoldingPriorities.setSidebarWidth(
                PaneGeometry.saved(ecran, .laterale), of: splitView
            )
        }

        /// Range les deux largeurs libres de l'écran courant.
        ///
        /// Le milieu n'en est pas : dans une fenêtre de largeur fixe, il est ce
        /// qui reste une fois les deux autres posées.
        fileprivate func saveCurrentWidth(of splitView: NSSplitView) {
            guard !isSettling, splitView.arrangedSubviews.count >= 3 else { return }
            PaneGeometry.save(splitView.arrangedSubviews[2].frame.width, ecran, .detail)
            PaneGeometry.save(splitView.arrangedSubviews[0].frame.width, ecran, .laterale)
        }
    }

    func updateNSView(_ view: NSView, context: Context) {
        // The probe's own work hangs off joining a window, which happens after
        // SwiftUI's first update and never again. What does change here is
        // which pane the column holds.
        context.coordinator.handOver(to: ecran)
    }

    @MainActor
    private static func applyWhenReady(
        from probe: NSView, coordinator: Coordinator
    ) async {
        for delay in Self.retryDelays {
            if delay != .zero { try? await Task.sleep(for: delay) }

            guard let root = probe.window?.contentView else { continue }
            for splitView in root.descendantSplitViews() where apply(to: splitView) {
                coordinator.splitView = splitView
                coordinator.restoreOnLaunch(splitView)
                observeDetailWidth(of: splitView, coordinator: coordinator)
                return
            }
        }
        // Nothing found after every retry: the layout simply behaves as it did
        // before. Silent on purpose — this is polish, not a broken feature.
    }

    /// Sets the priorities on a split view's items.
    ///
    /// Returns false when there is no controller behind it or it has fewer than
    /// three columns — the state during setup rather than a failure, so the
    /// caller retries.
    @discardableResult
    @MainActor
    static func apply(to splitView: NSSplitView) -> Bool {
        guard let controller = splitView.delegate as? NSSplitViewController else {
            return false
        }
        let items = controller.splitViewItems
        guard items.count >= 3 else { return false }

        set(listPriority, on: items[1])
        set(detailPriority, on: items[2])

        // Keeps the window's width fixed and resizes the panes instead;
        // otherwise AppKit answers a sidebar toggle by resizing the window.
        items[0].collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        return true
    }


    /// Puts the last divider where it leaves the detail pane exactly `width`.
    @MainActor
    static func setDetailWidth(_ width: Double, of splitView: NSSplitView) {
        guard splitView.arrangedSubviews.count >= 3,
              // Nothing to reopen when the pane is deliberately shut: `RootView`
              // collapses it to zero whenever there is no selection.
              splitView.arrangedSubviews[2].frame.width > 0
        else { return }

        let position = PaneGeometry.dividerPosition(
            detailWidth: width,
            totalWidth: splitView.bounds.width,
            dividerThickness: splitView.dividerThickness,
            sidebarWidth: splitView.arrangedSubviews[0].frame.width,
            minimumMiddle: 480
        )
        guard let position else { return }
        splitView.setPosition(position, ofDividerAt: 1)
    }

    /// Pose le premier diviseur pour que la barre latérale fasse `width`.
    ///
    /// Ne fait rien quand la latérale est repliée : c'est un geste délibéré,
    /// et la rouvrir parce qu'on change de section serait la reprendre à
    /// quelqu'un qui vient de la ranger.
    @MainActor
    static func setSidebarWidth(_ width: Double?, of splitView: NSSplitView) {
        guard let width, splitView.arrangedSubviews.count >= 3,
              splitView.arrangedSubviews[0].frame.width > 0
        else { return }

        let position = PaneGeometry.sidebarPosition(
            sidebarWidth: width,
            totalWidth: splitView.bounds.width,
            dividerThickness: splitView.dividerThickness,
            detailWidth: splitView.arrangedSubviews[2].frame.width,
            minimumMiddle: 480
        )
        guard let position else { return }
        splitView.setPosition(position, ofDividerAt: 0)
    }

    /// Records the width whenever the user drags the divider.
    ///
    /// The split view is captured weakly and read on the main actor rather than
    /// taken out of the notification: `Notification` is not `Sendable`, and the
    /// observer is never removed — it lives exactly as long as the window does.
    @MainActor
    private static func observeDetailWidth(
        of splitView: NSSplitView, coordinator: Coordinator
    ) {
        NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: splitView, queue: .main
        ) { [weak splitView, weak coordinator] note in
            // Only a drag is a choice, and AppKit says which is which.
            //
            // Measured on macOS 15: a divider pulled by hand posts
            // notifications carrying `NSSplitViewUserResizeKey`, while the
            // resize AppKit performs to honour a column's minimum — the one
            // that arrived six hundred milliseconds after every section
            // switch and wrote the floor over the width being restored —
            // carries the divider index and nothing else. A window of time
            // could not tell them apart; this can.
            //
            // The key is not documented, so its absence is read as "not a
            // drag": widths would stop being remembered rather than be
            // remembered wrong.
            let isDrag = note.userInfo?["NSSplitViewUserResizeKey"] != nil
            MainActor.assumeIsolated {
                guard let splitView, splitView.arrangedSubviews.count >= 3 else {
                    return
                }
                // Under whichever pane is showing: the same drag means two
                // different things depending on what the column holds.
                if isDrag { coordinator?.saveCurrentWidth(of: splitView) }
                // Whatever the cause: this may be the resize that reopens the
                // column, which owes its pane the width it was left at —
                // whether it was posted at a hand-over or is only asked for
                // now, the column having reopened without changing pane.
                coordinator?.columnDidResize(splitView)
            }
        }
    }

    private static func set(
        _ priority: NSLayoutConstraint.Priority, on item: NSSplitViewItem
    ) {
        guard item.holdingPriority != priority else { return }
        item.holdingPriority = priority
    }
}

/// A zero-size, non-drawing view that reports when it joins a window.
private final class ProbeView: NSView {
    var onAttachToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        onAttachToWindow?()
    }
}

extension NSView {
    /// Every split view in this view's subtree, outermost first.
    func descendantSplitViews() -> [NSSplitView] {
        var found: [NSSplitView] = []
        if let splitView = self as? NSSplitView { found.append(splitView) }
        for subview in subviews {
            found.append(contentsOf: subview.descendantSplitViews())
        }
        return found
    }
}
