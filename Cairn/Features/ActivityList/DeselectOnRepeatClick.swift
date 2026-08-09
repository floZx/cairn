import SwiftUI

/// The rule itself, kept apart from the AppKit plumbing so it can be tested.
enum RepeatClickDeselection {
    /// Whether a plain left click on `clickedRow` should clear the selection.
    ///
    /// Only when that row is the whole selection: with several rows selected,
    /// a plain click collapses the selection onto the one clicked — standard
    /// behaviour everywhere in macOS, and not something to turn into a
    /// deselect.
    static func shouldDeselect(clickedRow: Int, selected: IndexSet) -> Bool {
        clickedRow >= 0 && selected.count == 1 && selected.contains(clickedRow)
    }
}

/// Clicking the row that is already selected clears the selection.
///
/// Neither `List` nor `Table` reports that click: AppKit selects on mouse
/// down, sees the selection is unchanged, and the SwiftUI binding is never
/// written — so there is nothing for `onChange` to catch, and no gesture that
/// can tell the two cases apart after the fact. A local event monitor sees
/// the click before the table acts on it, and the probe the row-height fix
/// already uses finds the table to ask which row it landed on.
struct DeselectOnRepeatClick: NSViewRepresentable {
    /// Called when the click was a click on the already-selected row.
    var onDeselect: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let probe = NSView(frame: .zero)
        context.coordinator.probe = probe
        context.coordinator.onDeselect = onDeselect
        context.coordinator.startMonitoring()
        return probe
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Refreshed on every update: the closure captures the selection
        // binding, and a copy kept from the first build would write to a
        // binding that is no longer the one on screen.
        context.coordinator.onDeselect = onDeselect
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    @MainActor
    final class Coordinator {
        fileprivate var probe: NSView?
        fileprivate var onDeselect: () -> Void = {}
        private var monitor: Any?

        fileprivate func startMonitoring() {
            guard monitor == nil else { return }
            // Local, so only this app's own clicks are seen, and the handler
            // runs on the main thread by contract.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) {
                [weak self] event in
                // A `Bool` crosses back, not the event: `assumeIsolated` hands
                // its result out of the actor and `NSEvent` is not `Sendable`.
                let swallowed = MainActor.assumeIsolated {
                    self?.handle(event) ?? false
                }
                return swallowed ? nil : event
            }
        }

        fileprivate func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Returns whether the click was consumed as a deselection.
        private func handle(_ event: NSEvent) -> Bool {
            // Modified clicks build a selection rather than replace it, and a
            // double click is two events of which only the first is ours to
            // consider — neither should deselect.
            guard event.clickCount == 1,
                  event.modifierFlags
                      .intersection([.command, .shift, .option, .control]).isEmpty,
                  let probe,
                  let table = FixedTableRowHeight.tableView(near: probe),
                  let window = table.window,
                  event.window === window,
                  // Hit-tested rather than merely converted: the sidebar is an
                  // `NSTableView` too, and a click there converts into a
                  // perfectly plausible row index of this one.
                  let hit = window.contentView?.hitTest(event.locationInWindow),
                  hit.isDescendant(of: table)
            else { return false }

            let point = table.convert(event.locationInWindow, from: nil)
            guard RepeatClickDeselection.shouldDeselect(
                clickedRow: table.row(at: point), selected: table.selectedRowIndexes
            ) else { return false }

            onDeselect()
            // The caller swallows it: letting the click reach the table would
            // select again the row the selection was just cleared of.
            return true
        }
    }
}
