import SwiftUI

/// Decides which column absorbs a width change, so the detail pane holds still.
///
/// Collapsing the sidebar frees its width, and AppKit hands that space to
/// whichever pane resists least. By default the detail pane grew, which meant
/// the width the user had dragged never survived a sidebar toggle. Holding
/// priorities fix that: the lowest-priority pane is the first to take on — or
/// give up — width, so the list absorbs and the detail stays put.
///
/// SwiftUI exposes no API for this, so the probe walks up to the `NSSplitView`
/// that `NavigationSplitView` is built on. It is deliberately forgiving: if the
/// hierarchy ever changes shape the split view simply is not found, nothing is
/// set, and the layout behaves exactly as it did before.
struct SplitViewHoldingPriorities: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // A zero-size, non-drawing probe: it exists only to reach its ancestors.
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Deferred: on the first update the probe is not in the window yet, so
        // there is no ancestor split view to find.
        DispatchQueue.main.async {
            guard let splitView = view.enclosingSplitView else { return }
            let panes = splitView.arrangedSubviews.count
            guard panes >= 3 else { return }

            // Lowest priority absorbs first. The list is the elastic one; the
            // detail pane resists; the sidebar sits between the two so toggling
            // it does not come out of the detail pane either.
            splitView.setHoldingPriority(.defaultLow + 10, forSubviewAt: 0)
            splitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
            splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 2)
        }
    }
}

private extension NSView {
    /// The nearest ancestor split view, if any.
    var enclosingSplitView: NSSplitView? {
        var candidate = superview
        while let view = candidate {
            if let splitView = view as? NSSplitView { return splitView }
            candidate = view.superview
        }
        return nil
    }
}
