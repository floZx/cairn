import SwiftUI

/// Decides which column absorbs a width change, so the detail pane holds still.
///
/// Collapsing the sidebar frees its width, and AppKit hands that space to
/// whichever pane resists least — by default the detail pane, so the width the
/// user had dragged never survived a sidebar toggle.
///
/// The lever is `NSSplitViewItem.holdingPriority`: "the view with the lowest
/// priority will be the first to take on additional width". A first attempt set
/// priorities on the `NSSplitView`'s subviews instead, which did nothing —
/// `NavigationSplitView` is driven by an `NSSplitViewController`, and its items'
/// priorities win over anything set on the split view directly.
///
/// SwiftUI exposes none of this, so the probe locates the controller in the
/// window. It is deliberately forgiving: if it is not found, nothing is set and
/// the layout behaves exactly as it did before.
struct SplitViewHoldingPriorities: NSViewRepresentable {
    /// The list absorbs, the detail pane resists. The sidebar sits between the
    /// two so its own toggle never comes out of the detail pane.
    private static let sidebarPriority: NSLayoutConstraint.Priority = .init(250)
    private static let listPriority: NSLayoutConstraint.Priority = .init(200)
    private static let detailPriority: NSLayoutConstraint.Priority = .init(300)

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Reapplied on every layout pass rather than once: SwiftUI reconfigures
        // its split view items as the columns change, which would otherwise undo
        // this. Each pass is a few comparisons, and writes only on a difference.
        DispatchQueue.main.async {
            guard let controller = view.enclosingSplitViewController else { return }
            Self.configure(controller)
        }
    }

    /// Applies the priorities to a controller's three columns.
    ///
    /// Separate from the probe so it can be tested against a hand-built
    /// controller: whether SwiftUI's hierarchy is the shape we expect can only
    /// be seen by running the app, but this part need not be taken on trust.
    /// Does nothing unless there are three columns to arrange.
    @discardableResult
    static func configure(_ controller: NSSplitViewController) -> Bool {
        let items = controller.splitViewItems
        guard items.count >= 3 else { return false }

        apply(sidebarPriority, to: items[0])
        apply(listPriority, to: items[1])
        apply(detailPriority, to: items[2])

        // Keeps the window's width fixed and resizes the panes instead. The
        // alternative grows or shrinks the window itself, which would be a
        // stranger answer to folding a sidebar.
        if items[0].collapseBehavior != .preferResizingSiblingsWithFixedSplitView {
            items[0].collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        }
        return true
    }

    private static func apply(
        _ priority: NSLayoutConstraint.Priority, to item: NSSplitViewItem
    ) {
        guard item.holdingPriority != priority else { return }
        item.holdingPriority = priority
    }
}

extension NSView {
    /// The split view controller driving this view's window, if there is one.
    ///
    /// Found from the window rather than by walking up from the probe: the probe
    /// sits inside one column, and its ancestors need not include the controller
    /// that owns all three.
    var enclosingSplitViewController: NSSplitViewController? {
        if let root = window?.contentViewController,
           let found = Self.firstSplitViewController(in: root) {
            return found
        }
        // Fallback: the split view's delegate is usually the controller itself.
        var candidate: NSView? = superview
        while let view = candidate {
            if let splitView = view as? NSSplitView {
                return splitView.delegate as? NSSplitViewController
            }
            candidate = view.superview
        }
        return nil
    }

    static func firstSplitViewController(
        in controller: NSViewController
    ) -> NSSplitViewController? {
        if let splitViewController = controller as? NSSplitViewController {
            return splitViewController
        }
        for child in controller.children {
            if let found = firstSplitViewController(in: child) { return found }
        }
        return nil
    }
}
