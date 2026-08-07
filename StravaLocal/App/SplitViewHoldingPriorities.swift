import SwiftUI

/// Decides which column absorbs a width change, so the detail pane holds still.
///
/// Collapsing the sidebar frees its width, and AppKit hands that space to
/// whichever pane resists least — by default the detail pane, so the width the
/// user had dragged never survived a sidebar toggle. Holding priorities invert
/// that: the lowest-priority pane is the first to take on, or give up, width.
///
/// SwiftUI exposes none of this, so a probe reaches into the `NSSplitView` that
/// `NavigationSplitView` is built on. Two earlier attempts set the priorities
/// from `updateNSView`, deferred by one main-queue hop; diagnostics showed that
/// runs while the probe is still detached from any window, so neither ever
/// reached a split view at all. Hence `viewDidMoveToWindow`, which fires exactly
/// when there is a hierarchy to walk.
///
/// Both shapes are handled because which one SwiftUI uses is not contractual: a
/// split view owned by an `NSSplitViewController` takes priorities on its items,
/// a bare one takes them per subview. The probe stays forgiving — finding
/// neither sets nothing, and the layout behaves as it did before.
struct SplitViewHoldingPriorities: NSViewRepresentable {
    /// The list absorbs, the detail pane resists. The sidebar sits between the
    /// two so its own toggle does not come out of the detail pane either.
    static let sidebarPriority = NSLayoutConstraint.Priority.defaultLow + 10
    static let listPriority = NSLayoutConstraint.Priority.defaultLow
    static let detailPriority = NSLayoutConstraint.Priority.defaultHigh

    /// Spread over half a second: a window is assigned before its split view is
    /// populated, and AppKit posts no "the columns are ready" notification.
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

            guard let splitView = probe.enclosingSplitView else {
                Diagnostics.splitView("\(delay): no ancestor split view yet")
                continue
            }
            if apply(to: splitView) { return }
        }
        Diagnostics.splitView("gave up — hierarchy: \(probe.ancestorDescription)")
    }

    /// Sets the priorities on a split view, whichever shape it has.
    ///
    /// Returns false when there are not yet three columns, which is the state
    /// during setup rather than a failure — the caller retries.
    @discardableResult
    @MainActor
    static func apply(to splitView: NSSplitView) -> Bool {
        let priorities = [sidebarPriority, listPriority, detailPriority]

        if let controller = splitView.delegate as? NSSplitViewController {
            let items = controller.splitViewItems
            guard items.count >= 3 else {
                Diagnostics.splitView("controller has \(items.count) items")
                return false
            }
            for (item, priority) in zip(items, priorities) where
                item.holdingPriority != priority {
                item.holdingPriority = priority
            }
            // Keeps the window's width fixed and resizes the panes instead;
            // otherwise AppKit answers a sidebar toggle by resizing the window.
            items[0].collapseBehavior = .preferResizingSiblingsWithFixedSplitView
            Diagnostics.splitView(
                "set on \(items.count) items: "
                    + "\(items.map(\.holdingPriority.rawValue))"
            )
            return true
        }

        let panes = splitView.arrangedSubviews.count
        guard panes >= 3 else {
            Diagnostics.splitView("bare split view has \(panes) panes")
            return false
        }
        for (index, priority) in priorities.enumerated() {
            splitView.setHoldingPriority(priority, forSubviewAt: index)
        }
        Diagnostics.splitView(
            "set on \(panes) bare panes, delegate="
                + "\(splitView.delegate.map { String(describing: type(of: $0)) } ?? "nil")"
        )
        return true
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
    /// The nearest ancestor split view, if any.
    var enclosingSplitView: NSSplitView? {
        var candidate = superview
        while let view = candidate {
            if let splitView = view as? NSSplitView { return splitView }
            candidate = view.superview
        }
        return nil
    }

    /// The chain of ancestor class names, for diagnostics only.
    var ancestorDescription: String {
        var names: [String] = []
        var candidate: NSView? = self
        while let view = candidate {
            names.append(String(describing: type(of: view)))
            candidate = view.superview
        }
        let root = window?.contentViewController
        names.append("vc=" + (root.map { String(describing: type(of: $0)) } ?? "nil"))
        return names.joined(separator: " < ")
    }
}
