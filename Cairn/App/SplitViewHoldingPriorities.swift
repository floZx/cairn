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

    func makeNSView(context: Context) -> NSView {
        let probe = ProbeView()
        probe.onAttachToWindow = { [weak probe] in
            Task { @MainActor in
                guard let probe else { return }
                await Self.applyWhenReady(from: probe)
            }
        }
        return probe
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Nothing to do: the work hangs off the probe joining a window, which
        // happens after SwiftUI's first update and never again.
    }

    @MainActor
    private static func applyWhenReady(from probe: NSView) async {
        for delay in Self.retryDelays {
            if delay != .zero { try? await Task.sleep(for: delay) }

            guard let root = probe.window?.contentView else { continue }
            for splitView in root.descendantSplitViews() where apply(to: splitView) {
                restoreDetailWidth(of: splitView)
                observeDetailWidth(of: splitView)
                clipDividersUnderToolbar(of: splitView)
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

    /// Puts the last divider back where it leaves the detail pane its width.
    ///
    /// Runs after AppKit has restored its own geometry, which is the whole
    /// point: AppKit restored from a key that a rebuild may have orphaned, and
    /// this corrects it.
    @MainActor
    static func restoreDetailWidth(of splitView: NSSplitView) {
        guard let width = DetailPaneWidth.saved(),
              splitView.arrangedSubviews.count >= 3,
              // Nothing to reopen when the pane is deliberately shut: `RootView`
              // collapses it to zero whenever there is no selection.
              splitView.arrangedSubviews[2].frame.width > 0
        else { return }

        let position = DetailPaneWidth.dividerPosition(
            detailWidth: width,
            totalWidth: splitView.bounds.width,
            dividerThickness: splitView.dividerThickness,
            sidebarWidth: splitView.arrangedSubviews[0].frame.width,
            minimumMiddle: 480
        )
        guard let position else { return }
        splitView.setPosition(position, ofDividerAt: 1)
    }

    /// Records the width whenever the user drags the divider.
    ///
    /// The split view is captured weakly and read on the main actor rather than
    /// taken out of the notification: `Notification` is not `Sendable`, and the
    /// observer is never removed — it lives exactly as long as the window does.
    @MainActor
    private static func observeDetailWidth(of splitView: NSSplitView) {
        NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: splitView, queue: .main
        ) { [weak splitView] _ in
            MainActor.assumeIsolated {
                guard let splitView, splitView.arrangedSubviews.count >= 3 else {
                    return
                }
                DetailPaneWidth.save(splitView.arrangedSubviews[2].frame.width)
                // The dividers were just resized along with everything else,
                // so the mask has to follow or it clips the wrong slice.
                clipDividersUnderToolbar(of: splitView)
            }
        }
    }

    /// Stops the column dividers at the bottom of the toolbar.
    ///
    /// The dividers run the full height of the window. That never showed while
    /// the toolbar painted its own fill over them — and hiding that fill is
    /// exactly what let each column's material rise into the bar and give it
    /// the right tone. The line came with it: one hard rule straight up
    /// through the middle of the toolbar, cutting it in two.
    ///
    /// Masked rather than hidden: below the bar the divider is doing its job,
    /// and the two content columns are close enough in tone that without it
    /// they would run together. Only the part inside the bar goes.
    @MainActor
    static func clipDividersUnderToolbar(of splitView: NSSplitView) {
        guard let contentView = splitView.window?.contentView else { return }
        // What the titlebar and toolbar take off the top. Zero in a window
        // without one, in which case there is nothing to clip.
        let barHeight = contentView.bounds.height
            - contentView.window!.contentLayoutRect.height
        guard barHeight > 0 else { return }

        // By elimination rather than by class: the dividers are the subviews
        // that are not arranged columns, and the class that draws them is
        // private. Nothing here breaks if AppKit renames it.
        let columns = Set(splitView.arrangedSubviews.map(ObjectIdentifier.init))
        for divider in splitView.subviews
        where !columns.contains(ObjectIdentifier(divider)) {
            divider.wantsLayer = true
            let mask = divider.layer?.mask ?? CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            // Layer coordinates follow the view, which is not flipped: y grows
            // upward, so the bar is the top slice and what we keep starts at 0.
            mask.frame = CGRect(
                x: 0, y: 0,
                width: divider.bounds.width,
                height: max(0, divider.bounds.height - barHeight)
            )
            divider.layer?.mask = mask
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
