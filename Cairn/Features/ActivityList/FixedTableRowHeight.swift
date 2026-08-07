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
struct FixedTableRowHeight: NSViewRepresentable {
    /// Spread over half a second: the probe joins a window before the table is
    /// populated, and AppKit posts no "the rows are ready" notification.
    private static let retryDelays: [Duration] = [
        .zero, .milliseconds(50), .milliseconds(250), .milliseconds(750),
    ]

    func makeNSView(context: Context) -> NSView {
        let probe = RowHeightProbeView()
        probe.onAttachToWindow = { [weak probe] in
            Task { @MainActor in
                guard let probe else { return }
                await Self.applyWhenReady(from: probe)
            }
        }
        return probe
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Nothing to do: the work hangs off the probe joining a window.
    }

    @MainActor
    private static func applyWhenReady(from probe: NSView) async {
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
