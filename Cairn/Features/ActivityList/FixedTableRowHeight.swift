import SwiftUI

/// Turns off the table's automatic row heights, which cost seconds on a sort.
///
/// Sorting 840 activities froze the window for over ten seconds. A sample of the
/// main thread put 13.6 of 40 sampled seconds inside `-[NSTableRowData
/// endUpdates]`, split between `_doAutomaticRowHeightsForInsertedAndVisibleRows`
/// and tearing the resulting views down again. With automatic heights, AppKit
/// cannot know how tall a row is without building it, so a reorder makes it
/// instantiate an `NSHostingView` per cell for *every* row — 840, not the thirty
/// on screen — purely to measure something that never varies: every cell in this
/// table is a single line of text.
///
/// SwiftUI exposes no row-height API for `Table`, so a probe reaches into the
/// AppKit hierarchy, as `SplitViewHoldingPriorities` already does — see its
/// documentation for why such a probe has to wait for a window and then retry.
///
/// That one sweeps the whole window; this one climbs to the *nearest* ancestor
/// holding a table instead, because the sidebar is a `List` and therefore an
/// `NSTableView` too — a sweep from the window could just as well pin the
/// sidebar's row height and leave the activity table untouched.

/// Keeps whichever table the probe found, so the keyboard can scroll it.
///
/// Neither `Table` nor `List` publishes a way to bring a row into view, and
/// moving the selection with `j` without following it leaves the cursor
/// somewhere off screen — the list stops being navigable at exactly the moment
/// it is being navigated. Both are `NSTableView` underneath, which does know how.
@MainActor
final class TableScroller {
    /// The probe, not the table.
    ///
    /// Holding the table itself went stale the moment the presentation switched:
    /// the two tables coexist briefly, so whichever was captured could be the
    /// one on its way out. Resolving from the probe at each use always answers
    /// with the table that is actually on screen now.
    /// Held strongly, and deliberately.
    ///
    /// A weak reference here resolved to nil the moment the presentation
    /// switched — measured — leaving the scroller unable to find a table the
    /// probe's own search finds without trouble. The probe is a zero-sized view
    /// that draws nothing; keeping it alive costs nothing, and the closure it
    /// carries captures this object weakly so the two do not hold each other up.
    fileprivate var probe: NSView?

    fileprivate var tableView: NSTableView? {
        probe.flatMap { FixedTableRowHeight.tableView(near: $0) }
    }
    /// A focus request waiting for a table to exist.
    ///
    /// Switching presentation destroys the table the keyboard was in and builds
    /// another, so the request is made before there is anything to give focus
    /// to. It is held until the probe finds the replacement rather than fired
    /// into the void.
    private var wantsFocus = false

    /// Whether a focus request is still waiting. For the test.
    var hasPendingFocus: Bool { wantsFocus }

    /// Hands the scroller a probe directly, for the tests.
    func attachForTesting(_ probe: NSView) { attach(probe) }

    fileprivate func attach(_ probe: NSView) {
        self.probe = probe
        applyPendingFocus()
    }

    /// Puts the keyboard back in the list, now or as soon as there is one.
    ///
    /// Retried rather than attempted once: the replacement table is built over
    /// several runloop passes, and the first attempt lands while the old one is
    /// still there.
    func focusWhenAttached() {
        wantsFocus = true
        Task { @MainActor in
            for delay in Self.focusDelays {
                if delay != .zero { try? await Task.sleep(for: delay) }
                applyPendingFocus()
                if !wantsFocus { return }
            }
            // Given up on: the keyboard stays where the user left it, which is
            // the behaviour this was trying to improve on, not a broken state.
            wantsFocus = false
        }
    }

    private static let focusDelays: [Duration] = [
        .zero, .milliseconds(50), .milliseconds(150), .milliseconds(400),
    ]

    /// Called by the probe once a table exists under it.
    fileprivate func retryPendingFocus() { applyPendingFocus() }

    private func applyPendingFocus() {
        guard wantsFocus, let tableView, let window = tableView.window else { return }
        if window.makeFirstResponder(tableView) { wantsFocus = false }
    }

    func scroll(toRow index: Int) {
        guard let tableView, index >= 0, index < tableView.numberOfRows else { return }
        tableView.scrollRowToVisible(index)
    }
}

struct FixedTableRowHeight: NSViewRepresentable {
    /// Filled in once the table is found, if the caller wants to scroll it.
    var scroller: TableScroller?

    /// Spread over half a second: the probe joins a window before the table is
    /// populated, and AppKit posts no "the rows are ready" notification.
    private static let retryDelays: [Duration] = [
        .zero, .milliseconds(50), .milliseconds(250), .milliseconds(750),
    ]

    func makeNSView(context: Context) -> NSView {
        let probe = RowHeightProbeView()
        // The probe is what the scroller keeps: it outlives any one table.
        scroller?.attach(probe)
        probe.onAttachToWindow = { [weak probe, weak scroller] in
            Task { @MainActor in
                guard let probe else { return }
                await Self.applyWhenReady(from: probe, scroller: scroller)
                // A focus request may have been made while this table was still
                // being built; now that it exists, it can be honoured.
                scroller?.retryPendingFocus()
            }
        }
        return probe
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Nothing to do: the work hangs off the probe joining a window.
    }

    @MainActor
    private static func applyWhenReady(
        from probe: NSView, scroller: TableScroller?
    ) async {
        for delay in retryDelays {
            if delay != .zero { try? await Task.sleep(for: delay) }
            guard let table = tableView(near: probe) else { continue }
            if apply(to: table) { return }
        }
        // Nothing found after every retry: the table keeps automatic heights and
        // behaves exactly as before, slowly but correctly.
    }

    /// Pins the row height to whatever AppKit already measured for the first row.
    ///
    /// Returns false while the table is still empty — the state during setup
    /// rather than a failure, so the caller retries. Reading the measured height
    /// rather than hard-coding one keeps the table's appearance identical, and
    /// keeps it correct if the row content ever grows a second line by accident.
    @discardableResult
    @MainActor
    static func apply(to table: NSTableView) -> Bool {
        guard table.usesAutomaticRowHeights else { return true }
        guard table.numberOfRows > 0 else { return false }
        let measured = table.rect(ofRow: 0).height
        guard measured > 0 else { return false }

        table.usesAutomaticRowHeights = false
        table.rowHeight = measured
        return true
    }
}

/// A zero-size, non-drawing view that reports when it joins a window.
private final class RowHeightProbeView: NSView {
    var onAttachToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        onAttachToWindow?()
    }
}

extension FixedTableRowHeight {
    /// The first table view in the subtree of the closest ancestor that has one.
    ///
    /// `.background()` makes the probe a *sibling* of the view it decorates, so
    /// the table is never among the probe's own descendants; climbing one level
    /// at a time finds it without widening the search to the whole window, which
    /// is what keeps the sidebar's own `NSTableView` out of reach.
    @MainActor
    static func tableView(near probe: NSView) -> NSTableView? {
        var ancestor: NSView? = probe.superview
        while let current = ancestor {
            if let table = firstDescendantTableView(of: current) { return table }
            ancestor = current.superview
        }
        return nil
    }

    @MainActor
    private static func firstDescendantTableView(of view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let table = firstDescendantTableView(of: subview) { return table }
        }
        return nil
    }
}
