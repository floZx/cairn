import AppKit
import SwiftUI

/// Gives the keyboard back to the content when a motion key fell into nothing.
///
/// The vim keys only work while the content — or something inside it — has
/// the keyboard, and a click almost anywhere else takes it away without a
/// sign: `j`, `k` and `g` then did nothing until a click back in the list.
///
/// Sits at the very end of the window's responder chain, so it only ever
/// hears the presses nobody took: a key the list handled never reaches it.
/// A first version guessed from SwiftUI's focus who held the keyboard, and
/// guessed wrong whenever the table inside a view held it — it caught nearly
/// every `j`, and the replays scrambled the keyboard (the trace of 30
/// September). Here nothing is guessed: arriving here is the proof.
///
/// The press is then played again once the content has the keyboard, and
/// every key typed meanwhile waits behind it, so `gn` stays `g` then `n`.
@MainActor
final class VimFocusRescue: NSResponder {
    /// `j`/`k` walk, `J`/`K` scroll the pane, `g` starts every jump.
    static let keys: Set<String> = ["j", "k", "J", "K", "g"]

    /// SwiftUI sets the focus on its next update, and a press played back
    /// before it lands on the same nothing.
    private static let settle: Duration = .milliseconds(40)

    private var reclaim: () -> Void = {}
    private weak var window: NSWindow?
    private var monitor: Any?
    /// The rescued press and every one typed after it, in order.
    private var held: [NSEvent] = []
    /// The presses played back: let through the queue, and, should one fall
    /// here again, passed on — a key lost, never a key looping.
    private var replayed: [(timestamp: TimeInterval, keyCode: UInt16)] = []

    func install(in window: NSWindow, reclaim: @escaping () -> Void) {
        self.reclaim = reclaim
        // Back in the chain if something rebuilt it since.
        if !isInChain(of: window) {
            nextResponder = window.nextResponder
            window.nextResponder = self
        }
        guard self.window !== window else { return }
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // A `Bool` crosses back, not the event: `assumeIsolated` hands its
            // result out of the actor and `NSEvent` is not `Sendable` — the
            // rule `DeselectOnRepeatClick` follows.
            let swallowed = MainActor.assumeIsolated { self?.queue(event) ?? false }
            return swallowed ? nil : event
        }
    }

    private func isInChain(of window: NSWindow) -> Bool {
        var responder = window.nextResponder
        while let current = responder {
            if current === self { return true }
            responder = current.nextResponder
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        if let index = replayedIndex(of: event) {
            replayed.remove(at: index)
            super.keyDown(with: event)
            return
        }
        guard Self.isRescuable(event, in: window) else {
            super.keyDown(with: event)
            return
        }
        Log.keyboard.info("clavier rendu au contenu sur « \(event.charactersIgnoringModifiers ?? "", privacy: .public) »")
        reclaim()
        held = [event]
        replayed = []
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settle)
            self?.replayHeld()
        }
    }

    /// While a rescue settles, whatever is typed waits its turn behind it.
    private func queue(_ event: NSEvent) -> Bool {
        guard !held.isEmpty, event.window === window, replayedIndex(of: event) == nil
        else { return false }
        held.append(event)
        return true
    }

    private func replayHeld() {
        let events = held
        held = []
        replayed = events.map { ($0.timestamp, $0.keyCode) }
        for event in events { NSApp.postEvent(event, atStart: false) }
    }

    private func replayedIndex(of event: NSEvent) -> Int? {
        replayed.firstIndex { $0.timestamp == event.timestamp && $0.keyCode == event.keyCode }
    }

    private static func isRescuable(_ event: NSEvent, in window: NSWindow?) -> Bool {
        guard let characters = event.charactersIgnoringModifiers, keys.contains(characters),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let window, event.window === window, window.attachedSheet == nil
        else { return false }
        if let text = window.firstResponder as? NSTextView, text.isEditable { return false }
        return true
    }
}

/// Puts a `VimFocusRescue` at the end of the chain of the window it lands in.
struct VimFocusRescueInstaller: NSViewRepresentable {
    let rescue: VimFocusRescue
    let reclaim: () -> Void

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onWindow = { [rescue, reclaim] window in rescue.install(in: window, reclaim: reclaim) }
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.onWindow = { [rescue, reclaim] window in rescue.install(in: window, reclaim: reclaim) }
        if let window = probe.window { rescue.install(in: window, reclaim: reclaim) }
    }

    final class Probe: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
