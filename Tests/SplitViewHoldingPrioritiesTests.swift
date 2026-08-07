import Testing
import AppKit
@testable import StravaLocal

@Suite("SplitViewHoldingPriorities")
@MainActor
struct SplitViewHoldingPrioritiesTests {
    /// A three-column controller shaped like the one NavigationSplitView may
    /// build. Its split view's delegate is the controller itself.
    private func makeController() -> NSSplitViewController {
        let controller = NSSplitViewController()
        for _ in 0..<3 {
            let pane = NSViewController()
            pane.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
            controller.addSplitViewItem(NSSplitViewItem(viewController: pane))
        }
        return controller
    }

    /// A split view with three panes and no controller behind it — the other
    /// shape SwiftUI might present.
    private func makeBareSplitView(panes: Int = 3) -> NSSplitView {
        let splitView = NSSplitView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 400)
        )
        splitView.isVertical = true
        for _ in 0..<panes {
            splitView.addArrangedSubview(
                NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
            )
        }
        return splitView
    }

    @Test("sur un contrôleur : la liste absorbe, le détail résiste")
    func listAbsorbsAndDetailResistsOnController() {
        let controller = makeController()

        #expect(SplitViewHoldingPriorities.apply(to: controller.splitView))

        let priorities = controller.splitViewItems.map(\.holdingPriority)
        // The lowest priority takes on width first — that has to be the list.
        #expect(priorities[1] == priorities.min())
        // And the detail pane must resist more than either neighbour.
        #expect(priorities[2] > priorities[0])
        #expect(priorities[2] > priorities[1])
    }

    @Test("un split view nu est traité aussi, sans contrôleur derrière")
    func handlesBareSplitView() {
        let splitView = makeBareSplitView()

        // AppKit exposes only the setter, so the values cannot be read back;
        // what matters here is that this shape is recognised and served.
        #expect(SplitViewHoldingPriorities.apply(to: splitView))
    }

    @Test("l'ordre des priorités : la liste absorbe, le détail résiste")
    func priorityOrderIsCorrect() {
        // The lowest priority takes on width first, so it must be the list; the
        // detail pane resists more than either neighbour.
        #expect(
            SplitViewHoldingPriorities.listPriority
                < SplitViewHoldingPriorities.sidebarPriority
        )
        #expect(
            SplitViewHoldingPriorities.sidebarPriority
                < SplitViewHoldingPriorities.detailPriority
        )
    }

    @Test("plier la sidebar redimensionne les panneaux, pas la fenêtre")
    func collapsingResizesSiblings() {
        let controller = makeController()

        SplitViewHoldingPriorities.apply(to: controller.splitView)

        #expect(
            controller.splitViewItems[0].collapseBehavior
                == .preferResizingSiblingsWithFixedSplitView
        )
    }

    @Test("réappliquer ne change rien et reste sans effet de bord")
    func applyIsIdempotent() {
        let controller = makeController()

        SplitViewHoldingPriorities.apply(to: controller.splitView)
        let first = controller.splitViewItems.map(\.holdingPriority)
        SplitViewHoldingPriorities.apply(to: controller.splitView)

        #expect(controller.splitViewItems.map(\.holdingPriority) == first)
    }

    @Test("une hiérarchie incomplète est laissée intacte")
    func ignoresUnexpectedShapes() {
        let controller = NSSplitViewController()
        for _ in 0..<2 {
            let pane = NSViewController()
            pane.view = NSView()
            controller.addSplitViewItem(NSSplitViewItem(viewController: pane))
        }
        let before = controller.splitViewItems.map(\.holdingPriority)

        #expect(SplitViewHoldingPriorities.apply(to: controller.splitView) == false)
        #expect(controller.splitViewItems.map(\.holdingPriority) == before)

        // A bare split view that is not yet populated is left alone too, so the
        // probe retries rather than settling for a two-pane arrangement.
        #expect(SplitViewHoldingPriorities.apply(to: makeBareSplitView(panes: 2)) == false)
    }

    @Test("la sonde retrouve le split view depuis une colonne")
    func findsSplitViewFromInsideAColumn() {
        let splitView = makeBareSplitView()
        let probe = NSView()
        // Nested two levels deep, as a `.background()` probe would be.
        let container = NSView()
        container.addSubview(probe)
        splitView.arrangedSubviews[1].addSubview(container)

        #expect(probe.enclosingSplitView === splitView)
        #expect(NSView().enclosingSplitView == nil)
    }

    @Test("la description de la hiérarchie nomme les ancêtres")
    func describesAncestors() {
        let splitView = makeBareSplitView()
        let probe = NSView()
        splitView.arrangedSubviews[0].addSubview(probe)

        let description = probe.ancestorDescription
        #expect(description.contains("NSSplitView"))
        // No window in a test, so the controller slot is reported as absent
        // rather than silently omitted.
        #expect(description.contains("vc=nil"))
    }
}
