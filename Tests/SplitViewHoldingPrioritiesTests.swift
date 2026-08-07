import Testing
import AppKit
@testable import StravaLocal

@Suite("SplitViewHoldingPriorities")
@MainActor
struct SplitViewHoldingPrioritiesTests {
    /// A three-column controller shaped like the one NavigationSplitView builds.
    private func makeController() -> NSSplitViewController {
        let controller = NSSplitViewController()
        for _ in 0..<3 {
            let pane = NSViewController()
            pane.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
            controller.addSplitViewItem(NSSplitViewItem(viewController: pane))
        }
        return controller
    }

    @Test("la liste absorbe, le détail résiste")
    func listAbsorbsAndDetailResists() {
        let controller = makeController()

        #expect(SplitViewHoldingPriorities.configure(controller))

        let priorities = controller.splitViewItems.map(\.holdingPriority)
        // The lowest priority takes on width first — that has to be the list.
        #expect(priorities[1] == priorities.min())
        // And the detail pane must resist more than either neighbour.
        #expect(priorities[2] > priorities[0])
        #expect(priorities[2] > priorities[1])
    }

    @Test("plier la sidebar redimensionne les panneaux, pas la fenêtre")
    func collapsingResizesSiblings() {
        let controller = makeController()

        SplitViewHoldingPriorities.configure(controller)

        #expect(
            controller.splitViewItems[0].collapseBehavior
                == .preferResizingSiblingsWithFixedSplitView
        )
    }

    @Test("réappliquer ne change rien et reste sans effet de bord")
    func configureIsIdempotent() {
        let controller = makeController()

        SplitViewHoldingPriorities.configure(controller)
        let first = controller.splitViewItems.map(\.holdingPriority)
        SplitViewHoldingPriorities.configure(controller)

        #expect(controller.splitViewItems.map(\.holdingPriority) == first)
    }

    @Test("une hiérarchie à deux colonnes est laissée intacte")
    func ignoresUnexpectedShapes() {
        let controller = NSSplitViewController()
        for _ in 0..<2 {
            let pane = NSViewController()
            pane.view = NSView()
            controller.addSplitViewItem(NSSplitViewItem(viewController: pane))
        }
        let before = controller.splitViewItems.map(\.holdingPriority)

        #expect(SplitViewHoldingPriorities.configure(controller) == false)
        #expect(controller.splitViewItems.map(\.holdingPriority) == before)
    }

    @Test("le contrôleur est trouvé même imbriqué dans la hiérarchie")
    func findsNestedController() {
        let splitViewController = makeController()
        let middle = NSViewController()
        middle.view = NSView()
        middle.addChild(splitViewController)
        let root = NSViewController()
        root.view = NSView()
        root.addChild(middle)

        #expect(NSView.firstSplitViewController(in: root) === splitViewController)
        #expect(NSView.firstSplitViewController(in: NSViewController()) == nil)
    }
}
