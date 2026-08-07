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

    /// A split view with three panes and no controller behind it.
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

    @Test("la liste absorbe, le détail résiste")
    func listAbsorbsAndDetailResists() {
        let controller = makeController()

        #expect(SplitViewHoldingPriorities.apply(to: controller.splitView))

        let priorities = controller.splitViewItems.map(\.holdingPriority)
        // The lowest priority takes on width first — that has to be the list.
        #expect(priorities[1] == priorities.min())
        #expect(priorities[2] > priorities[1])
    }

    @Test("l'écart de priorité reste faible pour ne pas bloquer le séparateur")
    func prioritiesStayGentle() {
        // A holding priority *is* the priority of a width constraint. Set high
        // enough, it outranks the constraint AppKit installs while dragging a
        // divider and the pane stops being resizable — which is what
        // `.defaultHigh` did. Only the ordering matters.
        #expect(
            SplitViewHoldingPriorities.listPriority
                < SplitViewHoldingPriorities.detailPriority
        )
        #expect(
            SplitViewHoldingPriorities.detailPriority
                < NSLayoutConstraint.Priority.defaultHigh
        )
    }

    @Test("la sidebar garde sa priorité par défaut")
    func leavesTheSidebarAlone() {
        let controller = makeController()
        let before = controller.splitViewItems[0].holdingPriority

        SplitViewHoldingPriorities.apply(to: controller.splitView)

        // It is the pane being collapsed, never a candidate for the width it
        // frees, so there is nothing to gain by touching it.
        #expect(controller.splitViewItems[0].holdingPriority == before)
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

        // A split view with no controller behind it is left alone too, rather
        // than guessed at: the shape SwiftUI really uses has one.
        #expect(SplitViewHoldingPriorities.apply(to: makeBareSplitView()) == false)
    }

    @Test("le split view est trouvé même s'il n'est pas un ancêtre de la sonde")
    func findsSplitViewAmongDescendants() {
        // The real shape: the probe is a sibling of the split view, both under
        // the window's content view. An ancestor walk finds nothing here.
        let contentView = NSView()
        let splitView = makeBareSplitView()
        let wrapper = NSView()
        wrapper.addSubview(splitView)
        contentView.addSubview(wrapper)
        contentView.addSubview(NSView())

        #expect(contentView.descendantSplitViews() == [splitView])
        #expect(NSView().descendantSplitViews().isEmpty)
    }
}
