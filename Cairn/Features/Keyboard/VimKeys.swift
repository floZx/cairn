import SwiftUI

/// Turns key presses into `VimCommand`s for whichever view is on screen.
///
/// Extracted from the list because the list is not always what is showing: the
/// statistics and the global map can both open the detail pane now, so both must
/// be able to close it again. A handler that lives only on the table works in
/// exactly one of the three places.
///
/// Each view gets its own buffer, which is what we want: a count typed in one
/// view has no business surviving a jump to another.
struct VimKeys: ViewModifier {
    /// Returns whether the command was acted on. A view that cannot carry one
    /// out says so, and the press falls through rather than being swallowed.
    let onCommand: (VimCommand) -> Bool

    @State private var buffer = VimKeyBuffer()

    func body(content: Content) -> some View {
        content
            .focusable()
            // No ring: these views are not form controls, and a focus ring
            // around a whole pane reads as a bug.
            .focusEffectDisabled()
            .onKeyPress { press in
                guard let character = press.characters.first else { return .ignored }
                // ⌘ belongs to the menus. Swallowing it here would shadow every
                // shortcut the app already publishes.
                guard !press.modifiers.contains(.command) else { return .ignored }

                guard let command = buffer.accept(
                    character, control: press.modifiers.contains(.control)
                ) else {
                    // A digit or a `g` was consumed even though nothing ran, and
                    // saying so is what stops it reaching a table's type-select.
                    return buffer.isEmpty ? .ignored : .handled
                }
                return onCommand(command) ? .handled : .ignored
            }
            .onKeyPress(.escape) {
                buffer.reset()
                return onCommand(.clear) ? .handled : .ignored
            }
    }
}

extension View {
    func vimKeys(_ onCommand: @escaping (VimCommand) -> Bool) -> some View {
        modifier(VimKeys(onCommand: onCommand))
    }
}
